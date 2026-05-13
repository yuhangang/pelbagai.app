import Foundation
import MLX
import MLXLMCommon
import MLXLLM
import MLXVLM
import Combine

/// Thread-safe state for nonisolated GPU access checks during synchronous generation closures.
final class GPUForegroundState: @unchecked Sendable {
    static let shared = GPUForegroundState()
    private let lock = NSLock()
    private var _isAllowed = true
    
    var isAllowed: Bool {
        get {
            lock.withLock { _isAllowed }
        }
        set {
            lock.withLock { _isAllowed = newValue }
        }
    }
}

/// Centralized manager for MLX model lifecycle to prevent redundant memory usage.
@MainActor
class MLXModelManager: ObservableObject {
    static let shared = MLXModelManager()

    private static let gibibyte: UInt64 = 1024 * 1024 * 1024
    
    @Published var container: ModelContainer?
    @Published var isLoaded: Bool = false
    @Published var isLoading: Bool = false
    @Published var status: String = ""
    @Published var currentModelID: String?
    @Published var isForeground: Bool = true
    @Published var preferredBackend: MLXBackend = .gpu
    
    private var activeLoadTask: Task<ModelContainer, Error>?
    private var activeLoadModelID: String?
    private var activeLoadToken: UUID?
    
    private init() {
        let cacheLimit = Self.recommendedCacheLimit(forPhysicalMemory: ProcessInfo.processInfo.physicalMemory)
        Memory.cacheLimit = Int(cacheLimit)
        
        // Use recommended cache limit. The 20MB limit was too restrictive for VLMs.
        MLX.GPU.set(cacheLimit: Int(cacheLimit))
        
        // Load saved backend preference
        if let saved = UserDefaults.standard.string(forKey: "mlxBackend"),
           let backend = MLXBackend(rawValue: saved) {
            self.preferredBackend = backend
        }
        
        // Apply default device immediately
        let device: Device = preferredBackend == .gpu ? .gpu : .cpu
        Device.setDefault(device: device)
        
        print("🧠 [MLXModelManager] Initialized with backend: \(preferredBackend.displayName) (Device: \(device))")
        print("🧠 [MLXModelManager] Configured MLX cache limit: \(Self.formatBytes(cacheLimit))")
        setupLifecycleObservers()
    }
    
    private func setupLifecycleObservers() {
        // Observers will be handled by SwiftUI ScenePhase in the App/View layer
        // which will call handleBackground() or handleForeground()
    }
    
    func handleBackground() {
        isForeground = false
        GPUForegroundState.shared.isAllowed = false
        clearCache()
        print("🧠 [MLXModelManager] App backgrounded, GPU yielded")
    }
    
    func handleForeground() {
        isForeground = true
        GPUForegroundState.shared.isAllowed = true
    }
    
    nonisolated func isForegroundGPUAllowed() -> Bool {
        GPUForegroundState.shared.isAllowed
    }
    
    /// Updates the preferred backend and persists it.
    func setPreferredBackend(_ backend: MLXBackend) {
        guard preferredBackend != backend else { return }
        preferredBackend = backend
        UserDefaults.standard.set(backend.rawValue, forKey: "mlxBackend")
        print("🧠 [MLXModelManager] Preferred backend set to: \(backend.displayName)")
    }
    
    /// Loads a model container if it's not already loaded or if the model ID has changed.
    func loadModel(modelID: String, progressHandler: @Sendable @escaping (Progress) -> Void = { _ in }) async throws {
        if isLoaded && currentModelID == modelID {
            return
        }

        if let activeLoadTask {
            if activeLoadModelID == modelID {
                _ = try await activeLoadTask.value
                return
            }

            _ = try await activeLoadTask.value
            if isLoaded && currentModelID == modelID {
                return
            }
        }
        
        // Unload existing if different
        if currentModelID != modelID {
            await unloadModel()
        }
        
        isLoading = true
        activeLoadModelID = modelID
        let loadToken = UUID()
        activeLoadToken = loadToken
        
        status = "Initializing..."
        
        // Set the MLX default device based on preference
        let device: Device = preferredBackend == .gpu ? .gpu : .cpu
        Device.setDefault(device: device)
        print("🧠 [MLXModelManager] Loading model: \(modelID) on device: \(device)")

        let loadTask = Task<ModelContainer, Error> {
            let modelConfig: ModelConfiguration
            if modelID.contains("gemma-4-") {
                modelConfig = VLMModelFactory.shared.configuration(id: modelID)
            } else {
                modelConfig = ModelConfiguration(id: modelID)
            }
            return try await loadRemoteModelContainer(
                configuration: modelConfig,
                progressHandler: { progress in
                    let percent = Int(progress.fractionCompleted * 100)
                    Task { @MainActor in
                        if percent < 100 {
                            self.status = "Downloading: \(percent)%"
                        } else {
                            self.status = "Loading weights..."
                        }
                    }
                    progressHandler(progress)
                }
            )
        }
        activeLoadTask = loadTask

        defer {
            if activeLoadToken == loadToken {
                activeLoadTask = nil
                activeLoadModelID = nil
                activeLoadToken = nil
            }
            isLoading = false
        }

        do {
            let newContainer = try await loadTask.value
            self.container = newContainer
            self.currentModelID = modelID
            self.isLoaded = true
            self.status = "Ready"
            print("🧠 [MLXModelManager] Model loaded successfully")
        } catch {
            if activeLoadModelID == modelID {
                self.container = nil
                self.currentModelID = nil
                self.isLoaded = false
            }
            self.status = "Load failed: \(error.localizedDescription)"
            print("🧠 [MLXModelManager] Load failed: \(error)")
            throw error
        }
    }
    
    /// Releases the model container and clears the GPU cache.
    func unloadModel() async {
        print("🧠 [MLXModelManager] Unloading model")
        container = nil
        currentModelID = nil
        isLoaded = false
        status = ""
        clearCache()
    }
    
    /// Explicitly clears the MLX GPU cache to free up memory.
    func clearCache() {
        print("🧠 [MLXModelManager] Clearing GPU cache")
        Memory.clearCache()
    }

    private static func recommendedCacheLimit(forPhysicalMemory physicalMemory: UInt64) -> UInt64 {
        switch physicalMemory {
        case ..<(8 * gibibyte):
            // Keep older/lower-memory devices on the most conservative tier.
            return 256 * 1024 * 1024
        case ..<(12 * gibibyte):
            // Give 8 GB class devices a bit more cache without assuming lots of
            // free headroom after weights, app heap, media buffers, and OS use.
            return 512 * 1024 * 1024
        default:
            // 12 GB class devices still should not hand MLX half the device RAM.
            // Start at 1 GB and tune upward only from measured device runs.
            return 1024 * 1024 * 1024
        }
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }
}

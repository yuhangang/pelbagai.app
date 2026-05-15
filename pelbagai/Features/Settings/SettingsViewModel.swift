import SwiftUI
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    let environment: AppEnvironment
    @Published var isLoading = false
    @Published var loadingStatus = ""
    @Published var selectedModel: GemmaModel = .e2b // Default, will sync
    @Published var preferredBackend: MLXBackend = .gpu
    @Published var isModelLoaded: Bool = false
    @Published var isDownloading: Bool = false
    @Published var downloadingModel: GemmaModel?
    @Published var downloadProgress: Double = 0
    
    @Published var showDownloadWarning = false
    @Published var pendingModel: GemmaModel?
    
    private var cancellables = Set<AnyCancellable>()
    
    init(environment: AppEnvironment) {
        self.environment = environment
        self.selectedModel = environment.gemma.selectedModel
        self.preferredBackend = environment.mlx.preferredBackend
        
        setupBindings()
    }
    
    private func setupBindings() {
        environment.mlx.$isLoading
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.isLoading = $0 }
            .store(in: &cancellables)
            
        environment.mlx.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.loadingStatus = $0 }
            .store(in: &cancellables)
            
        environment.gemma.$selectedModel
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.selectedModel = $0 }
            .store(in: &cancellables)
            
        environment.mlx.$preferredBackend
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.preferredBackend = $0 }
            .store(in: &cancellables)
            
        environment.gemma.$isDownloading
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.isDownloading = $0 }
            .store(in: &cancellables)
            
        environment.gemma.$downloadProgress
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.downloadProgress = $0 }
            .store(in: &cancellables)
            
        environment.gemma.$downloadingModel
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.downloadingModel = $0 }
            .store(in: &cancellables)
    }
    
    func switchModel(to model: GemmaModel) {
        guard model != selectedModel else { return }
        
        // Update local state immediately for UI responsiveness
        selectedModel = model
        
        Task {
            await environment.gemma.switchModel(to: model)
        }
    }
    
    func downloadModel(_ model: GemmaModel) {
        if NetworkService.shared.isCellularOrHotspot {
            pendingModel = model
            showDownloadWarning = true
            return
        }
        
        performManualDownload(model: model)
    }
    
    private func performManualDownload(model: GemmaModel) {
        Task {
            await environment.gemma.downloadModel(model)
        }
    }
    
    func deleteModel(_ model: GemmaModel) {
        Task {
            await environment.gemma.deleteModel(model)
        }
    }
    
    func confirmDownload() {
        if let model = pendingModel {
            performManualDownload(model: model)
            pendingModel = nil
        }
        showDownloadWarning = false
    }
    
    func cancelDownload() {
        pendingModel = nil
        showDownloadWarning = false
    }

    func setGemma4AudioInputEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "gemma4AudioInputEnabled")

        Task {
            let wasLoaded = environment.gemma.isModelLoaded
            await environment.unloadAllModels()

            if wasLoaded, environment.gemma.selectedModel.isDownloaded {
                _ = await environment.gemma.loadModel()
            }
        }
    }
    
    private func performModelSwitch(to newModel: GemmaModel) {
        Task {
            await environment.unloadAllModels()
            await environment.gemma.switchModel(to: newModel)
        }
    }
    
    func switchBackend(to newBackend: MLXBackend) {
        guard newBackend != preferredBackend else { return }
        
        Task {
            let previousModelID = environment.mlx.currentModelID
            // Always offload everything before switching hardware backends
            await environment.unloadAllModels()
            
            environment.mlx.setPreferredBackend(newBackend)
            
            // If a model was already loaded, we need to reload it to apply the new backend
            if let currentID = previousModelID {
                print("🧠 [SettingsViewModel] Reloading model \(currentID) to apply \(newBackend.displayName) backend")
                do {
                    try await environment.mlx.loadModel(modelID: currentID)
                } catch {
                    print("🧠 [SettingsViewModel] Failed to reload model after backend switch: \(error)")
                }
            }
        }
    }
}

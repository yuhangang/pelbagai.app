import SwiftUI
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    let environment: AppEnvironment
    @Published var isLoading = false
    @Published var loadingStatus = ""
    @Published var selectedModel: GemmaModel = .e2b // Default, will sync
    @Published var preferredBackend: MLXBackend = .gpu
    
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
    }
    
    func switchModel(to newModel: GemmaModel) {
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

import SwiftUI
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    let environment: AppEnvironment
    @Published var isLoading = false
    @Published var loadingStatus = ""
    @Published var selectedModel: GemmaModel = .e2b // Default, will sync
    
    private var cancellables = Set<AnyCancellable>()
    
    init(environment: AppEnvironment) {
        self.environment = environment
        self.selectedModel = environment.gemma.selectedModel
        
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
    }
    
    func switchModel(to newModel: GemmaModel) {
        Task {
            await environment.gemma.switchModel(to: newModel)
        }
    }
}

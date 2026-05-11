import SwiftUI
import Combine

@MainActor
class ToolDataViewModel: ObservableObject {
    private let environment: AppEnvironment
    
    @Published var toolCatalog: [ToolInfo] = []
    @Published var userDefinitions: [LocalToolDefinition] = []
    @Published var allDefinitions: [LocalToolDefinition] = []
    @Published var totalResultCount: Int = 0
    @Published var totalStorageSize: String = "0 KB"
    
    private var cancellables = Set<AnyCancellable>()
    
    init(environment: AppEnvironment) {
        self.environment = environment
        setupBindings()
        refresh()
    }
    
    private func setupBindings() {
        environment.storage.$toolCatalog
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.toolCatalog = $0 }
            .store(in: &cancellables)
            
        environment.registry.$userDefinitions
            .receive(on: RunLoop.main)
            .map { $0.values.sorted { $0.displayName < $1.displayName } }
            .sink { [weak self] in self?.userDefinitions = $0 }
            .store(in: &cancellables)
            
        environment.registry.$allDefinitions
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.allDefinitions = $0 }
            .store(in: &cancellables)
            
        environment.storage.$totalResultCount
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.totalResultCount = $0 }
            .store(in: &cancellables)
        
        // Timer-based disk size refresh or manual
        environment.storage.$toolCatalog
            .receive(on: RunLoop.main)
            .map { _ in self.environment.storage.totalStorageSize }
            .sink { [weak self] in self?.totalStorageSize = $0 }
            .store(in: &cancellables)
    }
    
    func refresh() {
        environment.storage.refreshCatalog()
    }
    
    func clearAll() {
        environment.storage.clearAll()
        refresh()
    }
    
    func clearTool(_ toolID: String) {
        environment.storage.clearTool(toolID)
        refresh()
    }
    
    func deleteUserDefinition(toolID: String) {
        environment.registry.deleteUserDefinition(toolID: toolID)
    }
    
    func resetUserDefinitions() {
        environment.registry.resetUserDefinitions()
    }
    
    func isUserDefinition(_ toolID: String) -> Bool {
        environment.registry.isUserDefinition(toolID)
    }
    
    func loadAllResults(for toolID: String) -> [ScanResult] {
        environment.storage.loadAll(from: toolID)
    }
}

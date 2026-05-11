import SwiftUI
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    @Published var recentSessions: [ChatSession] = []
    @Published var chatSearchText: String = ""
    @Published var chatInputMode: ChatInputMode = .chat
    
    // Model state mirroring from managers
    @Published var totalResultCount: Int = 0
    @Published var isGenerating = false
    @Published var isLoadingModels = false
    @Published var isModelLoaded = false
    @Published var userDefinitionsCount = 0
    @Published var allDefinitions: [LocalToolDefinition] = []
    
    private let environment: AppEnvironment
    private var cancellables = Set<AnyCancellable>()
    
    init(environment: AppEnvironment) {
        self.environment = environment
        setupBindings()
        loadData()
    }
    
    private func setupBindings() {
        environment.storage.$totalResultCount
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.totalResultCount = $0 }
            .store(in: &cancellables)
            
        environment.gemma.$isGenerating
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.isGenerating = $0 }
            .store(in: &cancellables)
            
        environment.mlx.$isLoading
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.isLoadingModels = $0 }
            .store(in: &cancellables)
        
        environment.registry.$userDefinitions
            .receive(on: RunLoop.main)
            .map { $0.count }
            .sink { [weak self] in self?.userDefinitionsCount = $0 }
            .store(in: &cancellables)
        
        environment.registry.$allDefinitions
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.allDefinitions = $0 }
            .store(in: &cancellables)
        
        // Timer for model loaded state
        Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.isModelLoaded = self.environment.gemma.isModelLoaded
            }
            .store(in: &cancellables)
            
        // Listen for session updates
        NotificationCenter.default.publisher(for: .sessionUpdated)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadData()
            }
            .store(in: &cancellables)
    }
    
    func loadData() {
        recentSessions = environment.database.getAllSessions()
    }
    
    var filteredSessions: [ChatSession] {
        if chatSearchText.isEmpty {
            return recentSessions
        }
        return recentSessions.filter { $0.title.localizedCaseInsensitiveContains(chatSearchText) }
    }
    
    var defaultTools: [LocalToolDefinition] {
        allDefinitions.filter { !environment.registry.isUserDefinition($0.toolID) }
    }
    
    var customTools: [LocalToolDefinition] {
        allDefinitions.filter { environment.registry.isUserDefinition($0.toolID) }
    }
    
    func startNewQuickChat() -> UUID {
        let title = chatSearchText.isEmpty ? "New Chat" : chatSearchText
        let newSession: ChatSession
        if chatSearchText.isEmpty {
            newSession = environment.database.getOrCreateEmptySession(title: title)
        } else {
            newSession = environment.database.createSession(title: title)
        }
        chatSearchText = ""
        loadData()
        return newSession.id
    }
}

import SwiftUI
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    @Published var recentSessions: [ChatSession] = []
    @Published var chatSearchText: String = ""
    @Published var chatInputMode: ChatInputMode = .chat
    @Published var pendingImage: UIImage? = nil
    
    // Model state mirroring from managers
    @Published var totalResultCount: Int = 0
    @Published var isGenerating = false
    @Published var isLoadingModels = false
    @Published var isModelLoaded = false
    @Published var userDefinitionsCount = 0
    @Published var allDefinitions: [LocalToolDefinition] = []
    
    // Skills mirroring
    @Published var availableSkills: [Skill] = []
    @Published var recentSkills: [Skill] = []
    
    let environment: AppEnvironment
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
            
        environment.registry.$userDefinitions
            .receive(on: RunLoop.main)
            .map { $0.count }
            .sink { [weak self] in self?.userDefinitionsCount = $0 }
            .store(in: &cancellables)
        
        environment.registry.$allDefinitions
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.allDefinitions = $0 }
            .store(in: &cancellables)
            
        Publishers.CombineLatest(environment.skills.$builtInSkills, environment.skills.$userSkills)
            .receive(on: RunLoop.main)
            .sink { [weak self] builtIn, user in
                self?.availableSkills = builtIn + user
            }
            .store(in: &cancellables)
            
        environment.skills.$recentSkillNames
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.recentSkills = self?.environment.skills.recentSkills ?? []
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
    
    func registerSkill(_ skill: Skill) {
        environment.skills.registerSkill(skill)
    }
    
    // MARK: - Actions
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
    
    func startNewChatForSkill() -> UUID {
        let newSession = environment.database.getOrCreateEmptySession(title: "New Chat")
        loadData()
        return newSession.id
    }
}

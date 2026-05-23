import SwiftUI
import Combine

@MainActor
class MainViewModel: ObservableObject {
    @Published var sessions: [ChatSession] = []
    @Published var selectedItem: NavigationItem? = .home
    @Published var columnVisibility: NavigationSplitViewVisibility = .all
    @Published var isChatsExpanded: Bool = true
    @Published var homePath: [NavigationItem] = []
    @Published var chatPath: [NavigationItem] = []
    @Published var allDefinitions: [LocalToolDefinition] = []
    @Published var totalResultCount: Int = 0
    @Published var activeTab: NavigationItem = .home
    
    let environment: AppEnvironment
    private var cancellables = Set<AnyCancellable>()
    
    init(environment: AppEnvironment) {
        self.environment = environment
        
        environment.registry.$allDefinitions
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.allDefinitions = $0 }
            .store(in: &cancellables)

        // Listen for session updates
        NotificationCenter.default.publisher(for: .sessionUpdated)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadSessions()
            }
            .store(in: &cancellables)

        environment.storage.$totalResultCount
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.totalResultCount = $0 }
            .store(in: &cancellables)
    }
    
    func loadSessions() {
        sessions = environment.database.getAllSessions()
    }
    
    func createNewChat() {
        let newSession = environment.database.getOrCreateEmptySession(title: "New Chat")
        if !sessions.contains(where: { $0.id == newSession.id }) {
            sessions.insert(newSession, at: 0)
        }
        selectedItem = .chat(newSession.id, initialPrompt: nil, initialSkill: nil)
    }
    
    func createNewChat(with prompt: String) {
        let newSession = environment.database.getOrCreateEmptySession(title: "New Chat")
        if !sessions.contains(where: { $0.id == newSession.id }) {
            sessions.insert(newSession, at: 0)
        }
        selectedItem = .chat(newSession.id, initialPrompt: prompt, initialSkill: nil)
    }
    
    func deleteSession(_ session: ChatSession) {
        deleteSession(withId: session.id)
    }
    
    func deleteSession(withId id: UUID) {
        let sessionItem = NavigationItem.chat(id, initialPrompt: nil, initialSkill: nil)
        
        // Explicitly pop visual paths containing this session item
        homePath.removeAll(where: { $0 == sessionItem })
        chatPath.removeAll(where: { $0 == sessionItem })
        
        // Clear database record
        environment.database.deleteSession(id: id)
        
        // Handle active selection replacement to avoid forced tab reset on iOS
        if selectedItem == sessionItem {
            #if os(iOS)
            // On iOS, default to remaining in the parent tab stack view
            selectedItem = activeTab
            #else
            selectedItem = nil
            #endif
        }
        loadSessions()
    }
    
    func handleSelectedItemChange(_ newItem: NavigationItem?) {
        guard let item = newItem else { return }
        
        switch item {
        case .chat(_, _, _), .canvasCreator(_, _):
            if activeTab == .home {
                if !homePath.contains(item) {
                    homePath.append(item)
                }
            } else {
                if !chatPath.contains(item) {
                    chatPath.append(item)
                }
                activeTab = .chats
            }
        case .scanner(let toolID):
            if !homePath.contains(item) {
                homePath.append(item)
            }
            activeTab = .home
        case .home:
            activeTab = .home
        case .chats:
            activeTab = .chats
        case .data:
            activeTab = .data
        case .settings:
            activeTab = .settings
        }
    }
    
    var selectedTab: Binding<NavigationItem> {
        Binding(
            get: {
                self.activeTab
            },
            set: {
                self.activeTab = $0
                self.selectedItem = $0
            }
        )
    }
}

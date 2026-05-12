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
    
    let environment: AppEnvironment
    private var cancellables = Set<AnyCancellable>()
    
    init(environment: AppEnvironment) {
        self.environment = environment
        
        // Listen for session updates
        NotificationCenter.default.publisher(for: .sessionUpdated)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadSessions()
            }
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
        selectedItem = .chat(newSession.id, initialPrompt: nil)
    }
    
    func createNewChat(with prompt: String) {
        let newSession = environment.database.getOrCreateEmptySession(title: "New Chat")
        if !sessions.contains(where: { $0.id == newSession.id }) {
            sessions.insert(newSession, at: 0)
        }
        selectedItem = .chat(newSession.id, initialPrompt: prompt)
    }
    
    func deleteSession(_ session: ChatSession) {
        deleteSession(withId: session.id)
    }
    
    func deleteSession(withId id: UUID) {
        let sessionItem = NavigationItem.chat(id)
        
        // Explicitly pop visual paths containing this session item
        homePath.removeAll(where: { $0 == sessionItem })
        chatPath.removeAll(where: { $0 == sessionItem })
        
        // Clear database record
        environment.database.deleteSession(id: id)
        
        // Handle active selection replacement to avoid forced tab reset on iOS
        if selectedItem == sessionItem {
            #if os(iOS)
            // On iOS, default to remaining in the parent tab stack view
            selectedItem = .chats
            #else
            selectedItem = nil
            #endif
        }
        loadSessions()
    }
    
    func handleSelectedItemChange(_ newItem: NavigationItem?) {
        guard let item = newItem else { return }
        
        switch item {
        case .chat(let id, _):
            if !chatPath.contains(item) {
                chatPath.append(item)
            }
        case .scanner(let toolID):
            if !homePath.contains(item) {
                homePath.append(item)
            }
        default:
            break
        }
    }
    
    var selectedTab: Binding<NavigationItem> {
        Binding(
            get: {
                guard let item = self.selectedItem else { return .home }
                switch item {
                case .home, .scanner(_): return .home
                case .chats, .chat(_): return .chats
                case .storage: return .storage
                case .settings: return .settings
                }
            },
            set: { self.selectedItem = $0 }
        )
    }
}

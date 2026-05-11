import SwiftUI

enum NavigationItem: Hashable {
    case home
    case chats
    case scanner(String? = nil)
    case storage
    case settings
    case chat(UUID)
}

struct MainView: View {
    @EnvironmentObject var viewModel: MainViewModel
    
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    
    var effectiveColorScheme: ColorScheme? {
        switch appTheme {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
    
    var body: some View {
        Group {
            #if os(macOS)
            splitView
            #else
            tabView
                .onChange(of: viewModel.selectedItem) { newItem in
                    viewModel.handleSelectedItemChange(newItem)
                }
                .onChange(of: viewModel.homePath) { newPath in
                    if newPath.isEmpty {
                        switch viewModel.selectedItem {
                        case .scanner, .chat:
                            viewModel.selectedItem = .home
                        default:
                            break
                        }
                    }
                }
                .onChange(of: viewModel.chatPath) { newPath in
                    if newPath.isEmpty {
                        switch viewModel.selectedItem {
                        case .chat:
                            viewModel.selectedItem = .chats
                        default:
                            break
                        }
                    }
                }
            #endif
        }
        .preferredColorScheme(effectiveColorScheme)
    }
    
    private var tabView: some View {
        TabView(selection: viewModel.selectedTab) {
            NavigationStack(path: $viewModel.homePath) {
                HomeView(selectedItem: $viewModel.selectedItem, env: viewModel.environment)
                    .navigationDestination(for: NavigationItem.self) { item in
                        switch item {
                        case .scanner(let toolID):
                            ToolPageView(toolID: toolID ?? "parcel_address", env: viewModel.environment)
                        case .chat(let id):
                            ChatView(sessionId: id, env: viewModel.environment)
                        default:
                            EmptyView()
                        }
                    }
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(NavigationItem.home)
            
            NavigationStack(path: $viewModel.chatPath) {
                ChatListView()
                    .navigationDestination(for: NavigationItem.self) { item in
                        switch item {
                        case .chat(let id):
                            ChatView(sessionId: id, env: viewModel.environment)
                        default:
                            EmptyView()
                        }
                    }
            }
            .tabItem {
                Label("Chats", systemImage: "bubble.left.and.bubble.right.fill")
            }
            .tag(NavigationItem.chats)
            
            NavigationStack {
                ToolDataView(env: viewModel.environment)
            }
            .tabItem {
                Label("Tools", systemImage: "square.grid.2x2.fill")
            }
            .tag(NavigationItem.storage)
            
            NavigationStack {
                SettingsView(env: viewModel.environment)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(NavigationItem.settings)
        }
        .tint(.orange)
        .onAppear { viewModel.loadSessions() }
    }
    
    private var splitView: some View {
        NavigationSplitView(columnVisibility: $viewModel.columnVisibility) {
            List(selection: $viewModel.selectedItem) {
                Section {
                    NavigationLink(value: NavigationItem.home) {
                        Label("Home", systemImage: "house.fill")
                    }
                }
                
                Section("Tools") {
                    NavigationLink(value: NavigationItem.scanner("parcel_address")) {
                        Label("Parcel Address", systemImage: "shippingbox.fill")
                    }
                    NavigationLink(value: NavigationItem.storage) {
                        Label("Tool Storage", systemImage: "externaldrive.fill")
                    }
                }
                
                Section(isExpanded: $viewModel.isChatsExpanded) {
                    ForEach(viewModel.sessions) { session in
                        NavigationLink(value: NavigationItem.chat(session.id)) {
                            VStack(alignment: .leading) {
                                Text(session.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text(session.createdAt, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                viewModel.deleteSession(session)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Chats")
                        Spacer()
                        Button(action: viewModel.createNewChat) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                
                Section("Preferences") {
                    NavigationLink(value: NavigationItem.settings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("Pelbagai")
            .onAppear { viewModel.loadSessions() }
        } detail: {
            if let selectedItem = viewModel.selectedItem {
                switch selectedItem {
                case .home:
                    HomeView(selectedItem: $viewModel.selectedItem, env: viewModel.environment)
                case .chats:
                    ChatListView()
                case .scanner(let toolID):
                    ToolPageView(toolID: toolID ?? "parcel_address", env: viewModel.environment)
                        .id(toolID)
                case .storage:
                    ToolDataView(env: viewModel.environment)
                case .settings:
                    SettingsView(env: viewModel.environment)
                case .chat(let id):
                    ChatView(sessionId: id, env: viewModel.environment)
                        .id(id)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Select an item from the sidebar.")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .tint(.orange)
    }
}

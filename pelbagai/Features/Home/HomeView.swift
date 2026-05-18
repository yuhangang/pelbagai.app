import SwiftUI

#if os(macOS)
import AppKit
#endif

struct HomeView: View {
    @Binding var selectedItem: NavigationItem?
    @StateObject private var viewModel: HomeViewModel
    @FocusState private var isChatBarFocused: Bool
    
    init(selectedItem: Binding<NavigationItem?>, env: AppEnvironment) {
        self._selectedItem = selectedItem
        self._viewModel = StateObject(wrappedValue: HomeViewModel(environment: env))
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    headerSection
                    statsSection
                    
                    if !viewModel.defaultTools.isEmpty {
                        toolSection(title: "Default Tools", tools: viewModel.defaultTools)
                    }
                    
                    if !viewModel.customTools.isEmpty {
                        toolSection(title: "Custom Tools", tools: viewModel.customTools)
                    } else {
                        noCustomToolsPlaceholder
                    }
                    
                    recentChatsSection
                    Spacer(minLength: 120)
                }
                .padding(.bottom, 40)
            }
            
            VStack(spacing: 0) {
                if isChatBarFocused {
                    suggestionsOverlay
                }
                floatingChatBar
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isChatBarFocused)
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome to Pelbagai")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            
            Text("Your personal AI assistant, powered by Gemma 4.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }
    
    private var floatingChatBar: some View {
        ChatInputView(
            textInput: $viewModel.chatSearchText,
            inputMode: $viewModel.chatInputMode,
            isRecording: false,
            isGenerating: viewModel.isGenerating,
            isLoadingModels: viewModel.isLoadingModels,
            isModelLoaded: viewModel.isModelLoaded,
            userDefinitionsCount: viewModel.userDefinitionsCount,
            pendingImage: $viewModel.pendingImage,
            onMicTap: { }, onCameraTap: { }, onFileTap: {},
            onSend: {
                let id = viewModel.startNewQuickChat()
                isChatBarFocused = false
                selectedItem = .chat(id)
            },
        )
        .focused($isChatBarFocused)
        .padding(.bottom, 20)
        .padding(.top, 10)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .shadow(color: .black.opacity(0.1), radius: 10, y: -5)
        )
    }
    
    private var suggestionsOverlay: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(viewModel.chatSearchText.isEmpty ? "Recent Conversations" : "Search Results")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { isChatBarFocused = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
            
            ScrollView {
                VStack(spacing: 12) {
                    if viewModel.filteredSessions.isEmpty && !viewModel.chatSearchText.isEmpty {
                        Text("No matches found. Press enter to start a new chat.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 20)
                    }
                    
                    ForEach(viewModel.filteredSessions.prefix(5)) { session in
                        Button(action: {
                            isChatBarFocused = false
                            selectedItem = .chat(session.id)
                        }) {
                            HStack(spacing: 16) {
                                Circle()
                                    .fill(Color.orange.opacity(0.1))
                                    .frame(width: 40, height: 40)
                                    .overlay(Image(systemName: "bubble.left").foregroundColor(.orange))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text(session.createdAt, style: .relative)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            .padding(12)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(16)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
            }
            .frame(maxHeight: 300)
        }
        .padding(.vertical, 20)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, y: -5)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    private var statsSection: some View {
        HStack(spacing: 16) {
            Button(action: { selectedItem = .data }) {
                StatCard(title: "Scans", value: "\(viewModel.totalResultCount)", icon: "viewfinder", color: .orange)
            }
            .buttonStyle(.plain)
            
            Button(action: { selectedItem = .chats }) {
                StatCard(title: "Chats", value: "\(viewModel.recentSessions.count)", icon: "bubble.left.and.bubble.right.fill", color: .blue)
            }
            .buttonStyle(.plain)
            
            Button(action: { selectedItem = .data }) {
                StatCard(title: "Tools", value: "\(viewModel.allDefinitions.count)", icon: "hammer.fill", color: .purple)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
    }
    
    private func toolSection(title: String, tools: [LocalToolDefinition]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.bold))
                .padding(.horizontal, 24)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(tools) { tool in
                        NavigationLink(value: NavigationItem.scanner(tool.toolID)) {
                            ToolCard(tool: tool)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
    
    private var noCustomToolsPlaceholder: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom Tools")
                .font(.title3.weight(.bold))
                .padding(.horizontal, 24)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Define Your Own Tools")
                        .font(.headline)
                    Text("Add custom extraction schemas via the developer console.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "terminal.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
            }
            .padding(20)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.orange.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
            )
            .padding(.horizontal, 24)
        }
    }
    
    private var recentChatsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Chats")
                    .font(.title3.weight(.bold))
                Spacer()
                Button("See All") {
                    selectedItem = .chats
                }
                .font(.subheadline)
                .foregroundColor(.orange)
            }
            .padding(.horizontal, 24)
            
            if viewModel.recentSessions.isEmpty {
                Text("No recent chats.")
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(12)
                    .padding(.horizontal, 24)
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.recentSessions.prefix(3)) { session in
                        NavigationLink(value: NavigationItem.chat(session.id)) {
                            HStack(spacing: 16) {
                                Circle()
                                    .fill(Color.orange.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Image(systemName: "bubble.left")
                                            .foregroundColor(.orange)
                                    )
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.title)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(session.createdAt, style: .relative)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            .padding(12)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(16)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(color.opacity(0.1))
        .cornerRadius(20)
    }
}

struct ToolCard: View {
    let tool: LocalToolDefinition
    
    private var color: Color {
        tool.uiColor
    }
    
    private var icon: String {
        tool.uiIcon
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(tool.displayName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(tool.description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 32, alignment: .top)
            }
        }
        .padding(16)
        .frame(width: 160)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

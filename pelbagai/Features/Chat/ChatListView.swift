import SwiftUI

struct ChatListView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var viewModel: MainViewModel
    @State private var chatboxText: String = ""
    @FocusState private var isChatboxFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            Group {
                if viewModel.sessions.isEmpty {
                    EmptyStateView(
                        icon: "bubble.left.and.bubble.right",
                        title: "No Conversations Yet",
                        description: "Start a new chat to begin asking questions, generating content, or analyzing documents.",
                        actionTitle: "Start Chat",
                        action: viewModel.createNewChat
                    )
                } else {
                    List(selection: $viewModel.selectedItem) {
                        ForEach(viewModel.sessions) { session in
                            NavigationLink(value: NavigationItem.chat(session.id, initialPrompt: nil)) {
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
                    }
                }
            }
            
            chatboxSection
        }
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: viewModel.createNewChat) {
                    Image(systemName: "plus")
                }
            }
        }
    }
    
    private var chatboxSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                HStack {
                    TextField("Start a new chat...", text: $chatboxText)
                        .font(.system(size: 16, design: .rounded))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .focused($isChatboxFocused)
                        .onSubmit {
                            isChatboxFocused = false
                            sendChatboxPrompt()
                        }
                    
                    if !chatboxText.isEmpty {
                        Button(action: {
                            isChatboxFocused = false
                            sendChatboxPrompt()
                        }) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(Color.orange)
                                .clipShape(Circle())
                        }
                        .padding(.trailing, 6)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .background(Color.primary.opacity(0.05))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }
    
    private func sendChatboxPrompt() {
        let prompt = chatboxText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        
        viewModel.createNewChat(with: prompt)
        chatboxText = ""
    }
}

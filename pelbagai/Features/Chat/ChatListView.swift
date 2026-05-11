import SwiftUI

struct ChatListView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var viewModel: MainViewModel
    
    var body: some View {
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
                }
            }
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
}

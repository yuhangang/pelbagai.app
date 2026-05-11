import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Icon Container with glowing background and subtle bounce
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 120, height: 120)
                    .scaleEffect(isAnimating ? 1.05 : 0.95)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)
                
                Circle()
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 2)
                    .frame(width: 140, height: 140)
                    .scaleEffect(isAnimating ? 1.1 : 0.9)
                    .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: isAnimating)
                
                Image(systemName: icon)
                    .font(.system(size: 56, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .scaleEffect(isAnimating ? 1.02 : 0.98)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)
            }
            .padding(.bottom, 8)
            
            // Text Content
            VStack(spacing: 12) {
                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 32)
                    .lineSpacing(4)
            }
            
            // Action Button
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 32)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.gradient)
                                .shadow(color: Color.accentColor.opacity(0.3), radius: 10, x: 0, y: 5)
                        )
                }
                .padding(.top, 16)
                .buttonStyle(.plain)
            }
            
            Spacer()
            Spacer() // Push it up slightly above geometric center
        }
        .padding()
        .onAppear {
            // Slight delay to ensure view is rendered before starting perpetual animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isAnimating = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            EmptyStateView(
                icon: "bubble.left.and.bubble.right.fill",
                title: "No Chats Yet",
                description: "Start a conversation to see your chat list populated here.",
                actionTitle: "New Chat",
                action: {}
            )
            .preferredColorScheme(.light)
            .accentColor(.orange)
            
            EmptyStateView(
                icon: "folder",
                title: "No Documents",
                description: "You haven't saved any scanned documents yet. Use the scanner tool to begin.",
                actionTitle: "Open Scanner",
                action: {}
            )
            .preferredColorScheme(.dark)
            .accentColor(.orange)
        }
    }
}

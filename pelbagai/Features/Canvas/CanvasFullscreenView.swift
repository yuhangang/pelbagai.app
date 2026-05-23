import SwiftUI

/// A distraction-free, full-screen canvas viewer.
/// Extends the canvas app to fill the entire screen, allowing natural immersive layouts (games, forms, calculators).
struct CanvasFullscreenView: View {
    let htmlContent: String
    let canvasId: String
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Edge-to-edge WebView
            CanvasWebView(htmlContent: htmlContent, canvasId: canvasId)
                .ignoresSafeArea()
            
            // Floating Glassmorphic Close Button
            Button(action: {
                // UI feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.prepare()
                generator.impactOccurred()
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
            .padding(.top, safeAreaInsets.top > 0 ? 0 : 16) // Extra padding for non-notch devices if ignoring safe area
        }
        .statusBar(hidden: true)
    }
    
    // Helper to get safeAreaInsets in SwiftUI
    private var safeAreaInsets: UIEdgeInsets {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return .zero
        }
        return window.safeAreaInsets
    }
}

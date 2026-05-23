import SwiftUI

/// A beautiful inline glassmorphic card for rendering and interacting with AI Canvas apps in the chat thread.
struct CanvasBlockView: View {
    let localFileURL: URL
    let messageId: UUID
    @ObservedObject var viewModel: ChatViewModel
    
    @State private var htmlContent: String = ""
    @State private var isPresentingFullscreen: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                // Gradient Icon Badge
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.15), Color.blue.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.purple, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(appName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 4) {
                        Text("AI CANVAS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(4)
                        
                        Text("Interactive")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            
            Divider().opacity(0.3)
            
            // Inline Interactive WebView
            if !htmlContent.isEmpty {
                CanvasWebView(htmlContent: htmlContent, canvasId: messageId.uuidString)
                    .frame(height: 350)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            } else {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding()
                    Spacer()
                }
                .frame(height: 350)
            }
            
            Divider().opacity(0.3)
            
            // Bottom Action Row
            HStack(spacing: 10) {
                // Open Fullscreen
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.prepare()
                    generator.impactOccurred()
                    isPresentingFullscreen = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right.circle.fill")
                        Text("Fullscreen")
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(10)
                }
                
                // Share App
                Button(action: {
                    shareApp()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(10)
                }
                
                Spacer()
                
                // Refine App
                Button(action: {
                    refineApp()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("Refine")
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [Color.purple, Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(10)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.12), Color.blue.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                )
        )
        .onAppear {
            loadHtml()
        }
        .onChange(of: localFileURL) { _ in
            loadHtml()
        }
        .fullScreenCover(isPresented: $isPresentingFullscreen) {
            CanvasFullscreenView(htmlContent: htmlContent, canvasId: messageId.uuidString)
        }
    }
    
    // MARK: - Helper Functions
    
    private var appName: String {
        guard !htmlContent.isEmpty else { return "Loading Canvas..." }
        
        // Extract title tag
        if let titleRange = htmlContent.range(of: "<title>", options: .caseInsensitive),
           let endTitleRange = htmlContent.range(of: "</title>", options: .caseInsensitive, range: titleRange.upperBound..<htmlContent.endIndex) {
            let extracted = htmlContent[titleRange.upperBound..<endTitleRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return extracted.isEmpty ? "AI Canvas App" : extracted
        }
        
        return "AI Canvas App"
    }
    
    private func loadHtml() {
        do {
            let fileContent = try String(contentsOf: localFileURL, encoding: .utf8)
            DispatchQueue.main.async {
                self.htmlContent = fileContent
            }
        } catch {
            print("⚠️ Failed to load HTML file from: \(localFileURL.path). Error: \(error)")
        }
    }
    
    private func shareApp() {
        let activityVC = UIActivityViewController(activityItems: [localFileURL], applicationActivities: nil)
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            return
        }
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        
        topVC.present(activityVC, animated: true)
    }
    
    private func refineApp() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        
        // Autofill input and focus
        viewModel.textInput = "For the \(appName) app, please add/change "
    }
}

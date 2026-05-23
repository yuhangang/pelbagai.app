import SwiftUI
import WebKit

/// A SwiftUI wrapper around WKWebView configured for rendering and running
/// AI-generated canvas apps with a native Swift bridge.
struct CanvasWebView: UIViewRepresentable {
    let htmlContent: String
    let canvasId: String
    
    func makeCoordinator() -> CanvasBridgeCoordinator {
        CanvasBridgeCoordinator(canvasId: canvasId)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        
        // Register the "pelbagaiCanvas" channel
        contentController.add(context.coordinator, name: "pelbagaiCanvas")
        
        // Inject the Javascript bridge
        let bridgeScript = WKUserScript(
            source: context.coordinator.getBridgeJS(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(bridgeScript)
        config.userContentController = contentController
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        context.coordinator.webView = webView
        
        // Initial HTML load
        context.coordinator.lastLoadedHtml = htmlContent
        webView.loadHTMLString(htmlContent, baseURL: nil)
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // If content changed (e.g., from AI iteration), load the new HTML string
        if context.coordinator.lastLoadedHtml != htmlContent {
            context.coordinator.lastLoadedHtml = htmlContent
            uiView.loadHTMLString(htmlContent, baseURL: nil)
        }
    }
}

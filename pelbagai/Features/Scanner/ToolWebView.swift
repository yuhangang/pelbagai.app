import SwiftUI

#if canImport(UIKit)
import UIKit
import WebKit
#endif

// MARK: - Message Protocol

/// Bidirectional message format between Swift and embedded HTML.
struct ToolWebViewMessage: Codable {
    let action: String
    let payload: [String: String]
}

#if canImport(UIKit)
// MARK: - ToolWebView (UIViewRepresentable)

/// An embedded WKWebView that loads local HTML strings and supports
/// bidirectional message passing via the `pelbagai` JS channel.
///
/// **Swift → JS**: Call `sendToJS(_:)` on the coordinator.
/// **JS → Swift**: Post messages via `window.webkit.messageHandlers.pelbagai.postMessage({...})`
struct ToolWebView: UIViewRepresentable {
    let htmlContent: String
    let toolColor: Color
    var onMessage: ((ToolWebViewMessage) -> Void)?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onMessage: onMessage)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        
        // Register message handler on "pelbagai" channel
        contentController.add(context.coordinator, name: "pelbagai")
        
        // Inject a helper JS bridge function
        let bridgeScript = WKUserScript(
            source: """
            window.pelbagai = {
                send: function(action, payload) {
                    window.webkit.messageHandlers.pelbagai.postMessage(
                        JSON.stringify({ action: action, payload: payload || {} })
                    );
                },
                // Generic runner for dynamic scripts from tool definition
                run: async function(script, data) {
                    try {
                        const fn = new Function('data', 'return (' + script + ')(data)');
                        await fn(data);
                    } catch (e) {
                        console.error('JS Run Error:', e);
                        window.pelbagai.send('notify', { message: 'JS Error: ' + e.message });
                    }
                }
            };
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(bridgeScript)
        config.userContentController = contentController
        
        // Disable scrolling bounce and make background transparent
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator
        
        // Store reference for JS calls
        context.coordinator.webView = webView
        
        // Load HTML with dark mode support wrapper
        let wrappedHTML = wrapHTML(htmlContent)
        webView.loadHTMLString(wrappedHTML, baseURL: nil)
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Only reload if content changed
    }
    
    /// Wraps tool HTML in a full document with dark mode CSS and system font.
    private func wrapHTML(_ body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
            :root {
                --tool-color: \(toolColor.hexString);
                color-scheme: light dark;
            }
            * { box-sizing: border-box; margin: 0; padding: 0; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Rounded', sans-serif;
                font-size: 14px;
                padding: 12px;
                background: transparent;
                color: var(--text-primary);
                -webkit-user-select: none;
                -webkit-touch-callout: none;
            }
            @media (prefers-color-scheme: dark) {
                :root { --text-primary: #f5f5f7; --text-secondary: #8e8e93; --bg-card: rgba(255,255,255,0.06); --border: rgba(255,255,255,0.08); }
            }
            @media (prefers-color-scheme: light) {
                :root { --text-primary: #1d1d1f; --text-secondary: #86868b; --bg-card: rgba(0,0,0,0.03); --border: rgba(0,0,0,0.06); }
            }
            .card {
                background: var(--bg-card);
                border: 0.5px solid var(--border);
                border-radius: 12px;
                padding: 12px;
                margin-bottom: 8px;
            }
            .btn {
                display: inline-flex;
                align-items: center;
                gap: 6px;
                padding: 8px 16px;
                border-radius: 10px;
                border: none;
                font-size: 13px;
                font-weight: 600;
                cursor: pointer;
                background: var(--tool-color);
                color: white;
                -webkit-tap-highlight-color: transparent;
            }
            .btn:active { opacity: 0.7; }
            .btn-secondary {
                background: var(--bg-card);
                color: var(--text-primary);
                border: 0.5px solid var(--border);
            }
            .label { font-size: 11px; font-weight: 600; color: var(--text-secondary); text-transform: uppercase; letter-spacing: 0.5px; }
            .value { font-size: 14px; color: var(--text-primary); margin-top: 2px; }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        var onMessage: ((ToolWebViewMessage) -> Void)?
        
        init(onMessage: ((ToolWebViewMessage) -> Void)?) {
            self.onMessage = onMessage
            super.init()
            
            // Listen for triggers from Swift code
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleActionTrigger(_:)),
                name: NSNotification.Name("TriggerWebViewAction"),
                object: nil
            )
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc private func handleActionTrigger(_ notification: Notification) {
            guard let action = notification.userInfo?["action"] as? String,
                  let payload = notification.userInfo?["payload"] as? [String: Any] else { return }
            
            if action == "run_script" {
                if let script = payload["script"] as? String,
                   let data = payload["data"] as? String {
                    let js = "window.pelbagai.run(\(JSONString(script)), \(data));"
                    webView?.evaluateJavaScript(js) { _, error in
                        if let error = error {
                            print("⚙️ ToolWebView script error: \(error.localizedDescription)")
                        }
                    }
                }
            } else if let stringPayload = payload as? [String: String] {
                let message = ToolWebViewMessage(action: action, payload: stringPayload)
                sendToJS(message)
            }
        }
        
        private func JSONString(_ value: String) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: [value]),
                  let json = String(data: data, encoding: .utf8) else { return "\"\"" }
            return String(json.dropFirst().dropLast())
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "pelbagai",
                  let bodyString = message.body as? String,
                  let data = bodyString.data(using: .utf8),
                  let msg = try? JSONDecoder().decode(ToolWebViewMessage.self, from: data)
            else { return }
            
            DispatchQueue.main.async { [weak self] in
                self?.onMessage?(msg)
            }
        }
        
        /// Send data from Swift to the WebView's JS context.
        func sendToJS(_ message: ToolWebViewMessage) {
            guard let data = try? JSONEncoder().encode(message),
                  let json = String(data: data, encoding: .utf8) else { return }
            
            let js = "if(window.onPelbagaiMessage) window.onPelbagaiMessage(\(json));"
            webView?.evaluateJavaScript(js) { _, error in
                if let error = error {
                    print("⚙️ ToolWebView JS error: \(error.localizedDescription)")
                }
            }
        }
        
        // Block navigation to external URLs
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .other || navigationAction.request.url?.scheme == "about" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}

// MARK: - ToolWebViewBlock (SwiftUI wrapper)

/// A glassmorphic block that embeds a WKWebView for custom HTML tool UIs.
struct ToolWebViewBlock: View {
    let htmlContent: String
    let toolColor: Color
    var onMessage: ((ToolWebViewMessage) -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.12))
                        .frame(width: 26, height: 26)
                    Image(systemName: "globe")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.cyan)
                }
                Text("Custom View")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            
            Divider().opacity(0.3)
            
            // WebView
            ToolWebView(htmlContent: htmlContent, toolColor: toolColor, onMessage: onMessage)
                .frame(minHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.cyan.opacity(0.12), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Color Hex Helper

fileprivate extension Color {
    var hexString: String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

// MARK: - SkillWebView

struct SkillWebView: UIViewRepresentable {
    let localFileURL: URL
    let inputJson: String
    var onHtmlSnapshot: ((String) -> Void)?
    var onImageGenerated: ((Data) -> Void)?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        
        // Register the script message handler for "pelbagaiBridge"
        contentController.add(context.coordinator, name: "pelbagaiBridge")
        
        config.userContentController = contentController
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator
        
        // Load the local HTML file
        webView.loadFileURL(localFileURL, allowingReadAccessTo: localFileURL.deletingLastPathComponent())
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No updates needed
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let parent: SkillWebView
        
        init(parent: SkillWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // When document is loaded, invoke window.executeSkill(inputJson)
            let escapedInput = parent.inputJson
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            
            let js = "if (window.executeSkill) { window.executeSkill(\"\(escapedInput)\"); }"
            webView.evaluateJavaScript(js) { _, error in
                if let error = error {
                    print("⚙️ SkillWebView JS execution error: \(error.localizedDescription)")
                }
            }
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "pelbagaiBridge" else { return }
            
            if let bodyString = message.body as? String {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.onHtmlSnapshot?(bodyString)
                }
            } else if let dict = message.body as? [String: Any],
                      let type = dict["type"] as? String {
                if type == "imageGenerated", let urlStr = dict["url"] as? String {
                    guard let url = URL(string: urlStr) else { return }
                    Task {
                        do {
                            let (data, _) = try await URLSession.shared.data(from: url)
                            await MainActor.run { [weak self] in
                                self?.parent.onImageGenerated?(data)
                            }
                        } catch {
                            print("⚠️ Failed to download generated image: \(error)")
                        }
                    }
                } else if type == "saveImage", let urlStr = dict["url"] as? String {
                    guard let url = URL(string: urlStr) else { return }
                    Task {
                        do {
                            let (data, _) = try await URLSession.shared.data(from: url)
                            await MainActor.run {
                                guard let uiImage = UIImage(data: data) else { return }
                                let activityVC = UIActivityViewController(activityItems: [uiImage], applicationActivities: nil)
                                
                                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                   let rootVC = windowScene.windows.first?.rootViewController {
                                    
                                    var topVC = rootVC
                                    while let presented = topVC.presentedViewController {
                                        topVC = presented
                                    }
                                    
                                    if let popover = activityVC.popoverPresentationController {
                                        popover.sourceView = topVC.view
                                        popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
                                        popover.permittedArrowDirections = []
                                    }
                                    
                                    topVC.present(activityVC, animated: true)
                                }
                            }
                        } catch {
                            print("⚠️ Failed to save/share generated QR Code image: \(error)")
                        }
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .other || navigationAction.request.url?.scheme == "about" || navigationAction.request.url?.scheme == "file" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}

// MARK: - SkillWebViewBlock

struct SkillWebViewBlock: View {
    let localFileURL: URL
    let messageId: UUID
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 26, height: 26)
                    Image(systemName: "cpu")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.blue)
                }
                Text("Interactive Skill Output")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            
            Divider().opacity(0.3)
            
            // WebView
            let inputJson = extractJsonPayload(from: viewModel.messages.first(where: { $0.id == messageId })?.content ?? "", userText: "")
            SkillWebView(
                localFileURL: localFileURL,
                inputJson: inputJson,
                onHtmlSnapshot: { updatedHtml in
                    viewModel.saveHtmlSnapshot(for: messageId, html: updatedHtml)
                },
                onImageGenerated: { imageData in
                    viewModel.updateMessageImageData(for: messageId, imageData: imageData)
                }
            )
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.blue.opacity(0.12), lineWidth: 0.5)
                )
        )
    }
    
    private func extractJsonPayload(from responseText: String, userText: String) -> String {
        // 1. Try to find a JSON block in responseText: {...}
        if let startIdx = responseText.firstIndex(of: "{"),
           let endIdx = responseText.lastIndex(of: "}") {
            let jsonStr = String(responseText[startIdx...endIdx])
            if let data = jsonStr.data(using: .utf8),
               let _ = try? JSONSerialization.jsonObject(with: data) {
                return jsonStr
            }
        }
        
        // 2. Try to find a URL in the userText or responseText
        let textToSearch = responseText + " " + userText
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: textToSearch, options: [], range: NSRange(location: 0, length: textToSearch.utf16.count))
        if let firstMatch = matches?.first, let urlRange = Range(firstMatch.range, in: textToSearch) {
            let urlStr = String(textToSearch[urlRange])
            return "{\"text\":\"\(urlStr)\",\"url\":\"\(urlStr)\"}"
        }
        
        // 3. Fallback: use responseText directly as the text payload
        let cleanText = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        return "{\"text\":\"\(cleanText)\"}"
    }
}

#endif

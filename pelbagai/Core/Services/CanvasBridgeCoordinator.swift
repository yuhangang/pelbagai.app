import Foundation
import UIKit
import WebKit
import UniformTypeIdentifiers
import PhotosUI

/// Message structure received from the JS bridge.
struct CanvasBridgeMessage: Codable {
    let action: String
    let callbackId: Int
    let payload: [String: StringOrArrayOrDict]
}

/// A polymorphic enum to parse various JSON types sent from JS.
enum StringOrArrayOrDict: Codable {
    case string(String)
    case array([String])
    case dict([String: String])
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([String].self) {
            self = .array(arr)
        } else if let dict = try? container.decode([String: String].self) {
            self = .dict(dict)
        } else {
            throw DecodingError.typeMismatch(StringOrArrayOrDict.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported bridge payload type"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .array(let arr): try container.encode(arr)
        case .dict(let dict): try container.encode(dict)
        }
    }
    
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    
    var arrayValue: [String]? {
        if case .array(let arr) = self { return arr }
        return nil
    }
    
    var dictValue: [String: String]? {
        if case .dict(let dict) = self { return dict }
        return nil
    }
}

/// Coordinates communication and native features for the AI Canvas.
@MainActor
class CanvasBridgeCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    weak var webView: WKWebView?
    var lastLoadedHtml: String = ""
    let canvasId: String
    
    // Store active callbacks while presentation delegates do their work.
    private var pendingCallbacks: [Int: (Any?) -> Void] = [:]
    
    init(canvasId: String) {
        self.canvasId = canvasId
        super.init()
    }
    
    /// Returns the Javascript string to inject at document start.
    func getBridgeJS() -> String {
        return """
        window.pelbagai = {
            _callbacks: {},
            _nextCallbackId: 1,
            _callSwift: function(action, payload) {
                return new Promise((resolve, reject) => {
                    const callbackId = window.pelbagai._nextCallbackId++;
                    window.pelbagai._callbacks[callbackId] = { resolve, reject };
                    window.webkit.messageHandlers.pelbagaiCanvas.postMessage(JSON.stringify({
                        action: action,
                        callbackId: callbackId,
                        payload: payload || {}
                    }));
                });
            },
            
            // Device capabilities
            camera: {
                capture: function() { return window.pelbagai._callSwift('camera_capture'); }
            },
            photos: {
                pick: function() { return window.pelbagai._callSwift('photos_pick'); }
            },
            files: {
                pick: function(types) { return window.pelbagai._callSwift('files_pick', { types: types }); },
                save: function(name, content, type) { return window.pelbagai._callSwift('files_save', { name: name, content: content, type: type }); },
                list: function() { return window.pelbagai._callSwift('files_list'); }
            },
            share: {
                show: function(text, url, imageDataUrl) { return window.pelbagai._callSwift('share_show', { text: text, url: url, imageDataUrl: imageDataUrl }); }
            },
            
            // App state (persistent across restarts)
            storage: {
                save: function(key, value) { return window.pelbagai._callSwift('storage_save', { key: key, value: String(value) }); },
                load: function(key) { return window.pelbagai._callSwift('storage_load', { key: key }); },
                remove: function(key) { return window.pelbagai._callSwift('storage_remove', { key: key }); },
                list: function() { return window.pelbagai._callSwift('storage_list'); }
            },
            
            // UI controls
            ui: {
                haptic: function(style) { return window.pelbagai._callSwift('ui_haptic', { style: style }); },
                alert: function(title, message, buttons) { return window.pelbagai._callSwift('ui_alert', { title: title, message: message, buttons: buttons }); },
                toast: function(message) { return window.pelbagai._callSwift('ui_toast', { message: message }); }
            },
            
            onReady: null,
            appId: "\(canvasId)"
        };
        
        // Notify the web app that pelbagai is ready
        setTimeout(function() {
            if (typeof window.pelbagai.onReady === 'function') {
                window.pelbagai.onReady();
            } else {
                const event = new CustomEvent('pelbagaiReady');
                window.dispatchEvent(event);
            }
        }, 50);
        """
    }
    
    // MARK: - Script Message Handler
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "pelbagaiCanvas",
              let bodyString = message.body as? String,
              let data = bodyString.data(using: .utf8),
              let msg = try? JSONDecoder().decode(CanvasBridgeMessage.self, from: data)
        else { return }
        
        Task {
            await handleJSMessage(msg)
        }
    }
    
    private func handleJSMessage(_ message: CanvasBridgeMessage) async {
        let action = message.action
        let callbackId = message.callbackId
        let payload = message.payload
        
        switch action {
        case "camera_capture":
            handleCameraCapture(callbackId: callbackId)
        case "photos_pick":
            handlePhotosPick(callbackId: callbackId)
        case "files_pick":
            let types = payload["types"]?.arrayValue
            handleFilesPick(callbackId: callbackId, types: types)
        case "files_save":
            guard let name = payload["name"]?.stringValue,
                  let content = payload["content"]?.stringValue
            else {
                rejectPromise(callbackId: callbackId, error: "Missing 'name' or 'content' in save request")
                return
            }
            let type = payload["type"]?.stringValue
            handleFilesSave(callbackId: callbackId, name: name, content: content, type: type)
        case "files_list":
            handleFilesList(callbackId: callbackId)
        case "share_show":
            let text = payload["text"]?.stringValue
            let url = payload["url"]?.stringValue
            let imageDataUrl = payload["imageDataUrl"]?.stringValue
            handleShareShow(callbackId: callbackId, text: text, url: url, imageDataUrl: imageDataUrl)
        case "storage_save":
            guard let key = payload["key"]?.stringValue,
                  let value = payload["value"]?.stringValue
            else {
                rejectPromise(callbackId: callbackId, error: "Missing 'key' or 'value'")
                return
            }
            await CanvasStorageManager.shared.save(canvasId: canvasId, key: key, value: value)
            resolvePromise(callbackId: callbackId, result: "null")
        case "storage_load":
            guard let key = payload["key"]?.stringValue else {
                rejectPromise(callbackId: callbackId, error: "Missing 'key'")
                return
            }
            let val = await CanvasStorageManager.shared.load(canvasId: canvasId, key: key)
            if let val = val {
                let escaped = val.replacingOccurrences(of: "\\", with: "\\\\")
                                 .replacingOccurrences(of: "\"", with: "\\\"")
                                 .replacingOccurrences(of: "\n", with: "\\n")
                                 .replacingOccurrences(of: "\r", with: "\\r")
                resolvePromise(callbackId: callbackId, result: "\"\(escaped)\"")
            } else {
                resolvePromise(callbackId: callbackId, result: "null")
            }
        case "storage_remove":
            guard let key = payload["key"]?.stringValue else {
                rejectPromise(callbackId: callbackId, error: "Missing 'key'")
                return
            }
            await CanvasStorageManager.shared.remove(canvasId: canvasId, key: key)
            resolvePromise(callbackId: callbackId, result: "null")
        case "storage_list":
            let keys = await CanvasStorageManager.shared.listKeys(canvasId: canvasId)
            if let jsonKeysData = try? JSONEncoder().encode(keys),
               let jsonString = String(data: jsonKeysData, encoding: .utf8) {
                resolvePromise(callbackId: callbackId, result: jsonString)
            } else {
                resolvePromise(callbackId: callbackId, result: "[]")
            }
        case "ui_haptic":
            let style = payload["style"]?.stringValue ?? "medium"
            handleHaptic(style: style)
            resolvePromise(callbackId: callbackId, result: "null")
        case "ui_alert":
            let title = payload["title"]?.stringValue ?? "Alert"
            let message = payload["message"]?.stringValue ?? ""
            let buttons = payload["buttons"]?.arrayValue ?? ["OK"]
            handleAlert(callbackId: callbackId, title: title, message: message, buttons: buttons)
        case "ui_toast":
            let msg = payload["message"]?.stringValue ?? ""
            handleToast(message: msg)
            resolvePromise(callbackId: callbackId, result: "null")
        default:
            rejectPromise(callbackId: callbackId, error: "Unknown action: \(action)")
        }
    }
    
    // MARK: - Helper Core Functions
    
    func resolvePromise(callbackId: Int, result: String) {
        let js = "if (window.pelbagai && window.pelbagai._callbacks[\(callbackId)]) { window.pelbagai._callbacks[\(callbackId)].resolve(\(result)); delete window.pelbagai._callbacks[\(callbackId)]; }"
        webView?.evaluateJavaScript(js) { _, error in
            if let error = error {
                print("⚠️ Error resolving JS promise \(callbackId): \(error)")
            }
        }
    }
    
    func rejectPromise(callbackId: Int, error: String) {
        let escaped = error.replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "\"", with: "\\\"")
                            .replacingOccurrences(of: "\n", with: "\\n")
        let js = "if (window.pelbagai && window.pelbagai._callbacks[\(callbackId)]) { window.pelbagai._callbacks[\(callbackId)].reject(new Error(\"\(escaped)\")); delete window.pelbagai._callbacks[\(callbackId)]; }"
        webView?.evaluateJavaScript(js) { _, error in
            if let error = error {
                print("⚠️ Error rejecting JS promise \(callbackId): \(error)")
            }
        }
    }
    
    private func getTopVC() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            return nil
        }
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }
    
    // MARK: - Native Handlers
    
    private func handleCameraCapture(callbackId: Int) {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            rejectPromise(callbackId: callbackId, error: "Camera is not available on this device")
            return
        }
        
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        
        pendingCallbacks[callbackId] = { [weak self] result in
            if let dataUrl = result as? String {
                self?.resolvePromise(callbackId: callbackId, result: "{\"dataUrl\": \"\(dataUrl)\"}")
            } else {
                self?.rejectPromise(callbackId: callbackId, error: "Capture cancelled or failed")
            }
        }
        
        guard let topVC = getTopVC() else {
            rejectPromise(callbackId: callbackId, error: "Could not present camera interface")
            return
        }
        
        // Associate the callbackId with the picker using objc_setAssociatedObject if needed or just class storage
        picker.presentationController?.delegate = self
        topVC.present(picker, animated: true)
    }
    
    private func handlePhotosPick(callbackId: Int) {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        
        pendingCallbacks[callbackId] = { [weak self] result in
            if let dataUrl = result as? String {
                self?.resolvePromise(callbackId: callbackId, result: "{\"dataUrl\": \"\(dataUrl)\"}")
            } else {
                self?.rejectPromise(callbackId: callbackId, error: "Photo selection cancelled or failed")
            }
        }
        
        guard let topVC = getTopVC() else {
            rejectPromise(callbackId: callbackId, error: "Could not present photos interface")
            return
        }
        
        topVC.present(picker, animated: true)
    }
    
    private func handleFilesPick(callbackId: Int, types: [String]?) {
        var contentTypes: [UTType] = [.item]
        if let types = types {
            contentTypes = types.compactMap { mime in
                if mime.contains("text") { return .text }
                if mime.contains("json") { return .json }
                if mime.contains("image") { return .image }
                if mime.contains("pdf") { return .pdf }
                return UTType(mimeType: mime)
            }
        }
        if contentTypes.isEmpty { contentTypes = [.item] }
        
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.delegate = self
        
        pendingCallbacks[callbackId] = { [weak self] result in
            if let dict = result as? [String: Any],
               let jsonData = try? JSONSerialization.data(withJSONObject: dict),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                self?.resolvePromise(callbackId: callbackId, result: jsonString)
            } else {
                self?.rejectPromise(callbackId: callbackId, error: "File selection cancelled or failed")
            }
        }
        
        guard let topVC = getTopVC() else {
            rejectPromise(callbackId: callbackId, error: "Could not present document picker")
            return
        }
        
        topVC.present(picker, animated: true)
    }
    
    // File sandbox directory helper
    private var canvasFilesDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let baseDir = docs.appendingPathComponent("canvas_files", isDirectory: true)
        let canvasDir = baseDir.appendingPathComponent(canvasId, isDirectory: true)
        
        let fm = FileManager.default
        if !fm.fileExists(atPath: canvasDir.path) {
            try? fm.createDirectory(at: canvasDir, withIntermediateDirectories: true)
        }
        return canvasDir
    }
    
    private func handleFilesSave(callbackId: Int, name: String, content: String, type: String?) {
        let fileUrl = canvasFilesDirectory.appendingPathComponent(name)
        
        do {
            if let dataUrlRange = content.range(of: ";base64,") {
                let base64Part = String(content[dataUrlRange.upperBound...]).trimmed()
                if let data = Data(base64Encoded: base64Part) {
                    // Base64 decoding
                    try data.write(to: fileUrl, options: .atomic)
                } else {
                    rejectPromise(callbackId: callbackId, error: "Invalid base64 content")
                    return
                }
            } else {
                // Write as text
                try content.write(to: fileUrl, atomically: true, encoding: .utf8)
            }
            resolvePromise(callbackId: callbackId, result: "{\"success\": true}")
        } catch {
            rejectPromise(callbackId: callbackId, error: "Failed to write file: \(error.localizedDescription)")
        }
    }
    
    private func handleFilesList(callbackId: Int) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: canvasFilesDirectory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            resolvePromise(callbackId: callbackId, result: "[]")
            return
        }
        
        var list: [[String: Any]] = []
        for file in files {
            let attrs = try? fm.attributesOfItem(atPath: file.path)
            let size = attrs?[.size] as? Int64 ?? 0
            let date = attrs?[.modificationDate] as? Date ?? Date()
            
            let dateFormatter = ISO8601DateFormatter()
            let dateString = dateFormatter.string(from: date)
            
            list.append([
                "name": file.lastPathComponent,
                "size": size,
                "date": dateString
            ])
        }
        
        if let data = try? JSONSerialization.data(withJSONObject: list),
           let jsonStr = String(data: data, encoding: .utf8) {
            resolvePromise(callbackId: callbackId, result: jsonStr)
        } else {
            resolvePromise(callbackId: callbackId, result: "[]")
        }
    }
    
    private func handleShareShow(callbackId: Int, text: String?, url: String?, imageDataUrl: String?) {
        var items: [Any] = []
        
        if let text = text {
            items.append(text)
        }
        
        if let urlStr = url, let actualUrl = URL(string: urlStr) {
            items.append(actualUrl)
        }
        
        if let dataUrl = imageDataUrl,
           let dataUrlRange = dataUrl.range(of: ";base64,"),
           let base64Data = Data(base64Encoded: String(dataUrl[dataUrlRange.upperBound...]).trimmed()),
           let image = UIImage(data: base64Data) {
            items.append(image)
        }
        
        guard !items.isEmpty else {
            rejectPromise(callbackId: callbackId, error: "Nothing to share")
            return
        }
        
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        guard let topVC = getTopVC() else {
            rejectPromise(callbackId: callbackId, error: "Could not present share sheet")
            return
        }
        
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        activityVC.completionWithItemsHandler = { [weak self] _, completed, _, _ in
            self?.resolvePromise(callbackId: callbackId, result: "{\"success\": \(completed)}")
        }
        
        topVC.present(activityVC, animated: true)
    }
    
    private func handleHaptic(style: String) {
        let generator: UIImpactFeedbackGenerator
        switch style.lowercased() {
        case "light":
            generator = UIImpactFeedbackGenerator(style: .light)
        case "heavy":
            generator = UIImpactFeedbackGenerator(style: .heavy)
        default:
            generator = UIImpactFeedbackGenerator(style: .medium)
        }
        generator.prepare()
        generator.impactOccurred()
    }
    
    private func handleAlert(callbackId: Int, title: String, message: String, buttons: [String]) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        for (index, buttonTitle) in buttons.enumerated() {
            let action = UIAlertAction(title: buttonTitle, style: .default) { [weak self] _ in
                self?.resolvePromise(callbackId: callbackId, result: "\(index)")
            }
            alert.addAction(action)
        }
        
        guard let topVC = getTopVC() else {
            rejectPromise(callbackId: callbackId, error: "Could not present alert")
            return
        }
        
        topVC.present(alert, animated: true)
    }
    
    private func handleToast(message: String) {
        guard let topVC = getTopVC() else { return }
        
        let toastContainer = UIView()
        toastContainer.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        toastContainer.layer.cornerRadius = 14
        toastContainer.clipsToBounds = true
        toastContainer.alpha = 0
        toastContainer.translatesAutoresizingMaskIntoConstraints = false
        
        let label = UILabel()
        label.textColor = .white
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.text = message
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        
        toastContainer.addSubview(label)
        topVC.view.addSubview(toastContainer)
        
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: toastContainer.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: toastContainer.bottomAnchor, constant: -10),
            label.leadingAnchor.constraint(equalTo: toastContainer.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: toastContainer.trailingAnchor, constant: -18),
            
            toastContainer.centerXAnchor.constraint(equalTo: topVC.view.centerXAnchor),
            toastContainer.bottomAnchor.constraint(equalTo: topVC.view.safeAreaLayoutGuide.bottomAnchor, constant: -60),
            toastContainer.widthAnchor.constraint(lessThanOrEqualTo: topVC.view.widthAnchor, multiplier: 0.85)
        ])
        
        UIView.animate(withDuration: 0.25, animations: {
            toastContainer.alpha = 1.0
        }) { _ in
            UIView.animate(withDuration: 0.25, delay: 2.2, options: .curveEaseOut, animations: {
                toastContainer.alpha = 0.0
            }) { _ in
                toastContainer.removeFromSuperview()
            }
        }
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .other || navigationAction.request.url?.scheme == "about" {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }
    
    // MARK: - WKUIDelegate
    
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        getTopVC()?.present(alert, animated: true)
    }
    
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        getTopVC()?.present(alert, animated: true)
    }
}

// MARK: - Delegations

extension CanvasBridgeCoordinator: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        
        let callbackKeys = pendingCallbacks.keys
        guard let callbackId = callbackKeys.first else { return }
        let callback = pendingCallbacks.removeValue(forKey: callbackId)
        
        guard let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage,
              let resizedImage = image.resizedForCanvas(),
              let data = resizedImage.jpegData(compressionQuality: 0.8) else {
            callback?(nil)
            return
        }
        
        let base64String = data.base64EncodedString()
        let dataUrl = "data:image/jpeg;base64,\(base64String)"
        callback?(dataUrl)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        
        let callbackKeys = pendingCallbacks.keys
        guard let callbackId = callbackKeys.first else { return }
        let callback = pendingCallbacks.removeValue(forKey: callbackId)
        callback?(nil)
    }
}

extension CanvasBridgeCoordinator: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        let callbackKeys = pendingCallbacks.keys
        for callbackId in callbackKeys {
            if let callback = pendingCallbacks.removeValue(forKey: callbackId) {
                callback(nil)
            }
        }
    }
}

extension CanvasBridgeCoordinator: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        
        let callbackKeys = pendingCallbacks.keys
        guard let callbackId = callbackKeys.first else { return }
        let callback = pendingCallbacks.removeValue(forKey: callbackId)
        
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
            callback?(nil)
            return
        }
        
        provider.loadObject(ofClass: UIImage.self) { image, error in
            guard let uiImage = image as? UIImage,
                  let resizedImage = uiImage.resizedForCanvas(),
                  let data = resizedImage.jpegData(compressionQuality: 0.8) else {
                DispatchQueue.main.async {
                    callback?(nil)
                }
                return
            }
            
            let base64String = data.base64EncodedString()
            let dataUrl = "data:image/jpeg;base64,\(base64String)"
            DispatchQueue.main.async {
                callback?(dataUrl)
            }
        }
    }
}

extension CanvasBridgeCoordinator: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let callbackKeys = pendingCallbacks.keys
        guard let callbackId = callbackKeys.first else { return }
        let callback = pendingCallbacks.removeValue(forKey: callbackId)
        
        guard let url = urls.first else {
            callback?(nil)
            return
        }
        
        let secureAccess = url.startAccessingSecurityScopedResource()
        defer {
            if secureAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            let data = try Data(contentsOf: url)
            let name = url.lastPathComponent
            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let base64 = data.base64EncodedString()
            let dataUrl = "data:\(mimeType);base64,\(base64)"
            
            var text: String? = nil
            if mimeType.contains("text") || mimeType.contains("json") {
                text = String(data: data, encoding: .utf8)
            }
            
            var result: [String: Any] = [
                "name": name,
                "type": mimeType,
                "dataUrl": dataUrl
            ]
            if let text = text {
                result["text"] = text
            }
            callback?(result)
        } catch {
            print("⚠️ Failed to read document: \(error)")
            callback?(nil)
        }
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        let callbackKeys = pendingCallbacks.keys
        guard let callbackId = callbackKeys.first else { return }
        let callback = pendingCallbacks.removeValue(forKey: callbackId)
        callback?(nil)
    }
}

// MARK: - Helpers

fileprivate extension UIImage {
    /// Resize image to max 1280px dimension to avoid memory bloat in Base64 transfer.
    func resizedForCanvas() -> UIImage? {
        let maxDimension: CGFloat = 1280
        let size = self.size
        
        guard size.width > maxDimension || size.height > maxDimension else {
            return self
        }
        
        let aspect = size.width / size.height
        let newSize: CGSize
        if aspect > 1 {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspect)
        } else {
            newSize = CGSize(width: maxDimension * aspect, height: maxDimension)
        }
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        self.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resized
    }
}


fileprivate extension String {
    func trimmed() -> String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

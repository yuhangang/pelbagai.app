import SwiftUI
import Combine
import PhotosUI
import CoreImage

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@MainActor
class ToolPageViewModel: ObservableObject {
    let toolID: String
    private let environment: AppEnvironment
    
    @Published var savedResults: [ScanResult] = []
    @Published var textInput: String = ""
    @Published var selectedPhotoItem: PhotosPickerItem?
    @Published var capturedImage: UIImage?
    @Published var pendingImage: UIImage?

    @Published var showCamera = false
    @Published var showExportSheet = false
    @Published var exportFileURL: URL?
    @Published var editingResult: ScanResult?
    @Published var showEditSheet = false
    @Published var isProcessingText = false
    @Published var promptResponses: [ToolPromptResponse] = []
    
    // Model state mirroring
    @Published var isLoadingModels = false
    @Published var isModelLoaded = false
    @Published var isProcessing = false
    @Published var status = ""
    @Published var lastResult: ScanResult?
    
    private let exporter = ExcelExporter()
    private var cancellables = Set<AnyCancellable>()
    
    init(toolID: String, environment: AppEnvironment) {
        self.toolID = toolID
        self.environment = environment
        
        setupBindings()
        loadStoredResults()
    }
    
    private func setupBindings() {
        environment.mlx.$isLoading
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.isLoadingModels = $0 }
            .store(in: &cancellables)
        
        environment.vision.$isProcessing
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.isProcessing = $0 }
            .store(in: &cancellables)
        
        environment.vision.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.status = $0 }
            .store(in: &cancellables)
        
        environment.vision.$lastResult
            .receive(on: RunLoop.main)
            .map { [weak self] res -> ScanResult? in
                guard let toolID = self?.toolID else { return nil }
                return res?.toolID == toolID ? res : nil
            }
            .sink { [weak self] in self?.lastResult = $0 }
            .store(in: &cancellables)
        
        Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.isModelLoaded = self.environment.vision.isModelLoaded
            }
            .store(in: &cancellables)
    }
    
    var tool: LocalToolDefinition {
        environment.registry.definition(for: toolID) ?? LocalToolDefinition(
            toolID: toolID, displayName: toolID.replacingOccurrences(of: "_", with: " ").capitalized,
            description: "Custom tool"
        )
    }
    
    var toolColor: Color {
        tool.uiColor
    }
    
    var toolIcon: String {
        tool.uiIcon
    }
    
    func resetSessionState() {
        environment.vision.lastResult = nil
        environment.vision.status = ""
    }
    
    func loadStoredResults() {
        savedResults = environment.storage.loadAll(from: toolID)
    }
    
    func sendTextInput() {
        let text = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let image = pendingImage {
            let userPrompt = text.isEmpty ? "📷 Image captured" : text
            promptResponses.append(ToolPromptResponse(text: userPrompt, isUser: true, image: image))
            pendingImage = nil
            textInput = ""
            Task { await processImage(image, customPrompt: text.isEmpty ? nil : text) }
            return
        }
        
        guard !text.isEmpty else { return }
        
        promptResponses.append(ToolPromptResponse(text: text, isUser: true))
        textInput = ""
        
        Task { await processTextInput(text) }
    }
    
    func processTextInput(_ text: String) async {
        if !environment.vision.isModelLoaded {
            await environment.vision.loadModel()
        }
        
        isProcessingText = true
        defer { isProcessingText = false }
        
        let history = Array(toolInteractionHistory().suffix(2))
        await environment.gemma.generateToolOutput(
            text: text,
            definition: tool,
            history: history,
            stateOverride: toolStateOverride()
        )
        
        let output = environment.gemma.response
        if !output.isEmpty {
            handleModelTextOutput(output)
        }
    }
    
    private func toolInteractionHistory() -> [ChatMessage] {
        promptResponses.map { response in
            let role: ChatMessage.MessageRole = response.isUser ? .user : .assistant
            var content = response.text
            if response.isHiddenContext, let data = response.contextData {
                content = "TOOL KNOWLEDGE ADDED:\n" + data.map { "\($0): \($1)" }.joined(separator: "\n")
            }
            return ChatMessage(id: response.id, sessionId: UUID(), role: role, content: content, imageData: nil, timestamp: response.timestamp)
        }
    }
    
    private func handleModelTextOutput(_ output: String) {
        var scanResult = environment.vision.parseResponse(output, definition: tool)
        if (scanResult.state?.isEmpty ?? true),
           let stateOverride = toolStateOverride() {
            scanResult.state = stateOverride
        }
        environment.vision.lastResult = scanResult

        Task { [weak self] in
            guard let self = self else { return }
            let execution = await self.environment.tools.execute(result: scanResult, definition: self.tool)
            guard !execution.responses.isEmpty else {
                await MainActor.run {
                    self.appendDefaultModelOutput(output, scanResult: scanResult)
                }
                return
            }
            await MainActor.run {
                self.environment.vision.lastResult = execution.scanResult
                self.lastResult = execution.scanResult
                self.appendToolResponses(execution.responses)
            }
        }
    }

    private func appendDefaultModelOutput(_ output: String, scanResult: ScanResult) {
        if !scanResult.actions.isEmpty {
            environment.vision.lastResult = scanResult
            lastResult = scanResult
        }

        if let data = output.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let answer = json["answer"] as? String {
                promptResponses.append(ToolPromptResponse(text: answer, isUser: false))
            } else {
                promptResponses.append(ToolPromptResponse(text: "📋 Extracted details from prompt. Please review and confirm below.", isUser: false))
            }
            
            if let actionName = json["_action"] as? String,
               tool.runtimeActions?[actionName] == nil,
               let actionDef = tool.actions?[actionName],
               actionDef.effect == .run_js,
               let script = actionDef.script {
                NotificationCenter.default.post(
                    name: NSNotification.Name("TriggerWebViewAction"),
                    object: nil,
                    userInfo: ["action": "run_script", "payload": ["script": script, "data": output]]
                )
            }
        } else {
            if !output.isEmpty {
                promptResponses.append(ToolPromptResponse(text: output, isUser: false))
            }
        }
    }
    
    func handlePhotoSelection(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let uiImage = UIImage(data: data) {
            pendingImage = uiImage
        }
    }
    
    func processImage(_ image: UIImage, customPrompt: String? = nil) async {

        guard let ciImage = ImageInputPreparer.ciImage(from: image) else {
            promptResponses.append(ToolPromptResponse(text: "Failed to process image", isUser: false))
            return
        }
        if !environment.vision.isModelLoaded {
            await environment.vision.loadModel()
        }
        
        let result: ScanResult?
        if let prompt = customPrompt {
            // If there's a custom prompt, we use Gemma to generate the output based on image and prompt
            let history = Array(toolInteractionHistory().suffix(2))
            await environment.gemma.generateToolOutput(
                text: prompt,
                definition: tool,
                history: history,
                stateOverride: toolStateOverride()
            )
            let output = environment.gemma.response
            if !output.isEmpty {
                handleModelTextOutput(output)
            }
            return
        } else {
            result = await environment.vision.scan(image: ciImage, definition: tool)
        }

        if let result {
            let execution = await environment.tools.execute(result: result, definition: tool)
            environment.vision.lastResult = execution.scanResult
            lastResult = execution.scanResult
            appendToolResponses(execution.responses)
        }
        
        if let res = result,
           let actionFieldValue = res.richFields["_action"],
           case .string(let actionName) = actionFieldValue,
           tool.runtimeActions?[actionName] == nil,
           let actionDef = tool.actions?[actionName],
           actionDef.effect == .run_js,
           let script = actionDef.script {
            if let data = try? JSONEncoder().encode(res),
               let dataString = String(data: data, encoding: .utf8) {
                NotificationCenter.default.post(
                    name: NSNotification.Name("TriggerWebViewAction"),
                    object: nil,
                    userInfo: ["action": "run_script", "payload": ["script": script, "data": dataString]]
                )
            }
        }
    }

    private func appendToolResponses(_ responses: [ToolManager.Response]) {
        for response in responses {
            promptResponses.append(
                ToolPromptResponse(
                    text: response.text,
                    isUser: false,
                    imageURL: response.imageURL,
                    isHiddenContext: response.isHiddenContext,
                    contextData: response.contextData
                )
            )
        }
    }

    private func toolStateOverride() -> [String: String]? {
        let shouldUseRuntimeState =
            tool.capabilities.contains(.persistentState)
            || !(tool.stateBridges?.filter(\.fallbackToState).isEmpty ?? true)
        guard shouldUseRuntimeState else { return nil }

        if let liveState = lastResult?.state, !liveState.isEmpty {
            return liveState
        }

        let persistedState = environment.storage.latestState(for: tool.toolID)
        return persistedState.isEmpty ? nil : persistedState
    }
    
    func exportCurrentResults() {
        var resultsToExport = savedResults
        if let last = environment.vision.lastResult, last.toolID == toolID {
            resultsToExport.insert(last, at: 0)
        }
        
        if let url = exporter.exportToCSV(results: resultsToExport) {
            exportFileURL = url
            showExportSheet = true
        }
    }
    
    func updateResult(_ updated: ScanResult) {
        environment.storage.update(updated, in: tool.toolID)
        if let idx = savedResults.firstIndex(where: { $0.id == updated.id }) {
            savedResults[idx] = updated
        }
    }
    
    func executeDynamicAction(_ actionDef: LocalToolDefinition.ActionDefinition, payload: [String: String]) {
        switch actionDef.effect {
        case .store:
            let result = ScanResult(toolID: tool.toolID, richFields: payload.mapValues { .string($0) }, state: [:])
            environment.storage.save(result, to: tool.toolID)
            loadStoredResults()
            if let msg = actionDef.message {
                promptResponses.append(ToolPromptResponse(text: msg, isUser: false))
            }
        case .notify:
            if let msg = actionDef.message {
                promptResponses.append(ToolPromptResponse(text: msg, isUser: false))
            }
        case .open:
#if os(iOS)
            if let urlStr = payload["url"], let url = URL(string: urlStr) {
                UIApplication.shared.open(url)
            }
#elseif os(macOS)
            if let urlStr = payload["url"], let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            }
#endif
        default:
            break
        }
    }
    
    func handleSaveAction(_ payload: [String: String]) {
        let result = ScanResult(toolID: tool.toolID, richFields: payload.mapValues { .string($0) }, state: [:])
        environment.storage.save(result, to: tool.toolID)
        loadStoredResults()
        promptResponses.append(ToolPromptResponse(text: "✅ Saved", isUser: false))
    }
    
    func handleGetResultsAction() {
        if let data = try? JSONEncoder().encode(savedResults),
           let jsonString = String(data: data, encoding: .utf8) {
            NotificationCenter.default.post(
                name: NSNotification.Name("TriggerWebViewAction"),
                object: nil,
                userInfo: ["action": "results_data", "payload": ["json": jsonString]]
            )
        }
    }
    
    func handleSaveCSVAction(_ payload: [String: String]) {
        if let csv = payload["csv"], let filename = payload["filename"] {
            if let url = exporter.exportCustomCSV(content: csv, filename: filename) {
                exportFileURL = url
                showExportSheet = true
            }
        }
    }
    
    func handleStandardWebViewAction(_ message: ToolWebViewMessage) {
        switch message.action {
        case "save": handleSaveAction(message.payload)
        case "get_results": handleGetResultsAction()
        case "save_custom_csv": handleSaveCSVAction(message.payload)
        case "chat":
            let text = message.payload["text"] ?? ""
            let imageURL = message.payload["imageURL"]
            promptResponses.append(ToolPromptResponse(text: text, isUser: false, imageURL: imageURL))
        case "context":
            if let key = message.payload["key"], let value = message.payload["value"] {
                promptResponses.append(ToolPromptResponse(text: "🔍 [Knowledge Added: \(key)]", isUser: false, isHiddenContext: true, contextData: [key: value]))
            }
        case "model_input":
            if let text = message.payload["text"] {
                promptResponses.append(ToolPromptResponse(text: "🛠 Tool Result: \(text)", isUser: false, isHiddenContext: true))
                Task { await processTextInput("The tool returned the following information. Please use it to answer the user's last question:\n\n\(text)") }
            }
        case "notify":
            if let msg = message.payload["message"] {
                promptResponses.append(ToolPromptResponse(text: msg, isUser: false))
            }
        case "navigate":
#if os(iOS)
            if let urlStr = message.payload["url"], let url = URL(string: urlStr) {
                UIApplication.shared.open(url)
            }
#elseif os(macOS)
            if let urlStr = message.payload["url"], let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            }
#endif
        default: break
        }
        
    }
}

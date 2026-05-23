import SwiftUI
import Combine
import PhotosUI
import CoreImage
import AVFAudio

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@MainActor
class WorkbenchViewModel: ObservableObject {
    @Published var toolID: String
    private let environment: AppEnvironment
    
    @Published var savedResults: [ScanResult] = []
    @Published var textInput: String = ""
    @Published var selectedPhotoItem: PhotosPickerItem?
    @Published var capturedImage: UIImage?
    @Published var pendingImage: UIImage?
    @Published var isRecording = false
    @Published var speechBuffer: [Float] = []

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
    @Published var allDefinitions: [LocalToolDefinition] = []
    @Published var activeWorkflowRun: WorkflowRun?
    @Published var workflowArtifact: WorkflowArtifact?
    @Published var isWorkflowRunning = false
    @Published var workflowStatus = ""
    
    private let exporter = ExcelExporter()
    private let audioService = AudioService()
    private let attachmentService = AttachmentService()
    private var cancellables = Set<AnyCancellable>()
    
    init(toolID: String, environment: AppEnvironment) {
        self.toolID = toolID
        self.environment = environment
        
        setupBindings()
        loadStoredResults()
    }
    
    func switchToTool(_ newToolID: String) {
        guard newToolID != toolID else { return }
        toolID = newToolID
        resetSessionState()
        loadStoredResults()
        promptResponses.removeAll()
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
        
        environment.registry.$allDefinitions
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.allDefinitions = $0 }
            .store(in: &cancellables)

        environment.workflows.$activeRun
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.activeWorkflowRun = $0 }
            .store(in: &cancellables)

        environment.workflows.$lastArtifact
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.workflowArtifact = $0 }
            .store(in: &cancellables)

        environment.workflows.$isRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.isWorkflowRunning = $0 }
            .store(in: &cancellables)

        environment.workflows.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.workflowStatus = $0 }
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

        if let target = workflowTarget(for: text) ?? (tool.workflow == nil ? nil : tool) {
            Task { await runConfiguredWorkflow(targetDefinition: target, latestSourceResult: nil, reason: text) }
            return
        }
        
        Task { await processTextInput(text) }
    }
    
    func processTextInput(_ text: String) async {
        await MainActor.run { self.isProcessingText = true }
        await LLMRequestQueue.shared.enqueue { [weak self] in
            guard let self = self else { return }
            
            defer { Task { @MainActor [weak self] in self?.isProcessingText = false } }
            
            let isLoaded = await MainActor.run { self.environment.gemma.isModelLoaded }
            if !isLoaded {
                let didLoad = await self.environment.gemma.loadModel()
                guard didLoad else {
                    await MainActor.run {
                        let message = self.environment.gemma.lastErrorMessage ?? "Model failed to load"
                        self.promptResponses.append(ToolPromptResponse(text: message, isUser: false))
                    }
                    return
                }
            }
            
            let history = await MainActor.run { Array(self.toolInteractionHistory().suffix(2)) }
            let override = await MainActor.run { self.toolStateOverride() }
            let definition = await MainActor.run { self.tool }
            
            await self.environment.gemma.generateToolOutput(
                text: text,
                definition: definition,
                history: history,
                stateOverride: override
            )
            
            let output = await MainActor.run { self.environment.gemma.response }
            if !output.isEmpty {
                await MainActor.run { self.handleModelTextOutput(output) }
            }
        }
    }
    
    private func toolInteractionHistory() -> [ChatMessage] {
        promptResponses.map { response in
            let role: ChatMessage.MessageRole = response.isUser ? .user : .assistant
            var content = response.text
            if response.isHiddenContext, let data = response.contextData {
                content = "TOOL KNOWLEDGE ADDED:\n" + data.map { "\($0): \($1)" }.joined(separator: "\n")
            }
            return ChatMessage(
                id: response.id,
                sessionId: UUID(),
                role: role,
                content: content,
                imageData: nil,
                attachmentsData: nil,
                timestamp: response.timestamp
            )
        }
    }
    
    private func handleModelTextOutput(_ output: String) {
        var scanResult = environment.vision.parseResponse(output, definition: tool)
        if (scanResult.state?.isEmpty ?? true),
           let stateOverride = toolStateOverride() {
            scanResult.state = stateOverride
        }
        environment.vision.lastResult = scanResult
        
        // Auto-save agentic extractions if they are validated
        if scanResult.isValidated && scanResult.hasData {
            environment.storage.save(scanResult, to: toolID)
            loadStoredResults()
        }

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
                self.appendToolResponses(execution.responses, extractedTopic: execution.scanResult.richFields["topic"]?.flatString ?? execution.scanResult.richFields["subject"]?.flatString ?? execution.scanResult.richFields["query"]?.flatString)
            }
        }
    }

    private func appendDefaultModelOutput(_ output: String, scanResult: ScanResult) {
        if !scanResult.actions.isEmpty {
            environment.vision.lastResult = scanResult
            lastResult = scanResult
        }

        // Inject inline scan result card when we have extracted data
        if scanResult.hasData {
            promptResponses.append(ToolPromptResponse(
                text: "",
                isUser: false,
                scanResult: scanResult
            ))
        }

        if let data = output.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let answer = json["answer"] as? String {
                promptResponses.append(ToolPromptResponse(text: answer, isUser: false))
            } else if !scanResult.hasData {
                // Only show fallback text if we didn't already show the scan card
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
            if !output.isEmpty && !scanResult.hasData {
                promptResponses.append(ToolPromptResponse(text: output, isUser: false))
            }
        }
    }
    
    func handlePhotoSelection(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let uiImage = ImageInputPreparer.image(from: data) {
            pendingImage = uiImage
        }
    }
    
    func processImage(_ image: UIImage, customPrompt: String? = nil) async {
        await MainActor.run {
            self.isProcessing = true
            self.environment.vision.isProcessing = true
            self.environment.vision.status = "Preparing..."
        }
        await LLMRequestQueue.shared.enqueue { [weak self] in
            guard let self = self else { return }
            
            defer {
                Task { @MainActor [weak self] in
                    self?.isProcessing = false
                    self?.environment.vision.isProcessing = false
                }
            }
            
            let preparedImage = ImageInputPreparer.preparedForModel(image)
            let isLoaded = await MainActor.run { self.environment.gemma.isModelLoaded }
            if !isLoaded {
                let didLoad = await self.environment.gemma.loadModel()
                guard didLoad else {
                    await MainActor.run {
                        let message = self.environment.gemma.lastErrorMessage ?? "Model failed to load"
                        self.environment.vision.status = message
                        self.promptResponses.append(ToolPromptResponse(text: message, isUser: false))
                    }
                    return
                }
            }
            
            let definition = await MainActor.run { self.tool }
            let prompt = await MainActor.run {
                self.environment.vision.compactImagePrompt(for: definition, customPrompt: customPrompt)
            }

            await MainActor.run {
                self.environment.vision.status = "Analyzing image..."
                self.environment.vision.lastResult = nil
            }

            let output = await self.environment.gemma.generate(
                prompt: prompt,
                image: preparedImage,
                history: [],
                maxTokens: 256,
                imageSoftTokenCap: 16,
                retryEmptyImageOutput: false,
                prefillStepSizeOverride: 32
            )
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedOutput.isEmpty else {
                await MainActor.run {
                    self.environment.vision.status = "Scan failed: empty model response"
                    self.promptResponses.append(ToolPromptResponse(text: "I could not extract data from this image. Please try again.", isUser: false))
                }
                return
            }

            let result = await MainActor.run {
                self.environment.vision.parseResponse(trimmedOutput, definition: definition)
            }

            let execution = await self.environment.tools.execute(result: result, definition: definition)
            await MainActor.run {
                self.environment.vision.lastResult = execution.scanResult
                self.environment.vision.status = execution.scanResult.hasData ? "✅ Data extracted" : "⚠️ Limited results"
                self.lastResult = execution.scanResult
                if execution.responses.isEmpty {
                    self.appendDefaultModelOutput(trimmedOutput, scanResult: execution.scanResult)
                } else {
                    self.appendToolResponses(execution.responses, extractedTopic: execution.scanResult.richFields["topic"]?.flatString ?? execution.scanResult.richFields["subject"]?.flatString ?? execution.scanResult.richFields["query"]?.flatString)
                }
                
                if execution.scanResult.isValidated && execution.scanResult.hasData {
                    self.environment.storage.save(execution.scanResult, to: self.toolID)
                    self.loadStoredResults()
                }

                if let target = self.workflowTarget(for: customPrompt) {
                    Task {
                        await self.runConfiguredWorkflow(
                            targetDefinition: target,
                            latestSourceResult: execution.scanResult,
                            reason: customPrompt ?? "Source tool requested a workflow."
                        )
                    }
                }
            }
            
            await MainActor.run {
                if let actionFieldValue = result.richFields["_action"],
                   case .string(let actionName) = actionFieldValue,
                   self.tool.runtimeActions?[actionName] == nil,
                   let actionDef = self.tool.actions?[actionName],
                   actionDef.effect == .run_js,
                   let script = actionDef.script {
                    if let data = try? JSONEncoder().encode(execution.scanResult),
                       let dataString = String(data: data, encoding: .utf8) {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("TriggerWebViewAction"),
                            object: nil,
                            userInfo: ["action": "run_script", "payload": ["script": script, "data": dataString]]
                        )
                    }
                }
            }
        }
    }

    private func appendToolResponses(_ responses: [ToolManager.Response], extractedTopic: String?) {
        for response in responses {
            promptResponses.append(
                ToolPromptResponse(
                    text: response.text,
                    isUser: false,
                    imageURL: response.imageURL,
                    isHiddenContext: response.isHiddenContext,
                    contextData: response.contextData,
                    extractedTopic: extractedTopic
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

    private func workflowTarget(for userPrompt: String?) -> LocalToolDefinition? {
        WorkflowPlanner.workflowTarget(
            forSourceToolID: toolID,
            userPrompt: userPrompt,
            definitions: allDefinitions
        )
    }

    private func defaultWorkflowTarget() -> LocalToolDefinition? {
        if tool.workflow != nil {
            return tool
        }
        return allDefinitions.first { definition in
            definition.workflow?.triggerSourceToolIDs.contains(toolID) == true
        }
    }

    func runConfiguredWorkflow(
        targetDefinition: LocalToolDefinition? = nil,
        latestSourceResult: ScanResult? = nil,
        reason: String = "Run configured workflow"
    ) async {
        guard let targetDefinition = targetDefinition ?? defaultWorkflowTarget() else {
            await MainActor.run {
                self.promptResponses.append(
                    ToolPromptResponse(text: "No configured workflow is available for this tool.", isUser: false)
                )
            }
            return
        }

        let result = await environment.workflows.runWorkflow(
            targetDefinition: targetDefinition,
            latestSourceResult: latestSourceResult,
            reason: reason
        )

        await MainActor.run {
            self.activeWorkflowRun = result.run
            self.workflowArtifact = result.artifact
            if self.toolID == targetDefinition.toolID {
                self.loadStoredResults()
                self.lastResult = result.outputResult
            }

            if let artifact = result.artifact {
                self.promptResponses.append(
                    ToolPromptResponse(
                        text: artifact.summary,
                        isUser: false
                    )
                )
            } else if result.run.status == .failed {
                self.promptResponses.append(
                    ToolPromptResponse(
                        text: result.run.events.last?.detail ?? "I could not generate a report from the saved receipts.",
                        isUser: false
                    )
                )
            }
        }
    }
    
    func updateResult(_ updated: ScanResult) {
        environment.storage.update(updated, in: tool.toolID)
        if let idx = savedResults.firstIndex(where: { $0.id == updated.id }) {
            savedResults[idx] = updated
        }
    }
    
    func saveResult(_ result: ScanResult) {
        environment.storage.save(result, to: toolID)
        loadStoredResults()
    }
    
    func deleteResult(_ result: ScanResult) {
        environment.storage.delete(resultID: result.id, from: toolID)
        savedResults.removeAll { $0.id == result.id }
    }
    
    func clearHistory() {
        environment.storage.clearTool(toolID)
        savedResults.removeAll()
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

    // MARK: - Confirm Chat Item Handling

    func handleConfirmChoice(_ option: ConfirmChatOption) {
        // Append the user's selection as a message in the timeline
        promptResponses.append(ToolPromptResponse(text: option.title, isUser: true))
        // Forward the selection as a text input to continue conversation
        Task {
            await processTextInput(option.title)
        }
    }

    // MARK: - Audio & Voice Input

    func handleMicTap() {
        if isRecording {
            Task {
                await stopVoiceInputAndSend()
            }
        } else {
            Task {
                await startVoiceInput()
            }
        }
    }

    func startVoiceInput() async {
        guard !isLoadingModels else { return }
        
        speechBuffer.removeAll()
        isRecording = true
        
        do {
            try audioService.startRecording { [weak self] audioBuffer in
                guard let self = self else { return }
                if let channelData = audioBuffer.floatChannelData?[0] {
                    let frames = Int(audioBuffer.frameLength)
                    let samples = Array(UnsafeBufferPointer(start: channelData, count: frames))
                    
                    Task { @MainActor in
                        self.speechBuffer.append(contentsOf: samples)
                    }
                }
            }
        } catch {
            print("Failed to start audio engine: \(error)")
            isRecording = false
        }
    }

    func stopVoiceInputAndSend() async {
        audioService.stopRecording()
        isRecording = false
        
        let audioData = speechBuffer
        speechBuffer.removeAll()
        
        if !audioData.isEmpty {
            sendAudioMessage(audioData)
        }
    }

    func sendAudioMessage(_ audio: [Float]) {
        promptResponses.append(ToolPromptResponse(text: "🎤 Processing audio...", isUser: true))
        
        Task {
            do {
                let selectedModel = await MainActor.run { self.environment.gemma.selectedModel }
                let voicePolicy = VoiceRuntimePolicy(selectedModel: selectedModel)
                
                let transcript = try await self.transcribeWithWhisper(audio, policy: voicePolicy)
                print("🎤 [WorkbenchVM] Voice transcript: \"\(transcript.prefix(80))\"")
                
                await MainActor.run {
                    if let idx = self.promptResponses.lastIndex(where: { $0.text == "🎤 Processing audio..." }) {
                        self.promptResponses.remove(at: idx)
                    }
                    self.promptResponses.append(ToolPromptResponse(text: "🎤 \(transcript)", isUser: true))
                    
                    if let target = self.workflowTarget(for: transcript) ?? (self.tool.workflow == nil ? nil : self.tool) {
                        Task { await self.runConfiguredWorkflow(targetDefinition: target, latestSourceResult: nil, reason: transcript) }
                    } else {
                        Task { await self.processTextInput(transcript) }
                    }
                }
            } catch {
                await MainActor.run {
                    if let idx = self.promptResponses.lastIndex(where: { $0.text == "🎤 Processing audio..." }) {
                        self.promptResponses.remove(at: idx)
                    }
                    self.promptResponses.append(ToolPromptResponse(text: "I could not transcribe the voice message. \(error.localizedDescription)", isUser: false))
                }
            }
        }
    }

    private func transcribeWithWhisper(_ audio: [Float], policy: VoiceRuntimePolicy) async throws -> String {
        if policy.shouldUnloadGemmaBeforeWhisper {
            await environment.gemma.unloadModel()
        } else {
            environment.mlx.clearCache()
        }
        let transcript = try await environment.whisper.transcribe(samples: audio)
        await environment.whisper.unloadModel()
        return transcript
    }

    // MARK: - File Attachment Input

    func handleImportedFile(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            guard url.startAccessingSecurityScopedResource() else {
                print("🧠 WorkbenchVM: Cannot access security scoped resource")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let extractedText = try attachmentService.extractText(from: url)
                let filename = url.lastPathComponent
                
                let localName = try saveAttachmentToStorage(from: url)
                
                promptResponses.append(ToolPromptResponse(text: "📄 Attached: \(filename)\n\n\(extractedText.prefix(300))...", isUser: true))
                
                if let target = self.workflowTarget(for: extractedText) ?? (self.tool.workflow == nil ? nil : self.tool) {
                    Task { await self.runConfiguredWorkflow(targetDefinition: target, latestSourceResult: nil, reason: extractedText) }
                } else {
                    Task { await self.processTextInput(extractedText) }
                }
                
                print("🧠 WorkbenchVM: Successfully processed attachment \(filename)")
            } catch {
                print("🧠 WorkbenchVM: Failed to process attachment: \(error)")
                promptResponses.append(ToolPromptResponse(text: "Failed to process attachment: \(error.localizedDescription)", isUser: false))
            }
            
        case .failure(let error):
            print("🧠 WorkbenchVM: File import failed: \(error)")
        }
    }
    
    private func saveAttachmentToStorage(from url: URL) throws -> String {
        let fileManager = FileManager.default
        let documentsURL = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let attachmentsDirectory = documentsURL.appendingPathComponent("Attachments", isDirectory: true)
        
        if !fileManager.fileExists(atPath: attachmentsDirectory.path) {
            try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        }
        
        let fileExtension = url.pathExtension
        let uniqueName = "\(UUID().uuidString).\(fileExtension)"
        let destinationURL = attachmentsDirectory.appendingPathComponent(uniqueName)
        
        try fileManager.copyItem(at: url, to: destinationURL)
        return uniqueName
    }
}

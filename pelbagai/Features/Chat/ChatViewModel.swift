import SwiftUI
import Combine
import AVFAudio

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@MainActor
class ChatViewModel: ObservableObject {
    let sessionId: UUID
    let initialPrompt: String?
    let environment: AppEnvironment
    
    @Published var messages: [ChatMessage] = []
    @Published var textInput: String = ""
    @Published var inputMode: ChatInputMode = .chat
    @Published var isRecording = false
    @Published var speechBuffer: [Float] = []
    @Published var showCamera = false
    @Published var capturedImage: UIImage?
    @Published var pendingImage: UIImage?

    
    // Model state mirroring from managers for easier View binding
    @Published var isLoadingModels = false
    @Published var loadingStatusText = ""
    @Published var isGenerating = false
    @Published var response = ""
    @Published var status = ""
    @Published var isModelLoaded = false
    @Published var userDefinitionsCount = 0
    @Published var clarificationRequest: ClarificationRequest?
    @Published var pendingToolCall: PendingToolCall?
    @Published var activeSkill: Skill? = nil
    @Published var availableSkills: [Skill] = []
    
    @Published var showDownloadWarning = false
    
    private let audioService = AudioService()
    private let attachmentService = AttachmentService()
    private var cancellables = Set<AnyCancellable>()
    
    deinit {
        Task { await LLMRequestQueue.shared.clear() }
    }
    
    init(sessionId: UUID, environment: AppEnvironment, initialPrompt: String? = nil, initialSkill: Skill? = nil) {
        self.sessionId = sessionId
        self.environment = environment
        self.initialPrompt = initialPrompt
        self.activeSkill = initialSkill
        
        setupBindings()
    }
    
    private func setupBindings() {
        // Bind to GemmaManager
        environment.gemma.$isGenerating
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.isGenerating = $0 }
            .store(in: &cancellables)
            
        environment.gemma.$response
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.response = $0 }
            .store(in: &cancellables)
            
        environment.gemma.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.status = $0 }
            .store(in: &cancellables)
            
        environment.gemma.$clarificationRequest
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.clarificationRequest = $0 }
            .store(in: &cancellables)

        environment.agent.$pendingToolCall
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.pendingToolCall = $0 }
            .store(in: &cancellables)
        
        // Bind to SkillRegistry
        Publishers.CombineLatest(environment.skills.$builtInSkills, environment.skills.$userSkills)
            .receive(on: RunLoop.main)
            .sink { [weak self] builtIn, user in
                self?.availableSkills = builtIn + user
            }
            .store(in: &cancellables)
        
        // Bind to MLXModelManager
        environment.mlx.$isLoading
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.isLoadingModels = $0 }
            .store(in: &cancellables)
            
        environment.mlx.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.loadingStatusText = $0 }
            .store(in: &cancellables)
        
        // Bind to ToolRegistry
        environment.registry.$userDefinitions
            .receive(on: RunLoop.main)
            .map { $0.count }
            .sink { [weak self] in self?.userDefinitionsCount = $0 }
            .store(in: &cancellables)
        
        // Computed like properties
        Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.isModelLoaded = self.environment.gemma.isModelLoaded
            }
            .store(in: &cancellables)
    }
    
    func loadMessages() {
        messages = environment.database.getMessages(for: sessionId)
    }
    
    func loadAllModels() async {
        // Only load if already downloaded
        guard environment.gemma.selectedModel.isDownloaded else {
            print("🧠 Chat: Model not downloaded, skipping auto-load")
            return
        }
        
        await performLoadAllModels()
    }
    
    func confirmDownload() {
        showDownloadWarning = false
        Task {
            await performLoadAllModels()
        }
    }
    
    private func performLoadAllModels() async {
        await environment.gemma.loadModel()
        
        // Auto-send initial prompt if provided and no messages exist yet
        if let prompt = initialPrompt, messages.isEmpty {
            sendMessage(prompt)
        }
    }
    
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
        
        environment.speech.stop()
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
        let conversationContext = messages
        let userMessage = ChatMessage(
            id: UUID(),
            sessionId: sessionId,
            role: .user,
            content: "[Audio Message]",
            imageData: nil,
            attachmentsData: nil,
            timestamp: Date()
        )
        messages.append(userMessage)
        environment.database.addMessage(userMessage)
        
        Task {
            await LLMRequestQueue.shared.enqueue { [weak self] in
                guard let self = self else { return }
                
                await MainActor.run {
                    self.isGenerating = true
                }

                do {
                    let selectedModel = await MainActor.run { self.environment.gemma.selectedModel }
                    let voicePolicy = VoiceRuntimePolicy(selectedModel: selectedModel)
                    if voicePolicy.shouldLoadGemmaAudioTower {
                        do {
                            let generatedText = try await self.generateDirectAudioResponse(
                                audio,
                                history: conversationContext
                            )

                            await MainActor.run {
                                self.isGenerating = false
                                self.completeGeneration(generatedText)

                                if self.messages.count <= 2 {
                                    Task {
                                        await self.performTitleUpdate(for: "Voice message")
                                    }
                                }
                            }
                            return
                        } catch {
                            print("🎤 [ChatVM] Gemma direct audio failed, falling back to Whisper: \(error)")
                            if voicePolicy.shouldUnloadGemmaBeforeWhisper {
                                await self.environment.gemma.unloadModel()
                            }
                        }
                    }

                    let transcript = try await self.transcribeWithWhisper(audio, policy: voicePolicy)
                    print("🎤 [ChatVM] Voice transcript: \"\(transcript.prefix(80))\"")

                    if let activeSkill = await MainActor.run { self.activeSkill } {
                        await MainActor.run {
                            self.environment.skills.recordSkillUsed(activeSkill)
                        }
                        let responseText = await self.processActiveSkillTurn(transcript, activeSkill: activeSkill, history: conversationContext)
                        await MainActor.run {
                            self.isGenerating = false
                            self.completeGeneration(responseText, activeSkill: activeSkill)
                            if self.messages.count <= 2 {
                                Task {
                                    await self.performTitleUpdate(for: transcript)
                                }
                            }
                        }
                    } else {
                        let result = await self.environment.agent.processText(
                            transcript,
                            sessionId: self.sessionId,
                            history: conversationContext
                        )

                        await MainActor.run {
                            self.isGenerating = false
                            self.completeAgentTurn(result)

                            if self.messages.count <= 2 {
                                Task {
                                    await self.performTitleUpdate(for: transcript)
                                }
                            }
                        }
                    }
                } catch {
                    await self.environment.whisper.unloadModel()
                    await MainActor.run {
                        self.isGenerating = false
                        self.addAssistantMessage("I could not transcribe the voice message clearly. \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func generateDirectAudioResponse(_ audio: [Float], history: [ChatMessage]) async throws -> String {
        let isLoaded = await MainActor.run { environment.gemma.isModelLoaded }
        if !isLoaded {
            _ = await environment.gemma.loadModel()
        }

        let prompt = """
        Listen to the voice message and answer the user's spoken request directly.
        If the speech is unclear, say you could not hear it clearly.
        """
        let response = await environment.gemma.generate(
            prompt: prompt,
            audio: audio,
            history: history
        )
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty
            || trimmed.localizedCaseInsensitiveContains("local model error")
            || trimmed.localizedCaseInsensitiveContains("model is not loaded")
        {
            throw WhisperManager.WhisperManagerError.emptyTranscript
        }

        return trimmed
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
    
    func sendImageMessage(_ image: UIImage, prompt: String? = nil) {
        let conversationContext = messages
        let preparedImage = ImageInputPreparer.preparedForModel(image)
        let imageData = ImageInputPreparer.data(from: preparedImage)
        
        let content = prompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? prompt! : "[Image Message]"
        
        let userMessage = ChatMessage(
            id: UUID(),
            sessionId: sessionId,
            role: .user,
            content: content,
            imageData: imageData,
            attachmentsData: nil,
            timestamp: Date()
        )
        messages.append(userMessage)
        environment.database.addMessage(userMessage)
        
        Task {
            await LLMRequestQueue.shared.enqueue { [weak self] in
                guard let self = self else { return }
                
                let isLoaded = await MainActor.run { self.environment.gemma.isModelLoaded }
                if !isLoaded {
                    await self.environment.gemma.loadModel()
                }
                
                let finalPrompt = content == "[Image Message]" ? "Please describe this image." : content
                let generatedText = await self.environment.gemma.generate(prompt: finalPrompt, image: preparedImage, history: conversationContext)
                
                await MainActor.run {
                    self.completeGeneration(generatedText)
                }
            }
        }
    }
    
    func sendTypedMessage() {
        let text = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let image = pendingImage {
            sendImageMessage(image, prompt: text.isEmpty ? nil : text)
            pendingImage = nil
            textInput = ""
            return
        }
        
        guard !text.isEmpty else { return }
        textInput = ""
        
        switch inputMode {
        case .chat:
            sendMessage(text)
        case .tool:
            sendToolDefinitionRequest(text)
        }
    }
    
    func sendMessage(_ text: String) {
        let conversationContext = messages
        let userMessage = ChatMessage(
            id: UUID(),
            sessionId: sessionId,
            role: .user,
            content: text,
            imageData: nil,
            attachmentsData: nil,
            timestamp: Date()
        )
        messages.append(userMessage)
        environment.database.addMessage(userMessage)
        
        
        Task {
            await LLMRequestQueue.shared.enqueue { [weak self] in
                guard let self = self else { return }
                
                print("📝 [ChatVM] Processing text message: \"\(text.prefix(20))...\"")
                
                let isLoaded = await MainActor.run { self.environment.gemma.isModelLoaded }
                if !isLoaded {
                    print("📝 [ChatVM] Model not loaded, initializing...")
                    _ = await self.environment.gemma.loadModel()
                }
                
                await MainActor.run {
                    self.isGenerating = true
                    self.detectAndActivateCanvasSkillIfNeeded(text: text, history: conversationContext)
                }
                
                if let activeSkill = await MainActor.run { self.activeSkill } {
                    await MainActor.run {
                        self.environment.skills.recordSkillUsed(activeSkill)
                    }
                    let responseText: String
                    if activeSkill.capabilities.contains(.canvas) {
                        responseText = await self.processCanvasTurn(text, activeSkill: activeSkill, history: conversationContext)
                    } else {
                        responseText = await self.processActiveSkillTurn(text, activeSkill: activeSkill, history: conversationContext)
                    }
                    await MainActor.run {
                        self.isGenerating = false
                        self.completeGeneration(responseText, activeSkill: activeSkill)
                        
                        // If this is the first message, generate a title
                        if self.messages.count <= 2 {
                            Task {
                                await self.performTitleUpdate(for: text)
                            }
                        }
                    }
                } else {
                    let result = await self.environment.agent.processText(
                        text,
                        sessionId: self.sessionId,
                        history: conversationContext
                    )
                    
                    await MainActor.run {
                        self.isGenerating = false
                        self.completeAgentTurn(result)
                        
                        // If this is the first message, generate a title
                        if self.messages.count <= 2 {
                            Task {
                                await self.performTitleUpdate(for: text)
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// Summarizes the first message into a session title.
    /// Enqueues title generation as a background task after the main response.
    private func performTitleUpdate(for prompt: String) async {
        guard messages.count <= 2 else { return }
        
        await LLMRequestQueue.shared.enqueue { [weak self] in
            guard let self = self else { return }
            
            print("📝 [ChatVM] Generating session title for: \"\(prompt.prefix(20))...\"")
            
            let isLoaded = await MainActor.run { self.environment.gemma.isModelLoaded }
            if !isLoaded {
                await self.environment.gemma.loadModel()
            }
            
            let messages = [
                ["role": "system", "content": "You are a helpful assistant. Reply with only the summarized title, no other text or quotes."],
                ["role": "user", "content": "Summarize this user request into a concise 3-4 word title: \"\(prompt)\""]
            ]
            
            let generatedTitle = await self.environment.gemma.generateText(messages: messages, silent: true)
            let cleanedTitle = generatedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
            
            print("📝 [ChatVM] Generated title: \"\(cleanedTitle)\"")
            
            if !cleanedTitle.isEmpty && cleanedTitle.count < 60 {
                await MainActor.run {
                    self.environment.database.updateSessionTitle(id: self.sessionId, newTitle: cleanedTitle)
                    NotificationCenter.default.post(name: .sessionUpdated, object: nil)
                }
            }
        }
    }
    
    private func completeGeneration(_ responseText: String, activeSkill: Skill? = nil) {
        var attachmentsData: Data? = nil
        var finalResponseText = responseText
        
        if let activeSkill = activeSkill {
            if activeSkill.capabilities.contains(.canvas) {
                if let html = extractHTML(from: responseText) {
                    do {
                        // Extract a nice app name for filename
                        var appName = activeSkill.name
                        if let titleRange = html.range(of: "<title>", options: .caseInsensitive),
                           let endTitleRange = html.range(of: "</title>", options: .caseInsensitive, range: titleRange.upperBound..<html.endIndex) {
                            let extracted = html[titleRange.upperBound..<endTitleRange.lowerBound]
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if !extracted.isEmpty {
                                appName = extracted.replacingOccurrences(of: " ", with: "_").lowercased()
                            }
                        }
                        
                        let filename = try self.saveHTMLAttachmentToStorage(htmlContent: html)
                        let attachment = ChatAttachment(
                            id: UUID(),
                            filename: "\(appName).html",
                            fileType: "html",
                            localPath: filename,
                            extractedText: "[AI Canvas Micro-App]"
                        )
                        attachmentsData = try JSONEncoder().encode([attachment])
                        finalResponseText = cleanResponseText(responseText)
                    } catch {
                        print("⚠️ [ChatVM] Failed to save generated HTML attachment: \(error)")
                    }
                }
            } else if let html = activeSkill.htmlContent {
                do {
                    let filename = try self.saveHTMLAttachmentToStorage(htmlContent: html)
                    let attachment = ChatAttachment(
                        id: UUID(),
                        filename: "\(activeSkill.name)_snapshot.html",
                        fileType: "html",
                        localPath: filename,
                        extractedText: "[HTML Snapshot of Skill Output]"
                    )
                    attachmentsData = try JSONEncoder().encode([attachment])
                } catch {
                    print("⚠️ [ChatVM] Failed to save initial HTML attachment: \(error)")
                }
            }
        }
        
        let aiMessage = ChatMessage(
            id: UUID(),
            sessionId: sessionId,
            role: .assistant,
            content: finalResponseText,
            imageData: nil,
            attachmentsData: attachmentsData,
            timestamp: Date()
        )
        messages.append(aiMessage)
        environment.database.addMessage(aiMessage)
        
        let ttsEnabled = UserDefaults.standard.bool(forKey: "ttsEnabled")
        if ttsEnabled && !finalResponseText.isEmpty {
            environment.speech.speak(finalResponseText)
        }
    }
    
    func handleClarificationChoice(_ choice: String) {
        clarificationRequest = nil
        sendMessage(choice)
    }

    func confirmPendingToolCall(arguments: [String: String]) {
        Task {
            await LLMRequestQueue.shared.enqueue { [weak self] in
                guard let self = self else { return }
                
                let result = await self.environment.agent.confirmPendingToolCall(
                    arguments: arguments,
                    sessionId: self.sessionId
                )
                
                await MainActor.run {
                    self.completeAgentTurn(result)
                }
            }
        }
    }

    func cancelPendingToolCall() {
        environment.agent.cancelPendingToolCall()
        pendingToolCall = nil
        addAssistantMessage("Action cancelled.")
    }

    func retryLastAgentResponse() {
        guard !isLoadingModels, !isGenerating else { return }
        guard let lastUserIndex = messages.lastIndex(where: { $0.role == .user }) else { return }

        let userMessage = messages[lastUserIndex]
        let retryText = userMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !retryText.isEmpty,
              userMessage.imageData == nil,
              retryText != "[Audio Message]",
              retryText != "[Audio Input]",
              retryText != "[Image Message]" else {
            addAssistantMessage("Retry is available for text agent messages only.")
            return
        }

        let removedMessages = Array(messages[lastUserIndex...])
        removedMessages.forEach { environment.database.deleteMessage(id: $0.id) }
        messages.removeSubrange(lastUserIndex...)
        environment.agent.cancelPendingToolCall()
        clarificationRequest = nil
        pendingToolCall = nil
        sendMessage(retryText)
    }
    
    // Tool Definition Logic
    func sendToolDefinitionRequest(_ request: String) {
        let userMessage = ChatMessage(
            id: UUID(),
            sessionId: sessionId,
            role: .user,
            content: "Create local tool: \(request)",
            imageData: nil,
            attachmentsData: nil,
            timestamp: Date()
        )
        messages.append(userMessage)
        environment.database.addMessage(userMessage)
        
        Task {
            await LLMRequestQueue.shared.enqueue { [weak self] in
                guard let self = self else { return }
                
                let isLoaded = await MainActor.run { self.environment.gemma.isModelLoaded }
                if !isLoaded {
                    await self.environment.gemma.loadModel()
                }
                
                let prompt = await MainActor.run { self.toolDefinitionPrompt(for: request) }
                let toolResponse = await self.environment.gemma.generate(prompt: prompt, history: [])
                
                await MainActor.run {
                    do {
                        let definition = try self.parseToolDefinition(from: toolResponse, request: request)
                        self.environment.registry.upsert(definition)
                        
                        // If this is the first message, generate a title
                        if self.messages.count <= 2 {
                            Task {
                                await self.performTitleUpdate(for: request)
                            }
                        }
                        
                        let assistantText = """
                        Created local tool "\(definition.displayName)".
                        
                        Tool ID: \(definition.toolID)
                        Capabilities: \(definition.capabilities.map(\.rawValue).joined(separator: ", "))
                        """
                        self.addAssistantMessage(assistantText)
                    } catch {
                        self.addAssistantMessage("I could not create that tool definition. \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    func renameSession(to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        environment.database.updateSessionTitle(id: sessionId, newTitle: trimmed)
        NotificationCenter.default.post(name: .sessionUpdated, object: nil)
    }

    func handleImportedFile(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            guard url.startAccessingSecurityScopedResource() else {
                print("🧠 ChatVM: Cannot access security scoped resource")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let extractedText = try attachmentService.extractText(from: url)
                let filename = url.lastPathComponent
                
                // Clone file to local storage (generic Attachments folder)
                let localName = try saveAttachmentToStorage(from: url)
                
                let attachment = ChatAttachment(
                    id: UUID(),
                    filename: filename,
                    fileType: url.pathExtension.isEmpty ? "file" : url.pathExtension,
                    localPath: localName,
                    extractedText: extractedText
                )
                
                let attachmentsData = try JSONEncoder().encode([attachment])
                
                let userMessage = ChatMessage(
                    id: UUID(),
                    sessionId: sessionId,
                    role: .user,
                    content: extractedText,
                    imageData: nil,
                    attachmentsData: attachmentsData,
                    timestamp: Date()
                )
                
                messages.append(userMessage)
                environment.database.addMessage(userMessage)
                
                // Process with Agent
                Task {
                    await LLMRequestQueue.shared.enqueue { [weak self] in
                        guard let self = self else { return }
                        let isLoaded = await MainActor.run { self.environment.gemma.isModelLoaded }
                        if !isLoaded { await self.environment.gemma.loadModel() }
                        
                        await MainActor.run { self.isGenerating = true }
                        
                        // Pass the extracted text to the agent
                        let prompt = "I've attached a file named \(filename). Content:\n\(extractedText)"
                        let result = await self.environment.agent.processText(
                            prompt,
                            sessionId: self.sessionId,
                            history: self.messages.dropLast()
                        )
                        
                        await MainActor.run {
                            self.isGenerating = false
                            self.completeAgentTurn(result)
                        }
                    }
                }
                
                print("🧠 ChatVM: Successfully processed attachment \(filename)")
            } catch {
                print("🧠 ChatVM: Failed to process attachment: \(error)")
                addAssistantMessage("Failed to process attachment: \(error.localizedDescription)")
            }
            
        case .failure(let error):
            print("🧠 ChatVM: File import failed: \(error)")
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

    private func addAssistantMessage(_ text: String) {
        let aiMessage = ChatMessage(
            id: UUID(),
            sessionId: sessionId,
            role: .assistant,
            content: text,
            imageData: nil,
            attachmentsData: nil,
            timestamp: Date()
        )
        messages.append(aiMessage)
        environment.database.addMessage(aiMessage)
    }

    private func completeAgentTurn(_ result: AgentTurnResult) {
        clarificationRequest = result.clarification
        pendingToolCall = result.pendingToolCall
        addAssistantMessage(result.response)

        let ttsEnabled = UserDefaults.standard.bool(forKey: "ttsEnabled")
        if ttsEnabled && !result.response.isEmpty {
            environment.speech.speak(result.response)
        }
    }
    
    private func toolDefinitionPrompt(for request: String) -> String {
        """
        Create a local tool definition for Pelbagai from this user request:
        \(request)
        
        Return ONLY one valid JSON object matching this schema:
        {
          "schemaVersion": 1,
          "toolID": "lowercase_snake_case_identifier",
          "displayName": "Short user-facing name",
          "description": "One sentence describing what the tool extracts or does.",
          "briefing": "When the assistant should use this tool.",
          "index": ["search", "keywords"],
          "rules": ["Domain-specific extraction rule"],
          "prompt": "Tool-specific extraction instruction only. Do not define runtime meta keys here.",
          "inputSchema": { "image": "CIImage" },
          "outputSchema": { "Field Name": "string" },
          "stateSchema": {},
          "capabilities": ["scan_image", "export_csv"],
          "examples": [],
          "chainTo": []
        }
        
        Rules:
        - Use only these capability values: scan_image, export_csv, open_url, persistent_state.
        - Never include executable code, scripts, network authority, filesystem authority, or database authority.
        - Keep prompt focused on visible data extraction. The app runtime appends the JSON/meta-key contract.
        - Use persistent_state only when the user clearly needs cross-scan memory.
        - Use open_url only when the user clearly needs a user-approved link action.
        - Do not invent native plugins or system integrations. Plugins are trusted Swift capabilities registered by the app, not generated local tools.
        - chainTo must only include specific tool IDs this tool is allowed to hand off to.
        - Do not include markdown fences or explanation outside the JSON object.
        """
    }
    
    private func parseToolDefinition(from output: String, request: String) throws -> LocalToolDefinition {
        let json = extractJSONObject(from: output)
        guard let data = json.data(using: .utf8) else {
            throw ToolDefinitionError.invalidJSON
        }
        
        var definition = try JSONDecoder().decode(LocalToolDefinition.self, from: data).normalized()
        if definition.description.isEmpty {
            definition.description = request
        }
        if definition.prompt == nil {
            definition.prompt = "Extract structured data for this task: \(request). Return ONLY valid JSON."
        }
        return definition.normalized()
    }
    
    func applySkill(_ skill: Skill) {
        self.activeSkill = skill
    }
    
    func registerSkill(_ skill: Skill) {
        environment.skills.registerSkill(skill)
    }
    
    private func extractJSONObject(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(text[start...end])
    }
    
    private func processActiveSkillTurn(_ text: String, activeSkill: Skill, history: [ChatMessage]) async -> String {
        let brevityInstruction = "\n\nIMPORTANT: Keep your response extremely brief, direct, and concise (at most 1 or 2 sentences). Do not do too much talking. Focus strictly on getting to the point and displaying the result."
        var systemPrompt = activeSkill.resolvedInstructions + brevityInstruction
        if activeSkill.htmlContent != nil {
            if activeSkill.name == "query-wikipedia" {
                systemPrompt += "\n\nIMPORTANT: You must include a valid JSON block containing the exact, canonical Wikipedia topic/article name to search, e.g., {\"topic\": \"Quantum computing\"} or {\"topic\": \"Albert Einstein\"}. Make sure the JSON block is complete."
            } else {
                systemPrompt += "\n\nIMPORTANT: You must include a valid JSON block containing the result/target text for the interactive view, e.g., {\"text\": \"your_result_here\"} or {\"url\": \"http://example.com\"}. Make sure the JSON block is complete."
            }
        }
        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        
        for msg in history.suffix(8) {
            let content = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            switch msg.role {
            case .user:
                messages.append(["role": "user", "content": content])
            case .assistant:
                messages.append(["role": "model", "content": content])
            case .system:
                continue
            }
        }
        
        messages.append(["role": "user", "content": text])
        
        return await environment.gemma.generateText(
            messages: messages,
            statusText: "Thinking with \(activeSkill.displayName)..."
        )
    }
    
    private func processCanvasTurn(_ text: String, activeSkill: Skill, history: [ChatMessage]) async -> String {
        // 1. Check if we are iterating on an existing canvas
        // Search history backwards for an assistant message with an HTML attachment
        var existingHtml: String? = nil
        for msg in history.reversed() {
            if msg.role == .assistant,
               let attachment = msg.attachments.first(where: { $0.fileType.lowercased() == "html" }) {
                // Read the HTML content from attachments folder
                let fileManager = FileManager.default
                if let documentsURL = try? fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
                    let fileURL = documentsURL.appendingPathComponent("Attachments").appendingPathComponent(attachment.localPath)
                    if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                        existingHtml = content
                        break
                    }
                }
            }
        }
        
        let systemPrompt: String
        if let existing = existingHtml {
            // Build prompt for iteration
            systemPrompt = CanvasPromptBuilder.buildIterationPrompt(request: text, existingHtml: existing)
        } else {
            // Build base system prompt for initial generation
            systemPrompt = CanvasPromptBuilder.buildSystemPrompt()
        }
        
        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        
        // Add chat history (up to last 8 messages) to maintain context
        for msg in history.suffix(8) {
            let content = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            switch msg.role {
            case .user:
                messages.append(["role": "user", "content": content])
            case .assistant:
                // Strip large HTML code blocks from assistant history to save token space and prevent model confusion
                let cleanedContent = cleanResponseText(content)
                messages.append(["role": "model", "content": cleanedContent])
            case .system:
                continue
            }
        }
        
        messages.append(["role": "user", "content": text])
        
        return await environment.gemma.generateText(
            messages: messages,
            statusText: existingHtml != nil ? "Updating Canvas..." : "Building Canvas..."
        )
    }
    
    private func extractHTML(from text: String) -> String? {
        return CanvasParser.extractHTML(from: text)
    }
    
    private func cleanResponseText(_ text: String) -> String {
        return CanvasParser.cleanResponseText(text)
    }
    
    private func detectAndActivateCanvasSkillIfNeeded(text: String, history: [ChatMessage]) {
        // If already in a canvas skill, no need to auto-activate
        if let active = activeSkill, active.capabilities.contains(.canvas) {
            return
        }
        
        let normalized = text.lowercased()
        
        // 1. Initial generation intent keywords
        let generationKeywords = [
            "build me", "build an app", "create an app", "make an app", "design an app",
            "create a calculator", "build a calculator", "make a calculator",
            "create a timer", "build a timer", "make a timer",
            "create a game", "build a game", "make a game",
            "create a pos", "build a pos", "make a pos",
            "generate a canvas", "generate an app", "build a modern app"
        ]
        
        var hasCanvasIntent = generationKeywords.contains { normalized.contains($0) }
        
        // 2. Iteration intent: if there's an existing canvas in the history, and user is asking to modify/add/change/fix it
        if !hasCanvasIntent {
            let hasExistingCanvas = history.contains { msg in
                msg.role == .assistant && msg.attachments.contains { $0.fileType.lowercased() == "html" && $0.extractedText == "[AI Canvas Micro-App]" }
            }
            if hasExistingCanvas {
                let iterationKeywords = [
                    "add", "change", "fix", "update", "modify", "remove", "button", "reset", "style", "color", "layout", "mode", "toggle", "increase", "decrease"
                ]
                hasCanvasIntent = iterationKeywords.contains { normalized.contains($0) } || normalized.count < 60
            }
        }
        
        if hasCanvasIntent {
            if let canvasSkill = environment.skills.skill(byID: "canvas-app-builder") {
                print("🎨 [ChatVM] Auto-activating Canvas App Builder skill")
                self.activeSkill = canvasSkill
            }
        }
    }
    
    func importSkill(from url: URL) {
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let fallbackName = url.deletingPathExtension().lastPathComponent
            if let skill = Skill.parse(from: markdown, fallbackName: fallbackName) {
                applySkill(skill)
                registerSkill(skill)
                self.addAssistantMessage("Successfully imported skill \"\(skill.displayName)\" and activated it.")
            } else {
                self.addAssistantMessage("Failed to parse the SKILL.md file. Ensure it contains correct frontmatter.")
            }
        } catch {
            self.addAssistantMessage("Failed to read the imported file: \(error.localizedDescription)")
        }
    }
    
    func deleteCustomSkill(named name: String) {
        if activeSkill?.name == name {
            activeSkill = nil
        }
        environment.skills.removeUserSkill(named: name)
    }
    
    func saveHtmlSnapshot(for messageId: UUID, html: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        let msg = messages[index]
        
        do {
            if let existingHtmlAttachment = msg.attachments.first(where: { $0.fileType.lowercased() == "html" }) {
                // Update the existing HTML file on disk directly
                _ = try saveHTMLAttachmentToStorage(htmlContent: html, filename: existingHtmlAttachment.localPath)
                print("💾 [ChatVM] Updated existing HTML snapshot: \(existingHtmlAttachment.localPath)")
            } else {
                // Create a new HTML attachment
                let uniqueName = try saveHTMLAttachmentToStorage(htmlContent: html)
                let attachment = ChatAttachment(
                    id: UUID(),
                    filename: "Skill_Snapshot.html",
                    fileType: "html",
                    localPath: uniqueName,
                    extractedText: "[HTML Snapshot of Skill Output]"
                )
                var currentAttachments = msg.attachments
                currentAttachments.append(attachment)
                let attachmentsData = try JSONEncoder().encode(currentAttachments)
                
                let updatedMsg = ChatMessage(
                    id: msg.id,
                    sessionId: msg.sessionId,
                    role: msg.role,
                    content: msg.content,
                    imageData: msg.imageData,
                    attachmentsData: attachmentsData,
                    timestamp: msg.timestamp
                )
                
                messages[index] = updatedMsg
                environment.database.updateMessageAttachments(id: msg.id, attachmentsData: attachmentsData)
                print("💾 [ChatVM] Saved new HTML snapshot: \(uniqueName)")
            }
        } catch {
            print("⚠️ [ChatVM] Failed to save/update HTML snapshot: \(error)")
        }
    }
    
    func updateMessageImageData(for messageId: UUID, imageData: Data) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        let msg = messages[index]
        
        let updatedMsg = ChatMessage(
            id: msg.id,
            sessionId: msg.sessionId,
            role: msg.role,
            content: msg.content,
            imageData: imageData,
            attachmentsData: msg.attachmentsData,
            timestamp: msg.timestamp
        )
        
        messages[index] = updatedMsg
        environment.database.updateMessageImageData(id: msg.id, imageData: imageData)
        print("💾 [ChatVM] Saved image data for message: \(msg.id)")
    }
    
    private func saveHTMLAttachmentToStorage(htmlContent: String, filename: String? = nil) throws -> String {
        let fileManager = FileManager.default
        let documentsURL = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let attachmentsDirectory = documentsURL.appendingPathComponent("Attachments", isDirectory: true)
        
        if !fileManager.fileExists(atPath: attachmentsDirectory.path) {
            try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        }
        
        let uniqueName = filename ?? "\(UUID().uuidString).html"
        let destinationURL = attachmentsDirectory.appendingPathComponent(uniqueName)
        
        try htmlContent.write(to: destinationURL, atomically: true, encoding: .utf8)
        return uniqueName
    }
}

private enum ToolDefinitionError: LocalizedError {
    case invalidJSON
    
    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "The model did not return a valid JSON object."
        }
    }
}

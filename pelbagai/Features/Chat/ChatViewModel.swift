import SwiftUI
import Combine
import AVFAudio

#if canImport(UIKit)
import UIKit
#else
import AppKit
fileprivate typealias UIImage = NSImage
#endif

@MainActor
class ChatViewModel: ObservableObject {
    let sessionId: UUID
    private let environment: AppEnvironment
    
    @Published var messages: [ChatMessage] = []
    @Published var textInput: String = ""
    @Published var inputMode: ChatInputMode = .chat
    @Published var isRecording = false
    @Published var speechBuffer: [Float] = []
    @Published var showCamera = false
    @Published var capturedImage: UIImage?
    
    // Model state mirroring from managers for easier View binding
    @Published var isLoadingModels = false
    @Published var loadingStatusText = ""
    @Published var isGenerating = false
    @Published var response = ""
    @Published var status = ""
    @Published var isModelLoaded = false
    @Published var userDefinitionsCount = 0
    @Published var clarificationRequest: ClarificationRequest?
    
    private let audioService = AudioService()
    private var cancellables = Set<AnyCancellable>()
    private var activeTask: Task<Void, Never>?
    
    deinit {
        activeTask?.cancel()
    }
    
    init(sessionId: UUID, environment: AppEnvironment) {
        self.sessionId = sessionId
        self.environment = environment
        
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
        await environment.gemma.loadModel()
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
        let userMessage = ChatMessage(id: UUID(), sessionId: sessionId, role: .user, content: "[Audio Message]", imageData: nil, timestamp: Date())
        messages.append(userMessage)
        environment.database.addMessage(userMessage)
        
        activeTask?.cancel()
        activeTask = Task {
            if !environment.gemma.isModelLoaded {
                await environment.gemma.loadModel()
            }
            
            let prompt = "Listen to this audio and respond naturally."
            messages.append(ChatMessage(id: UUID(), sessionId: sessionId, role: .user, content: "[Audio Input]", imageData: nil, timestamp: Date()))
            
            await environment.gemma.generate(prompt: prompt, audio: audio, history: conversationContext)
            
            completeGeneration()
        }
    }
    
    func sendImageMessage(_ image: UIImage) {
        let conversationContext = messages
        let imageData = ImageInputPreparer.data(from: image)
        
        let userMessage = ChatMessage(
            id: UUID(),
            sessionId: sessionId,
            role: .user,
            content: "[Image Message]",
            imageData: imageData,
            timestamp: Date()
        )
        messages.append(userMessage)
        environment.database.addMessage(userMessage)
        
        activeTask?.cancel()
        activeTask = Task {
            if !environment.gemma.isModelLoaded {
                await environment.gemma.loadModel()
            }
            
            let prompt = "Please describe this image."
            await environment.gemma.generate(prompt: prompt, image: image, history: conversationContext)
            
            completeGeneration()
        }
    }
    
    func sendTypedMessage() {
        let text = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let userMessage = ChatMessage(id: UUID(), sessionId: sessionId, role: .user, content: text, imageData: nil, timestamp: Date())
        messages.append(userMessage)
        environment.database.addMessage(userMessage)
        
        updateSessionTitleIfNeeded(with: text)
        
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self = self else { return }
            if !self.environment.gemma.isModelLoaded {
                await self.environment.gemma.loadModel()
            }
            
            await self.environment.gemma.generate(prompt: text, history: conversationContext)
            self.completeGeneration()
        }
    }
    
    private func updateSessionTitleIfNeeded(with text: String) {
        if messages.count == 1 {
            let title = String(text.prefix(30)) + (text.count > 30 ? "..." : "")
            environment.database.updateSessionTitle(id: sessionId, newTitle: title)
            NotificationCenter.default.post(name: .sessionUpdated, object: nil)
        }
    }
    
    private func completeGeneration() {
        let responseText = environment.gemma.response
        let aiMessage = ChatMessage(
            id: UUID(),
            sessionId: sessionId,
            role: .assistant,
            content: responseText,
            imageData: nil,
            timestamp: Date()
        )
        messages.append(aiMessage)
        environment.database.addMessage(aiMessage)
        
        let ttsEnabled = UserDefaults.standard.bool(forKey: "ttsEnabled")
        if ttsEnabled && !responseText.isEmpty {
            environment.speech.speak(responseText)
        }
    }
    
    func handleClarificationChoice(_ choice: String) {
        clarificationRequest = nil
        sendMessage(choice)
    }
    
    // Tool Definition Logic
    func sendToolDefinitionRequest(_ request: String) {
        let userMessage = ChatMessage(
            id: UUID(),
            sessionId: sessionId,
            role: .user,
            content: "Create local tool: \(request)",
            imageData: nil,
            timestamp: Date()
        )
        messages.append(userMessage)
        environment.database.addMessage(userMessage)
        
        updateSessionTitleIfNeeded(with: request)
        
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self = self else { return }
            if !self.environment.gemma.isModelLoaded {
                await self.environment.gemma.loadModel()
            }
            
            await self.environment.gemma.generate(prompt: self.toolDefinitionPrompt(for: request), history: [])
            let rawResponse = self.environment.gemma.response
            
            do {
                let definition = try self.parseToolDefinition(from: rawResponse, request: request)
                self.environment.registry.upsert(definition)
                
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
    
    private func addAssistantMessage(_ text: String) {
        let aiMessage = ChatMessage(
            id: UUID(),
            sessionId: sessionId,
            role: .assistant,
            content: text,
            imageData: nil,
            timestamp: Date()
        )
        messages.append(aiMessage)
        environment.database.addMessage(aiMessage)
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
    
    private func extractJSONObject(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(text[start...end])
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

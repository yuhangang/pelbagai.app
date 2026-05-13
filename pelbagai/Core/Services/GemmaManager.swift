import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import Combine
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM
import Hub

nonisolated enum GemmaModel: String, CaseIterable, Identifiable {
    case e2b = "E2B"
    case e4b = "E4B"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .e2b: return "Gemma 4 E2B"
        case .e4b: return "Gemma 4 E4B"
        }
    }
    
    var modelID: String {
        switch self {
        case .e2b: return "mlx-community/gemma-4-e2b-it-4bit"
        case .e4b: return "mlx-community/gemma-4-e4b-it-4bit"
        }
    }
    
    var isDownloaded: Bool {
        let repo = HubApi.Repo(id: modelID)
        let localURL = HubApi().localRepoLocation(repo)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isDir) {
            if isDir.boolValue {
                if let files = try? FileManager.default.contentsOfDirectory(atPath: localURL.path), !files.isEmpty {
                    return true
                }
            }
        }
        return false
    }
    
    var isSupported: Bool {
        switch self {
        case .e2b:
            return true
        case .e4b:
            // E4B requires at least 12GB RAM (using 10.5GB GiB threshold to account for decimal vs binary reporting)
            return MemoryStats.totalMemoryGB >= 10.5
        }
    }
    
    static var availableModels: [GemmaModel] {
        allCases.filter { $0.isSupported }
    }
}

nonisolated struct GemmaToolCall: Decodable, Hashable {
    let name: String
    let args: [String: String]?
}

struct ClarificationRequest: Codable, Hashable {
    let question: String
    let options: [String]?
}

private enum GemmaInputError: LocalizedError {
    case failedToPrepareImage

    var errorDescription: String? {
        switch self {
        case .failedToPrepareImage:
            return "Failed to prepare the selected image for the model."
        }
    }
}

/// Manages the on-device Gemma models via MLX Swift.
/// Handles model loading, prompt construction, and streaming token generation.
@MainActor
class GemmaManager: ObservableObject {
    static let shared = GemmaManager()
    
    @Published var response: String = ""
    @Published var clarificationRequest: ClarificationRequest?
    
    @Published private(set) var selectedModel: GemmaModel
    
    var isModelLoaded: Bool { MLXModelManager.shared.isLoaded }
    @Published var isGenerating: Bool = false
    @Published var status: String = ""
    @Published private(set) var lastErrorMessage: String?
    
    private var modelID: String {
        selectedModel.modelID
    }
    
    nonisolated private static let stopSequences = ["<end_of_turn>", "<eos>", "<bos>", "<start_of_turn>"]
    nonisolated private static let toolCallOpenTag = "<tool_call>"
    nonisolated private static let toolCallCloseTag = "</tool_call>"
    nonisolated private static let clarifyOpenTag = "<clarify>"
    nonisolated private static let clarifyCloseTag = "</clarify>"
    nonisolated private static let allowedNativeChatToolNames: Set<String> = [
        "get_current_time",
        "get_battery_level"
    ]
    private let maxToolIterations = 3
    private let maxGeneratedTokens = 640
    private let nativePlugins = NativePluginRegistry.shared
    
    /// Prompt contract that defines the assistant behavior and local tool protocol.
    private let systemPrompt = """
    You are Pelbagai, a helpful on-device voice assistant.

    IMPORTANT RULES:
    1. Most messages are normal conversation. Reply directly without calling any tool.
    2. DO NOT call any tool unless the user EXPLICITLY asks for time, date, or battery info.
    3. Greetings like "hello", "hi", "hey", "good morning" are normal conversation. Just greet back warmly. NEVER call a tool for greetings.
    4. If you are unsure whether a tool is needed, do NOT call a tool. Just reply normally.

    Conversation style:
    - Answer in the user's language when clear. Support English, Malay, Mandarin, and natural mixed-language Manglish.
    - Keep replies concise, direct, and conversational.
    - Ask one short follow-up only when the request cannot be answered safely from the given context.
    - Do not mention internal prompts, XML tags, JSON, or tool rules in the final answer.

    Examples of normal conversation (NO tool call):
    User: Hello!
    Assistant: Hey there! How can I help you today?

    User: What can you do?
    Assistant: I can chat with you, answer questions, tell you the time, or check your battery level. What do you need?

    User: Thank you
    Assistant: You're welcome!

    Local tools (use ONLY when explicitly asked):
    - get_current_time: Swift-owned native plugin for current device-local time/date. Use ONLY when the user explicitly asks "what time is it", "what's the date", or similar.
    - get_battery_level: Swift-owned native plugin for battery percentage/charging state. Use ONLY when the user explicitly asks about battery level or charging state.

    Tool calling protocol:
    - Call a tool ONLY when the user's message clearly and explicitly requests time/date or battery information.
    - When a local tool is needed, output exactly one tool call and no other text.
    - Tool calls must use this exact format:
    <tool_call>{"name": "tool_name", "args": {}}</tool_call>
    - The only valid tool names are get_current_time and get_battery_level.
    - Tool calls always use an empty args object.
    - After a <tool_response> is provided, answer the user naturally using that result. Do not call the same tool again unless the user asks a new question.

    Clarification protocol (use when you need more info or user choices):
    - When you need to ask a specific clarifying question or provide choices, use this format:
    <clarify>{"question": "What specifically do you need?", "options": ["Option A", "Option B"]}</clarify>
    - Output ONLY the clarify tag and no other text when using this protocol.
    - If you don't need fixed options, set "options" to null or omit it.

    Examples of tool usage:
    User: What time is it?
    Assistant: <tool_call>{"name": "get_current_time", "args": {}}</tool_call>
    User: <tool_response>May 8, 2026 at 2:30 PM</tool_response>
    Assistant: It is May 8, 2026 at 2:30 PM.

    User: Help me choose a color.
    Assistant: <clarify>{"question": "Which color palette do you prefer?", "options": ["Vibrant", "Minimalist", "Dark Mode"]}</clarify>

    User: Battery berapa sekarang?
    Assistant: <tool_call>{"name": "get_battery_level", "args": {}}</tool_call>
    """

    private let systemAck = "Understood. I will reply conversationally to most messages and only call a tool when explicitly asked for time or battery info."
    
    private init() {
        let model: GemmaModel
        if let saved = UserDefaults.standard.string(forKey: "selectedGemmaModel"),
           let savedModel = GemmaModel(rawValue: saved),
           savedModel.isSupported {
            model = savedModel
        } else {
            model = .e2b
        }
        self.selectedModel = model
        
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        #endif
        
        Task { @MainActor in
            if model.isDownloaded {
                print("🧠 [GemmaManager] Model \(model.displayName) is already downloaded. Auto-initializing...")
                await self.loadModel()
            } else {
                print("🧠 [GemmaManager] Model \(model.displayName) is not downloaded. Skipping auto-initialization.")
            }
        }
    }
    
    /// Switches to a new model, unloading the current one if necessary.
    func switchModel(to model: GemmaModel) async {
        guard model.isSupported else { return }
        guard model != selectedModel else { return }
        guard !isGenerating else { return }
        
        print("🧠 Switching Gemma model to: \(model.displayName)")
        
        let previousModel = selectedModel
        let previouslyLoadedModelID = MLXModelManager.shared.currentModelID
        
        do {
            try await load(model: model)
            commitSelectedModel(model)
        } catch {
            print("🧠 Failed to switch Gemma model to \(model.displayName): \(error)")
            
            if previouslyLoadedModelID == previousModel.modelID {
                do {
                    try await load(model: previousModel)
                    commitSelectedModel(previousModel)
                } catch {
                    print("🧠 Failed to restore previous Gemma model \(previousModel.displayName): \(error)")
                }
            }
        }
    }
    
    // MARK: - Local Tools
    
    private func executeTool(_ toolCall: GemmaToolCall) async -> String {
        do {
            print("🧠 Executing native plugin chat tool: \(toolCall.name)")
            let result = try await nativePlugins.executeChatTool(
                name: toolCall.name,
                arguments: toolCall.args ?? [:]
            )
            return result.summary
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private func explicitLocalToolRequest(for prompt: String) -> GemmaToolCall? {
        let normalized = prompt
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }

        let asksForBattery = [
            "battery",
            "bateri",
            "charging",
            "charge level",
            "battery level"
        ].contains { normalized.contains($0) }

        if asksForBattery {
            return GemmaToolCall(name: "get_battery_level", args: [:])
        }

        let asksForTimeOrDate = [
            "what time",
            "what's the time",
            "current time",
            "time now",
            "date today",
            "today's date",
            "what date",
            "hari ini",
            "pukul berapa",
            "jam berapa"
        ].contains { normalized.contains($0) }

        if asksForTimeOrDate {
            return GemmaToolCall(name: "get_current_time", args: [:])
        }

        return nil
    }

    private func finalAnswer(for toolCall: GemmaToolCall, result: String) -> String {
        switch toolCall.name {
        case "get_current_time":
            return "It is \(result)."
        case "get_battery_level":
            return result
        default:
            return result
        }
    }

    private func commitSelectedModel(_ model: GemmaModel) {
        guard selectedModel != model else { return }
        selectedModel = model
        UserDefaults.standard.set(model.rawValue, forKey: "selectedGemmaModel")
    }

    private func load(model: GemmaModel) async throws {
        try await MLXModelManager.shared.loadModel(modelID: model.modelID)
    }
    
    // MARK: - Model Lifecycle
    
    /// Loads the Gemma model via MLXModelManager.
    @discardableResult
    func loadModel() async -> Bool {
        guard !isGenerating else { return false }
        
        do {
            try await load(model: selectedModel)
            lastErrorMessage = nil
            return true
        } catch {
            print("🧠 Failed to load Gemma model: \(error)")
            lastErrorMessage = error.localizedDescription
            status = "Load failed: \(error.localizedDescription)"
            return false
        }
    }
    
    /// Releases the resident LLM weights.
    func unloadModel() async {
        guard !isGenerating else { 
            print("🧠 [GemmaManager] Cannot unload while generating")
            return 
        }
        print("🧠 [GemmaManager] Unloading resident model")
        await MLXModelManager.shared.unloadModel()
        response = ""
        status = ""
    }
    
    // MARK: - Text Generation
    
    /// Generates a response from the transcribed user input, raw audio, or image.
    /// Streams tokens into `self.response` for real-time UI updates.
    func generate(prompt: String, image: UIImage? = nil, audio: [Float]? = nil, history: [ChatMessage] = []) async {
        guard !isGenerating else { return }
        
        isGenerating = true
        response = ""
        clarificationRequest = nil
        lastErrorMessage = nil
        status = ""
        defer {
            if image != nil {
                Gemma4Processor.setRuntimeImageSoftTokenCap(32)
            }
            status = ""
            isGenerating = false
            MLXModelManager.shared.clearCache()
        }
        
        print("🧠 Generating response for: \(prompt)")
        
        do {
            if audio == nil, image == nil, let toolCall = explicitLocalToolRequest(for: prompt) {
                status = "Using \(nativePlugins.chatTool(named: toolCall.name)?.displayName ?? toolCall.name)..."
                let toolResult = await executeTool(toolCall)
                response = finalAnswer(for: toolCall, result: toolResult)
                print("🧠 Handled local tool without model generation: \(toolCall.name)")
                return
            }

            guard let container = MLXModelManager.shared.container else {
                print("🧠 Model not loaded yet")
                response = "Model is not loaded yet."
                return
            }

            var messages = buildMessages(prompt: prompt, history: history)
            var executedToolCalls: Set<GemmaToolCall> = []
            var iterationCount = 0
            var didRetryEmptyImageOutput = false
            var imageSoftTokenRetryCap: Int?
            let maxTokens = maxGeneratedTokens
            let isCPU = MLXModelManager.shared.preferredBackend == .cpu
            let prefillStepSize = isCPU ? 32 : 128
            let device: Device = isCPU ? .cpu : .gpu
            
            while executedToolCalls.count < maxToolIterations {
                if Task.isCancelled { break }
                iterationCount += 1
                print("🧠 Generation iteration \(iterationCount)")
                
                let currentMessages = messages
                let currentIteration = iterationCount
                let currentImageSoftTokenRetryCap = imageSoftTokenRetryCap
                let shouldUseMultimodalInput = (audio != nil || image != nil)
                    && (currentIteration == 1 || currentImageSoftTokenRetryCap != nil)
                let rawOutput = try await container.perform { context in
                    let input: MLXLMCommon.LMInput
                    
                    // If we have audio or image and it's the first iteration, build a
                    // structured chat turn so MLXLMCommon collects media into
                    // `input.images` / `input.audio` for the model-specific processor.
                    if shouldUseMultimodalInput {
                        var images: [UserInput.Image] = []
                        var audioInputs: [UserInput.Audio] = []
                        var finalPrompt = currentImageSoftTokenRetryCap == nil
                            ? prompt
                            : "Describe the visible content of this image in one concise paragraph. Do not answer with an empty response."
                        
                        if let img = image {
                            guard let ciImage = ImageInputPreparer.ciImage(from: img) else {
                                throw GemmaInputError.failedToPrepareImage
                            }
                            images.append(.ciImage(ciImage))
                        }
                        
                        if let audioSamples = audio {
                            // Prepend the audio token to the prompt if not already present
                            if !finalPrompt.contains("<|audio|>") {
                                finalPrompt = "<|audio|>\n" + finalPrompt
                            }
                            let audioData = audioSamples.withUnsafeBufferPointer { buffer in
                                Data(buffer: buffer)
                            }
                            audioInputs.append(.data(audioData, format: "audio/pcm-f32"))
                        }

                        let userInput = UserInput(
                            chat: [
                                .user(finalPrompt, images: images, audio: audioInputs)
                            ]
                        )
                        print("🧠 Prepared multimodal input - images: \(images.count), audio: \(audio != nil)")

                        input = try await context.processor.prepare(input: userInput)
                    } else {
                        input = try await context.processor.prepare(
                            input: .init(messages: currentMessages)
                        )
                    }
                    
                    print("🧠 [GemmaManager] Starting MLXLMCommon.generate on \(device)...")
                    let result = try MLXLMCommon.generate(
                        input: input,
                        parameters: GenerateParameters(temperature: 0.25, prefillStepSize: prefillStepSize),
                        context: context
                    ) { tokens in
                        if Task.isCancelled || !MLXModelManager.shared.isForegroundGPUAllowed() { return .stop }
                        if tokens.count >= maxTokens { return .stop }
                        
                        if tokens.count % 32 == 0 {
                            if MemoryStats.headroomMB < 200 {
                                Task { @MainActor in
                                    self.response += "\n\n> ⚠️ Stopped due to low memory. Please close background apps."
                                }
                                return .stop
                            }
                        }
                        
                        let text = context.tokenizer.decode(tokenIds: tokens)
                        let cleanedText = Self.cleanModelOutput(text)
                        let visibleText = Self.visibleOutput(from: cleanedText)
                        
                        for stopSeq in Self.stopSequences {
                            if text.contains(stopSeq) {
                                Task { @MainActor in self.response = visibleText }
                                return .stop
                            }
                        }
                        
                        Task { @MainActor in
                            if Self.hasPartialToolCall(in: cleanedText) {
                                self.status = "Checking local context..."
                            } else if Self.hasPartialClarify(in: cleanedText) {
                                self.status = "Structuring clarification..."
                            }
                            self.response = visibleText
                        }
                        return .more
                    }
                    if result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        print(
                            "🧠 [GemmaManager] Empty generation output. "
                                + "generatedTokenCount=\(result.generationTokenCount), "
                                + "promptTokenCount=\(result.promptTokenCount)"
                        )
                    }
                    return result.output
                }
                
                let output = Self.cleanModelOutput(rawOutput)
                print("🧠 Model output: \(output)")
                if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   image != nil,
                   audio == nil,
                   !didRetryEmptyImageOutput {
                    didRetryEmptyImageOutput = true
                    imageSoftTokenRetryCap = 64
                    Gemma4Processor.setRuntimeImageSoftTokenCap(64)
                    MLXModelManager.shared.clearCache()
                    print("🧠 Empty image output; retrying once with image softTokens=64")
                    continue
                }
                
                if let toolCall = Self.parseToolCall(from: output),
                   !executedToolCalls.contains(toolCall) {
                    executedToolCalls.insert(toolCall)
                    
                    // UI Updates
                    self.status = "Using \(nativePlugins.chatTool(named: toolCall.name)?.displayName ?? toolCall.name)..."
                    self.response = ""
                    
                    print("🧠 Tool call detected: \(toolCall.name)")
                    let toolResult = await executeTool(toolCall)

                    self.response = finalAnswer(for: toolCall, result: toolResult)
                    print("🧠 Completed local tool without follow-up model generation")
                    break
                }
                
                if let clarify = Self.parseClarify(from: output) {
                    self.clarificationRequest = clarify
                    self.response = clarify.question
                    print("🧠 Clarification requested: \(clarify.question)")
                    break
                }
                
                self.response = Self.visibleOutput(from: output).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
            
            if response.isEmpty {
                response = "I could not finish that request cleanly. Please try again."
            }
            
            print("🧠 Generation complete")
            
        } catch {
            print("🧠 Generation error: \(error)")
            lastErrorMessage = error.localizedDescription
            self.response = "I hit a local model error: \(error.localizedDescription)"
        }
    }

    /// Generates text from fully prepared chat messages. Agent orchestration,
    /// tool routing, and memory injection live outside this manager.
    func generateText(messages: [[String: String]], statusText: String = "Thinking...") async -> String {
        guard !isGenerating else { return "" }

        isGenerating = true
        response = ""
        clarificationRequest = nil
        lastErrorMessage = nil
        status = statusText
        defer {
            status = ""
            isGenerating = false
            MLXModelManager.shared.clearCache()
        }

        guard let container = MLXModelManager.shared.container else {
            response = "Model is not loaded yet."
            lastErrorMessage = response
            return response
        }

        let maxTokens = maxGeneratedTokens
        let isCPU = MLXModelManager.shared.preferredBackend == .cpu
        let prefillStepSize = isCPU ? 32 : 128
        let device: Device = isCPU ? .cpu : .gpu

        do {
            let rawOutput = try await container.perform { context in
                print("🧠 [GemmaManager] Starting MLXLMCommon.generate (text-only) on \(device)...")
                let input = try await context.processor.prepare(
                    input: .init(messages: messages)
                )
                
                let result = try MLXLMCommon.generate(
                    input: input,
                    parameters: GenerateParameters(temperature: 0.25, prefillStepSize: prefillStepSize),
                    context: context
                ) { tokens in
                    if Task.isCancelled || !MLXModelManager.shared.isForegroundGPUAllowed() { return .stop }
                    if tokens.count >= maxTokens { return .stop }

                    if tokens.count % 32 == 0, MemoryStats.headroomMB < 200 {
                        Task { @MainActor in
                            self.response += "\n\n> ⚠️ Stopped due to low memory. Please close background apps."
                        }
                        return .stop
                    }

                    let text = context.tokenizer.decode(tokenIds: tokens)
                    let cleanedText = Self.cleanModelOutput(text)
                    let visibleText = Self.visibleOutput(from: cleanedText)

                    for stopSeq in Self.stopSequences where text.contains(stopSeq) {
                        Task { @MainActor in self.response = visibleText }
                        return .stop
                    }

                    Task { @MainActor in
                        if Self.hasPartialToolCall(in: cleanedText) {
                            self.status = "Checking local context..."
                        } else if Self.hasPartialClarify(in: cleanedText) {
                            self.status = "Structuring clarification..."
                        }
                        self.response = visibleText
                    }
                    return .more
                }
                return result.output
            }

            let cleaned = Self.cleanModelOutput(rawOutput)
            response = Self.visibleOutput(from: cleaned)
            return cleaned
        } catch {
            print("🧠 Generation error: \(error)")
            lastErrorMessage = error.localizedDescription
            response = "I hit a local model error: \(error.localizedDescription)"
            return response
        }
    }

    
    private func buildMessages(prompt: String, history: [ChatMessage]) -> [[String: String]] {
        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "assistant", "content": systemAck]
        ]
        
        let recentHistory = history.suffix(8)
        for message in recentHistory {
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            
            switch message.role {
            case .user:
                messages.append(["role": "user", "content": content])
            case .assistant:
                messages.append(["role": "assistant", "content": content])
            case .system:
                continue
            }
        }
        
        messages.append(["role": "user", "content": prompt])
        return messages
    }
    
    nonisolated private static func cleanModelOutput(_ output: String) -> String {
        var cleaned = output
        for stopSeq in stopSequences {
            cleaned = cleaned.replacingOccurrences(of: stopSeq, with: "")
        }
        
        // Strip markdown code blocks if present
        if cleaned.contains("```") {
            let lines = cleaned.components(separatedBy: .newlines)
            let filtered = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            cleaned = filtered.joined(separator: "\n")
        }
        
        while cleaned.first?.isWhitespace == true {
            cleaned.removeFirst()
        }
        return cleaned
    }
    
    nonisolated private static func visibleOutput(from output: String) -> String {
        var visible = output
        
        // Remove complete tool calls
        if visible.contains(toolCallCloseTag) {
            visible = visible.replacingOccurrences(of: toolCallPattern, with: "", options: .regularExpression)
        }
        // Remove partial tool calls
        if let range = visible.range(of: toolCallOpenTag) {
            visible = String(visible[..<range.lowerBound])
        }
        
        // Remove complete clarify tags
        if visible.contains(clarifyCloseTag) {
            visible = visible.replacingOccurrences(of: clarifyPattern, with: "", options: .regularExpression)
        }
        // Remove partial clarify tags
        if let range = visible.range(of: clarifyOpenTag) {
            visible = String(visible[..<range.lowerBound])
        }
        
        // Preserve trailing whitespace during streaming for smooth UI
        while visible.first?.isWhitespace == true {
            visible.removeFirst()
        }
        
        return visible
    }
    
    nonisolated private static var toolCallPattern: String {
        "\(NSRegularExpression.escapedPattern(for: toolCallOpenTag)).*?\(NSRegularExpression.escapedPattern(for: toolCallCloseTag))"
    }

    nonisolated private static var clarifyPattern: String {
        "\(NSRegularExpression.escapedPattern(for: clarifyOpenTag)).*?\(NSRegularExpression.escapedPattern(for: clarifyCloseTag))"
    }
    
    nonisolated private static func hasPartialToolCall(in output: String) -> Bool {
        output.contains(toolCallOpenTag) && !output.contains(toolCallCloseTag)
    }

    nonisolated private static func hasPartialClarify(in output: String) -> Bool {
        output.contains(clarifyOpenTag) && !output.contains(clarifyCloseTag)
    }
    
    nonisolated private static func parseToolCall(from output: String) -> GemmaToolCall? {
        guard let startRange = output.range(of: toolCallOpenTag),
              let endRange = output.range(of: toolCallCloseTag, range: startRange.upperBound..<output.endIndex) else {
            return nil
        }
        
        let jsonString = String(output[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = jsonString.data(using: .utf8),
              let toolCall = try? JSONDecoder().decode(GemmaToolCall.self, from: data),
              allowedNativeChatToolNames.contains(toolCall.name) else {
            return nil
        }
        
        return toolCall
    }

    nonisolated private static func parseClarify(from output: String) -> ClarificationRequest? {
        guard let startRange = output.range(of: clarifyOpenTag),
              let endRange = output.range(of: clarifyCloseTag, range: startRange.upperBound..<output.endIndex) else {
            return nil
        }
        
        let jsonString = String(output[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = jsonString.data(using: .utf8),
              let clarify = try? JSONDecoder().decode(ClarificationRequest.self, from: data) else {
            return nil
        }
        
        return clarify
    }
    
    nonisolated private static func toolCallMarkup(for toolCall: GemmaToolCall) -> String {
        let args = toolCall.args ?? [:]
        let payload: [String: Any] = ["name": toolCall.name, "args": args]
        
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return "\(toolCallOpenTag){\"name\":\"\(toolCall.name)\",\"args\":{}}\(toolCallCloseTag)"
        }
        
        return "\(toolCallOpenTag)\(json)\(toolCallCloseTag)"
    }
    
    // MARK: - Tool Output Generation
    
    /// Generates structured output for a tool from text input.
    /// Uses the tool's prompt and output schema to guide the LLM.
    func generateToolOutput(
        text: String,
        definition: LocalToolDefinition,
        history: [ChatMessage] = [],
        stateOverride: [String: String]? = nil
    ) async {
        guard !isGenerating else { return }
        
        isGenerating = true
        response = ""
        status = "Processing with \(definition.displayName)..."
        defer {
            status = ""
            isGenerating = false
            MLXModelManager.shared.clearCache()
        }
        
        guard let container = MLXModelManager.shared.container else {
            response = "Model is not loaded yet."
            return
        }
        
        // Build a focused prompt for structured extraction from text
        var toolPrompt = definition.prompt ?? "Extract structured data. Return ONLY valid JSON."
        if let briefing = definition.briefing {
            toolPrompt = "BRIEFING: \(briefing)\n\n\(toolPrompt)"
        }
        
        if let rules = definition.rules, !rules.isEmpty {
            let rulesText = rules.map { "- \($0)" }.joined(separator: "\n")
            toolPrompt += "\n\nADDITIONAL RULES:\n\(rulesText)"
        }
        
        if let examples = definition.examples, !examples.isEmpty {
            let examplesText = examples.enumerated().map { index, example in
                let fields = example
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key): \($0.value.flatString)" }
                    .joined(separator: "\n")
                return "Example \(index + 1):\n\(fields)"
            }.joined(separator: "\n\n")
            toolPrompt += "\n\nFEW-SHOT EXAMPLES:\n\(examplesText)"
        }
        
        let schemaHint: String
        if definition.outputSchema.isEmpty {
            schemaHint = "Choose clear user-facing field names."
        } else {
            schemaHint = "Output fields: " + definition.outputSchema.keys.sorted().joined(separator: ", ")
        }
        
        var stateContext = ""
        let shouldInjectState = definition.capabilities.contains(.persistentState) || stateOverride != nil
        if shouldInjectState {
            let state = stateOverride ?? ToolStorage.shared.latestState(for: definition.toolID)
            if !state.isEmpty,
               let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8) {
                stateContext = "\nCURRENT TOOL STATE (Context from previous messages):\n\(json)\n"
            }
        }
        
        let instructionPrompt = """
        \(toolPrompt)
        
        \(schemaHint)
        \(stateContext)
        """
        
        var messages: [[String: String]] = [
            ["role": "system", "content": "You are a structured data extraction assistant. Return ONLY valid JSON matching the requested schema. No markdown, no explanation.\n\nINSTRUCTIONS:\n\(instructionPrompt)"]
        ]
        
        // Add conversational context if provided
        for msg in history.suffix(6) {
            messages.append(["role": msg.role.rawValue, "content": msg.content])
        }
        
        // Current request
        messages.append(["role": "user", "content": text])
        
        let maxTokens = maxGeneratedTokens
        
        do {
            let rawOutput = try await container.perform { context in
                let input = try await context.processor.prepare(
                    input: .init(messages: messages)
                )
                let result = try MLXLMCommon.generate(
                    input: input,
                    parameters: GenerateParameters(temperature: 0.15, prefillStepSize: 128),
                    context: context
                ) { tokens in
                    if Task.isCancelled || !MLXModelManager.shared.isForegroundGPUAllowed() { return .stop }
                    if tokens.count >= maxTokens { return .stop }
                    
                    if tokens.count % 32 == 0 {
                        if MemoryStats.headroomMB < 200 {
                            Task { @MainActor in
                                self.response = "{\"error\": \"Low memory, extraction stopped.\"}"
                            }
                            return .stop
                        }
                    }
                    let decoded = context.tokenizer.decode(tokenIds: tokens)
                    if decoded.contains("</s>") || decoded.contains("<end_of_turn>") || decoded.contains("<eos>") {
                        return .stop
                    }
                    return .more
                }
                return result.output
            }
            
            self.response = Self.cleanModelOutput(rawOutput)
            print("🛠 Tool output: \(response)")
        } catch {
            self.response = "Error: \(error.localizedDescription)"
        }
    }
}

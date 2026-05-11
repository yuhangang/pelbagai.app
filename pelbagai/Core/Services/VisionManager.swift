import Foundation
import SwiftUI
import Combine
import MLX
import MLXLMCommon
import MLXVLM

#if canImport(UIKit)
import UIKit
#endif

/// Manages on-device vision inference using Gemma 4's multimodal capabilities via MLXVLM.
/// Generic scanner — works with any `ScanTemplate` to extract structured data from images.
@MainActor
class VisionManager: ObservableObject {
    
    static let shared = VisionManager()
    
    var isModelLoaded: Bool { MLXModelManager.shared.isLoaded }
    @Published var isProcessing: Bool = false
    @Published var status: String = ""
    @Published var lastResult: ScanResult?
    
    private let maxGeneratedTokens = 1024
    
    /// Uses the same model selection as GemmaManager.
    private var modelID: String {
        GemmaManager.shared.selectedModel.modelID
    }
    
    private init() {}
    
    // MARK: - Model Lifecycle
    
    /// Loads the VLM model for image+text inference.
    func loadModel() async {
        do {
            try await MLXModelManager.shared.loadModel(modelID: modelID)
        } catch {
            print("📷 Failed to load VLM model: \(error)")
        }
    }
    
    /// Releases the VLM model to free memory.
    func unloadModel() async {
        await MLXModelManager.shared.unloadModel()
        status = ""
    }
    
    // MARK: - Vision Processing
    
    /// Extracts structured data from an image using a local tool definition.
    @discardableResult
    func scan(image: CIImage, definition: LocalToolDefinition, customPrompt: String? = nil) async -> ScanResult? {
        guard let container = MLXModelManager.shared.container else {
            print("📷 VLM not loaded")
            status = "Model not loaded"
            return nil
        }
        guard !isProcessing else { return nil }
        
        isProcessing = true
        status = "Analyzing image..."
        lastResult = nil
        
        let prompt = customPrompt ?? prompt(for: definition)
        
        print("📷 Starting scan with tool: \(definition.toolID)")
        
        let maxTokens = maxGeneratedTokens
        
        do {
            let userInput = UserInput(
                chat: [
                    .user(prompt, images: [.ciImage(image)])
                ]
            )
            
            let rawOutput = try await container.perform { context in
                let input = try await context.processor.prepare(input: userInput)
                
                let result = try MLXLMCommon.generate(
                    input: input,
                    parameters: GenerateParameters(temperature: 0.1), // Low temp for precise extraction
                    context: context
                ) { tokens in
                    if tokens.count >= maxTokens { return .stop }
                    
                    let text = context.tokenizer.decode(tokenIds: tokens)
                    if text.contains("</s>") || text.contains("<end_of_turn>") || text.contains("<eos>") {
                        return .stop
                    }
                    
                    Task { @MainActor in
                        self.status = "Extracting data..."
                    }
                    return .more
                }
                return result.output
            }
            
            let output = cleanOutput(rawOutput)
            print("📷 Raw output: \(output)")
            
            let scanResult = parseResponse(output, definition: definition)
            
            self.lastResult = scanResult
            self.status = scanResult.hasData ? "✅ Data extracted" : "⚠️ Limited results"
            
            print("📷 Scan complete: \(scanResult.fields.count) fields extracted")
            
            isProcessing = false
            MLXModelManager.shared.clearCache()
            return scanResult
            
        } catch {
            print("📷 Scan error: \(error)")
            status = "Scan failed: \(error.localizedDescription)"
            isProcessing = false
            MLXModelManager.shared.clearCache()
            return nil
        }
    }

    
    // MARK: - Response Parsing
    
    /// Parses the LLM's JSON response into a ScanResult.
    /// Supports:
    ///   - Plain string values → FieldValue.string
    ///   - Array values       → FieldValue.list
    ///   - `_scriptNotes` key → ScanResult.scriptNotes  (extraction notes)
    ///   - `_script` key      → legacy extraction notes
    ///   - `_state` object    → ScanResult.state   (cross-scan persistent key-value pairs)
    ///   - `_actions` array   → declarative tool actions validated by Swift
    ///   - `_isValid` / `isValid` → isValidated
    ///   - `_validationNotes` / `validationNotes` → validationNotes
    func parseResponse(_ output: String, definition: LocalToolDefinition) -> ScanResult {
        let jsonString = extractJSON(from: output)
        let capabilities = Set(definition.capabilities)
        
        guard let data = jsonString.data(using: .utf8) else {
            return ScanResult(
                toolID: definition.toolID,
                template: definition.displayName,
                richFields: ["Raw Text": .string(output)],
                validationNotes: "Failed to parse response"
            )
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var richFields: [String: FieldValue] = [:]
                var validationNotes = ""
                var scriptNotes: String? = nil
                var state: [String: String]? = nil
                var actions: [ToolAction] = []
                var confidence: Double?
                var followUp: ToolFollowUp?
                
                for (key, value) in json {
                    // --- Meta keys (strip from visible fields) ---
                    if key == "isValid" || key == "_isValid" { continue }
                    
                    if key == "validationNotes" || key == "_validationNotes" {
                        validationNotes = "\(value)"
                        continue
                    }
                    
                    if key == "_scriptNotes" || key == "_script" {
                        scriptNotes = value as? String
                        continue
                    }
                    
                    if key == "_state" {
                        if capabilities.contains(.persistentState),
                           let stateDict = value as? [String: Any] {
                            state = stateDict.compactMapValues { v -> String? in
                                if let s = v as? String { return s }
                                if let n = v as? NSNumber { return n.stringValue }
                                return nil
                            }
                        }
                        continue
                    }
                    
                    if key == "_actions" {
                        if capabilities.contains(.openURL),
                           let actionValues = value as? [[String: Any]] {
                            actions = actionValues.compactMap(Self.parseAction)
                        }
                        continue
                    }
                    
                    if key == "_confidence" || key == "confidence" {
                        if let number = value as? NSNumber {
                            confidence = max(0, min(1, number.doubleValue))
                        } else if let string = value as? String, let parsed = Double(string) {
                            confidence = max(0, min(1, parsed))
                        }
                        continue
                    }
                    
                    if key == "_followUp" {
                        if let rawFollowUp = value as? [String: Any],
                           let rawTool = rawFollowUp["tool"] as? String {
                            let normalizedTool = LocalToolDefinition.normalizedToolID(rawTool)
                            let allowedChains = Set(definition.chainTo ?? [])
                            if allowedChains.contains(normalizedTool) {
                                followUp = ToolFollowUp(
                                    tool: normalizedTool,
                                    reason: rawFollowUp["reason"] as? String
                                )
                            }
                        }
                        continue
                    }
                    
                    // --- Data fields ---
                    if let arr = value as? [Any] {
                        // Array → FieldValue.list (flatten each element to string)
                        let items: [String] = arr.compactMap { item in
                            if let s = item as? String { return s }
                            if let n = item as? NSNumber { return n.stringValue }
                            return nil
                        }
                        if !items.isEmpty { richFields[key] = .list(items) }
                    } else if let stringValue = value as? String, !stringValue.isEmpty {
                        richFields[key] = .string(stringValue)
                    } else if let numValue = value as? NSNumber {
                        richFields[key] = .string(numValue.stringValue)
                    }
                }
                
                let numericIsValid = (json["_isValid"] as? Int).map { $0 == 1 }
                    ?? (json["isValid"] as? Int).map { $0 == 1 }
                let isValid = (json["_isValid"] as? Bool)
                    ?? (json["isValid"] as? Bool)
                    ?? numericIsValid
                    ?? (richFields.count >= 2)
                
                return ScanResult(
                    toolID: definition.toolID,
                    template: definition.displayName,
                    richFields: richFields,
                    isValidated: isValid,
                    validationNotes: validationNotes,
                    confidence: confidence,
                    followUp: followUp,
                    timestamp: Date(),
                    script: scriptNotes,
                    state: state,
                    actions: actions
                )
            }
        } catch {
            print("📷 JSON parse error: \(error)")
        }
        
        // Fallback: raw text capture
        return ScanResult(
            toolID: definition.toolID,
            template: definition.displayName,
            richFields: ["Raw Text": .string(output)],
            isValidated: false,
            validationNotes: "Could not parse structured data — raw text captured"
        )
    }
    
    private func prompt(for definition: LocalToolDefinition) -> String {
        var finalPrompt = definition.prompt ?? "Extract structured data from this image. Return ONLY valid JSON."
        
        // Inject briefing as high-level context
        if let briefing = definition.briefing {
            finalPrompt = "BRIEFING: \(briefing)\n\n\(finalPrompt)"
        }
        
        // Append rules if present
        if let rules = definition.rules, !rules.isEmpty {
            let rulesText = rules.map { "- \($0)" }.joined(separator: "\n")
            finalPrompt += "\n\nADDITIONAL RULES:\n\(rulesText)"
        }
        
        if let examples = definition.examples, !examples.isEmpty {
            let examplesText = examples.enumerated().map { index, example in
                let fields = example
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key): \($0.value)" }
                    .joined(separator: "\n")
                return "Example \(index + 1):\n\(fields)"
            }.joined(separator: "\n\n")
            finalPrompt += "\n\nFEW-SHOT EXAMPLES:\n\(examplesText)"
        }
        
        finalPrompt += runtimeProtocol(for: definition)
        
        // Add state for tools with persistent_state capability
        if definition.capabilities.contains(.persistentState) {
            let state = ToolStorage.shared.latestState(for: definition.toolID)
            if !state.isEmpty,
               let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]),
               let stateJSON = String(data: data, encoding: .utf8) {
                finalPrompt += """
                
                
                CURRENT TOOL STATE:
                \(stateJSON)
                
                Use CURRENT TOOL STATE only to update `_state`. Do not copy it into visible fields unless the image itself supports that value.
                """
            }
        }
        
        return finalPrompt
    }
    
    private func runtimeProtocol(for definition: LocalToolDefinition) -> String {
        var metaKeys = [
            "- `_isValid`: boolean extraction success flag.",
            "- `_validationNotes`: short user-readable quality note.",
            "- `_confidence`: number from 0.0 to 1.0."
        ]
        
        if definition.capabilities.contains(.persistentState) {
            metaKeys.append("- `_state`: string key-value memory matching the declared state schema.")
        } else {
            metaKeys.append("- Do not emit `_state`; this tool has no persistent state permission.")
        }
        
        if definition.capabilities.contains(.openURL) {
            metaKeys.append("- `_actions`: array of declarative user-approved actions. Only `openURL` actions are supported.")
        } else {
            metaKeys.append("- Do not emit `_actions`; this tool has no action permission.")
        }
        
        if let chainTo = definition.chainTo, !chainTo.isEmpty {
            metaKeys.append("- `_followUp`: optional object with `tool` and `reason`. `tool` must be one of: \(chainTo.joined(separator: ", ")).")
        } else {
            metaKeys.append("- Do not emit `_followUp`; this tool has no chaining permission.")
        }
        
        let outputSchema = definition.outputSchema.isEmpty
            ? "Choose clear user-facing field names for visible extracted data."
            : definition.outputSchema
                .sorted { $0.key < $1.key }
                .map { "- `\($0.key)`: \($0.value)" }
                .joined(separator: "\n")
        
        return """
        
        
        RUNTIME OUTPUT CONTRACT:
        Return ONLY one valid JSON object. Visible extracted fields must use user-facing keys.
        
        Visible output schema:
        \(outputSchema)
        
        Runtime meta keys:
        \(metaKeys.joined(separator: "\n"))
        
        The runtime will strip unsupported meta keys. Never include markdown, XML, code, or explanation outside the JSON object.
        """
    }
    
    private static func parseAction(_ raw: [String: Any]) -> ToolAction? {
        guard let typeValue = raw["type"] as? String,
              let type = ToolAction.ActionType(rawValue: typeValue) else {
            return nil
        }
        
        switch type {
        case .openURL:
            return ToolAction(
                type: type,
                url: raw["url"] as? String,
                label: raw["label"] as? String,
                requiresUserApproval: true
            )
        }
    }
    
    /// Extracts a JSON object substring from the model output.
    private func extractJSON(from text: String) -> String {
        guard let startIndex = text.firstIndex(of: "{"),
              let endIndex = text.lastIndex(of: "}") else {
            return text
        }
        return String(text[startIndex...endIndex])
    }
    
    /// Cleans stop tokens from model output.
    private func cleanOutput(_ output: String) -> String {
        var cleaned = output
        let stopSequences = ["<end_of_turn>", "<eos>", "<bos>", "<start_of_turn>", "</s>"]
        for seq in stopSequences {
            cleaned = cleaned.replacingOccurrences(of: seq, with: "")
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

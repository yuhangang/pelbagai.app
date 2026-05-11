import Foundation
import Hub
import MLXLMCommon
import MLXVLM
import Tokenizers

struct HubDownloaderBridge: Downloader, Sendable {
    let hub: HubApi

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        try await hub.snapshot(
            from: id,
            matching: patterns,
            progressHandler: progressHandler
        )
    }
}

struct TransformersTokenizerLoaderBridge: TokenizerLoader, Sendable {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await AutoTokenizer.from(modelFolder: directory)
        return TransformersTokenizerBridge(upstream)
    }
}

struct TransformersTokenizerBridge: MLXLMCommon.Tokenizer, Sendable {
    let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String : any Sendable]],
        tools: [[String : any Sendable]]? = nil,
        additionalContext: [String : any Sendable]? = nil
    ) throws -> [Int] {
        print("🧠 Tokenizer: Applying chat template to \(messages.count) messages")
        for (index, msg) in messages.enumerated() {
            let role = msg["role"] as? String ?? "unknown"
            let content = (msg["content"] as? String)?.prefix(50) ?? ""
            print("  [\(index)] role: \(role), content: \(content)...")
        }
        
        do {
            return try upstream.applyChatTemplate(
                messages: messages,
                tools: tools,
                additionalContext: additionalContext
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            print("🧠 Tokenizer: Missing chat template error")
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        } catch {
            print("🧠 Tokenizer: Error applying chat template: \(error)")
            throw error
        }
    }
}

func loadRemoteModelContainer(
    configuration: ModelConfiguration,
    progressHandler: @Sendable @escaping (Progress) -> Void = { _ in }
) async throws -> ModelContainer {
    let hub = HubApi()

    if configuration.name.contains("gemma-4-") {
        return try await VLMModelFactory.shared.loadContainer(
            from: HubDownloaderBridge(hub: hub),
            using: TransformersTokenizerLoaderBridge(),
            configuration: configuration,
            progressHandler: progressHandler
        )
    }

    return try await loadModelContainer(
        from: HubDownloaderBridge(hub: hub),
        using: TransformersTokenizerLoaderBridge(),
        configuration: configuration,
        progressHandler: progressHandler
    )
}

// MARK: - MemoryStats

/// Utility to query the OS for current memory usage and Jetsam limits.
enum MemoryStats {
    /// Returns (footprintMB, jetsamLimitMB) using task_vm_info.
    static func footprintMB() -> (Double, Double) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, 0) }
        let footprint = Double(info.phys_footprint) / 1_048_576
        let limit = Double(info.limit_bytes_remaining) / 1_048_576 + footprint
        return (footprint, limit)
    }

    /// Current available memory headroom (MB).
    static var headroomMB: Int {
        let (footprint, limit) = footprintMB()
        #if os(macOS)
        let simulatedJetsamMB = 6144
        return max(0, simulatedJetsamMB - Int(footprint))
        #else
        return max(0, Int(limit - footprint))
        #endif
    }

    /// Total physical memory in GB.
    static var totalMemoryGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
    }
}

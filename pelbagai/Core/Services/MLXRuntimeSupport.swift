import Foundation
import Darwin
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
    // This Hub package build treats `useOfflineMode: false` as advisory and can
    // still force the local-cache-only branch when NWPath reports constrained or
    // expensive connectivity. Disable that heuristic so first-run model loads
    // attempt real network fetches and fail with actual transport errors when
    // offline instead of the misleading "Repository not available locally".
    let hub = HubApi(useOfflineMode: false)
    setenv("CI_DISABLE_NETWORK_MONITOR", "1", 1)

    if configuration.name.contains("gemma-4-") {
        Gemma4Registration.setAudioCapabilityEnabled(false)
        Gemma4Processor.setRuntimeImageSoftTokenCap(32)
        await Gemma4Registration.register()

        let modelRegistry = ModelTypeRegistry<LanguageModel>()
        let processorRegistry = ProcessorTypeRegistry()
        let makeModel: @Sendable (Data) throws -> Gemma4Model = { data in
            try Gemma4Registration.makeModel(from: data)
        }
        await modelRegistry.registerModelType("gemma4", creator: makeModel)
        await modelRegistry.registerModelType("gemma4_audio", creator: makeModel)
        await processorRegistry.registerProcessorType("Gemma4Processor") { data, tokenizer in
            let configuration = try JSONDecoder.json5().decode(
                Gemma4ProcessorConfiguration.self,
                from: data
            )
            return Gemma4Processor(configuration, tokenizer: tokenizer)
        }

        print("🧠 [MLXModelManager] Using app-owned Gemma 4 VLM runtime")
        let gemma4Factory = VLMModelFactory(
            typeRegistry: modelRegistry,
            processorRegistry: processorRegistry,
            modelRegistry: VLMRegistry.shared
        )

        return try await gemma4Factory.loadContainer(
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

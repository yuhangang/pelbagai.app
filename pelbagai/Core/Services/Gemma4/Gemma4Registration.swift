import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM

// MARK: - Gemma 4 Model Registration

/// Register the "gemma4" model type with both the text and VLM registries.
///
/// Call this once at app startup before loading models:
/// ```swift
/// await Gemma4Registration.register()
/// ```
public enum Gemma4Registration {
    private static let runtimeOptionsLock = NSLock()
    private static var audioCapabilityEnabled = false

    nonisolated public static func setAudioCapabilityEnabled(_ enabled: Bool) {
        runtimeOptionsLock.lock()
        audioCapabilityEnabled = enabled
        runtimeOptionsLock.unlock()
    }

    nonisolated public static func currentAudioCapabilityEnabled() -> Bool {
        runtimeOptionsLock.lock()
        let enabled = audioCapabilityEnabled
        runtimeOptionsLock.unlock()
        return enabled
    }

    nonisolated private static func makeRuntimeConfiguration(from data: Data) throws -> Gemma4ModelConfiguration {
        let configuration = try JSONDecoder.json5().decode(
            Gemma4ModelConfiguration.self,
            from: data
        )
        return configuration.withAudioCapability(enabled: currentAudioCapabilityEnabled())
    }

    nonisolated public static func makeModel(from data: Data) throws -> Gemma4Model {
        let configuration = try makeRuntimeConfiguration(from: data)
        return Gemma4Model(configuration)
    }

    public static func register() async {
        let makeModel: @Sendable (Data) throws -> Gemma4Model = { data in
            try Self.makeModel(from: data)
        }

        await LLMTypeRegistry.shared.registerModelType("gemma4", creator: makeModel)
        await LLMTypeRegistry.shared.registerModelType("gemma4_audio", creator: makeModel)

        await VLMTypeRegistry.shared.registerModelType("gemma4", creator: makeModel)
        await VLMTypeRegistry.shared.registerModelType("gemma4_audio", creator: makeModel)

        await VLMProcessorTypeRegistry.shared.registerProcessorType("Gemma4Processor") { data, tokenizer in
            let configuration = try JSONDecoder.json5().decode(
                Gemma4ProcessorConfiguration.self,
                from: data
            )
            return Gemma4Processor(configuration, tokenizer: tokenizer)
        }
    }
}

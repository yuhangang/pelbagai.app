import Foundation

/// Centralizes memory-tier decisions for voice input so audio routing does not
/// drift between settings, model loading, and chat execution.
nonisolated struct VoiceRuntimePolicy {
    enum Route: Equatable {
        case nativeGemmaAudio
        case speechToText(unloadGemmaFirst: Bool)
    }

    private static let e4bAudioMinimumGB = 10.5
    private static let e2bAudioMaximumConstrainedGB = 8.0

    let totalMemoryGB: Double
    let selectedModel: GemmaModel
    let userEnabledNativeAudio: Bool

    init(
        totalMemoryGB: Double = MemoryStats.totalMemoryGB,
        selectedModel: GemmaModel,
        userEnabledNativeAudio: Bool = Self.userNativeAudioPreference()
    ) {
        self.totalMemoryGB = totalMemoryGB
        self.selectedModel = selectedModel
        self.userEnabledNativeAudio = userEnabledNativeAudio
    }

    /// The effective model-load decision. Native audio is allowed automatically
    /// for the device/model tiers that can reasonably avoid the Whisper swap.
    var shouldLoadGemmaAudioTower: Bool {
        switch selectedModel {
        case .e4b:
            return userEnabledNativeAudio && totalMemoryGB >= Self.e4bAudioMinimumGB
        case .e2b:
            return userEnabledNativeAudio && totalMemoryGB <= Self.e2bAudioMaximumConstrainedGB
        }
    }

    var preferredRoute: Route {
        if shouldLoadGemmaAudioTower {
            return .nativeGemmaAudio
        }

        return .speechToText(unloadGemmaFirst: shouldUnloadGemmaBeforeWhisper)
    }

    /// Whisper medium is too expensive to keep beside Gemma on lower tiers.
    /// High-memory devices may keep Gemma resident during rare STT fallback.
    var shouldUnloadGemmaBeforeWhisper: Bool {
        totalMemoryGB < Self.e4bAudioMinimumGB
    }

    static func shouldLoadGemmaAudioTower(
        modelID: String,
        totalMemoryGB: Double = MemoryStats.totalMemoryGB,
        userEnabledNativeAudio: Bool = Self.userNativeAudioPreference()
    ) -> Bool {
        let selectedModel = GemmaModel(modelID: modelID) ?? .e2b
        return VoiceRuntimePolicy(
            totalMemoryGB: totalMemoryGB,
            selectedModel: selectedModel,
            userEnabledNativeAudio: userEnabledNativeAudio
        ).shouldLoadGemmaAudioTower
    }

    private static func userNativeAudioPreference() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "gemma4AudioInputEnabled") == nil {
            return true
        }
        return defaults.bool(forKey: "gemma4AudioInputEnabled")
    }
}

import Foundation
import AVFoundation
import Combine

/// Manages text-to-speech output using AVSpeechSynthesizer.
/// Handles audio session configuration to avoid conflicts with WhisperKit recording.
@MainActor
class SpeechService: NSObject, ObservableObject {
    static let shared = SpeechService()
    
    @Published var isSpeaking: Bool = false
    
    private let synthesizer = AVSpeechSynthesizer()
    
    private override init() {
        super.init()
        synthesizer.delegate = SpeechDelegateAdapter.shared
        SpeechDelegateAdapter.shared.service = self
    }
    
    /// Speak the given text aloud.
    /// Automatically detects language from the text content.
    func speak(_ text: String) {
        // Stop any ongoing speech first
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        let cleanedText = cleanForSpeech(text)
        guard !cleanedText.isEmpty else { return }
        
        // Configure audio session for playback
        configureAudioSessionForPlayback()
        
        let utterance = AVSpeechUtterance(string: cleanedText)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // Auto-detect language
        if let detectedLanguage = detectLanguage(for: cleanedText) {
            utterance.voice = AVSpeechSynthesisVoice(language: detectedLanguage)
        }
        
        isSpeaking = true
        synthesizer.speak(utterance)
    }
    
    /// Stop any ongoing speech immediately.
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }
    
    // MARK: - Private Helpers
    
    private func configureAudioSessionForPlayback() {
#if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("🔊 Failed to configure audio session for TTS: \(error)")
        }
#endif
    }
    
    /// Clean model output artifacts before speaking
    private func cleanForSpeech(_ text: String) -> String {
        var cleaned = text
        
        // Remove common model artifacts
        let patternsToRemove = [
            "<end_of_turn>", "<eos>", "<bos>", "<start_of_turn>",
            "<tool_call>", "</tool_call>",
            "<tool_response>", "</tool_response>"
        ]
        for pattern in patternsToRemove {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "")
        }
        
        // Remove markdown-style formatting
        cleaned = cleaned.replacingOccurrences(of: "**", with: "")
        cleaned = cleaned.replacingOccurrences(of: "__", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        
        // Remove error prefixes that shouldn't be spoken
        if cleaned.hasPrefix("Error:") || cleaned.hasPrefix("⚠️") {
            return ""
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Simple language detection based on script analysis.
    /// Supports English, Malay (ms), and Chinese (zh).
    private func detectLanguage(for text: String) -> String? {
        var chineseCount = 0
        var totalCount = 0
        
        for scalar in text.unicodeScalars {
            if scalar.properties.isAlphabetic {
                totalCount += 1
                // CJK Unified Ideographs range
                if (0x4E00...0x9FFF).contains(scalar.value) ||
                   (0x3400...0x4DBF).contains(scalar.value) {
                    chineseCount += 1
                }
            }
        }
        
        guard totalCount > 0 else { return "en-US" }
        
        let chineseRatio = Double(chineseCount) / Double(totalCount)
        
        if chineseRatio > 0.3 {
            return "zh-CN"
        }
        
        // Check for Malay keywords
        let malayKeywords = ["saya", "anda", "ini", "itu", "untuk", "dengan", "dari",
                             "boleh", "tidak", "sudah", "akan", "ada", "yang", "dan",
                             "selamat", "terima", "kasih", "baik", "apa", "bagaimana"]
        let lowered = text.lowercased()
        let words = lowered.components(separatedBy: .whitespacesAndNewlines)
        let malayHits = words.filter { malayKeywords.contains($0) }.count
        
        if malayHits >= 2 || (words.count > 0 && Double(malayHits) / Double(words.count) > 0.2) {
            return "ms-MY"
        }
        
        return "en-US"
    }
    
    // Called by the delegate adapter when speech finishes
    fileprivate func didFinishSpeaking() {
        isSpeaking = false
    }
}

// MARK: - Delegate Adapter
// AVSpeechSynthesizerDelegate cannot be directly on a @MainActor class,
// so we use a separate non-isolated adapter.

private class SpeechDelegateAdapter: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechDelegateAdapter()
    weak var service: SpeechService?
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            service?.didFinishSpeaking()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            service?.didFinishSpeaking()
        }
    }
}

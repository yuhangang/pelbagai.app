import Foundation
import SwiftUI
import WhisperKit
import AVFoundation
import Combine

@MainActor
class WhisperManager: ObservableObject {
    enum WhisperManagerError: LocalizedError {
        case emptyAudio
        case emptyTranscript

        var errorDescription: String? {
            switch self {
            case .emptyAudio:
                return "No audio was recorded."
            case .emptyTranscript:
                return "I could not hear a clear spoken message."
            }
        }
    }

    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var isModelLoaded: Bool = false
    
    var isDownloaded: Bool {
        let fileManager = FileManager.default
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            // Check for a key file that indicates the model is present
            let configPath = documentsURL.appendingPathComponent("huggingface/models/openai/whisper-medium/tokenizer_config.json").path
            return fileManager.fileExists(atPath: configPath)
        }
        return false
    }
    
    static let shared = WhisperManager()
    
    private var whisperKit: WhisperKit?
    private let audioService = AudioService()
    
    // Buffer to accumulate audio samples before transcription
    private var speechBuffer: [Float] = []
    
    private init() {}
    
    func loadModel() async {
        guard whisperKit == nil else { return }
        
        isModelLoaded = false
        do {
            print("Starting WhisperKit initialization (Multilingual)...")
            
            // Ensure the directory structure exists to prevent move errors
            let fileManager = FileManager.default
            if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                let hfURL = documentsURL.appendingPathComponent("huggingface/models/openai/whisper-medium")
                if !fileManager.fileExists(atPath: hfURL.path) {
                    print("Creating model directory at: \(hfURL.path)")
                    try? fileManager.createDirectory(at: hfURL, withIntermediateDirectories: true)
                }
            }
            
            // Use the "medium" model for high accuracy in Malaysian multi-language speech
            self.whisperKit = try await WhisperKit(model: "medium")
            
            // Verify integrity (check for key files)
            if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                let configPath = documentsURL.appendingPathComponent("huggingface/models/openai/whisper-medium/tokenizer_config.json").path
                if !fileManager.fileExists(atPath: configPath) {
                    print("⚠️ Warning: tokenizer_config.json missing after load")
                    // If it's missing, WhisperKit might still throw during transcribe
                }
            }
            
            self.isModelLoaded = true
            print("WhisperKit Multilingual Model Loaded Successfully")
        } catch {
            print("Failed to load WhisperKit model: \(error)")
            await resetModel()
            
            DispatchQueue.main.async {
                self.transcript = "Model download failed or corrupted. Cache cleared. Please try again."
            }
        }
    }
    
    func unloadModel() async {
        if isRecording {
            audioService.stopRecording()
            isRecording = false
        }
        
        speechBuffer.removeAll(keepingCapacity: false)
        whisperKit = nil
        isModelLoaded = false
        print("WhisperKit model unloaded")
    }
    
    func resetModel() async {
        print("Cleaning up model cache...")
        let fileManager = FileManager.default
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let hfURL = documentsURL.appendingPathComponent("huggingface")
            try? fileManager.removeItem(at: hfURL)
        }
        self.whisperKit = nil
        self.isModelLoaded = false
    }

    func transcribe(samples: [Float]) async throws -> String {
        guard !samples.isEmpty else {
            throw WhisperManagerError.emptyAudio
        }
        if whisperKit == nil {
            await loadModel()
        }
        guard let whisperKit else {
            throw WhisperManagerError.emptyTranscript
        }

        print("🤖 Whisper: Transcribing one-shot audio with \(samples.count) samples...")
        let result = try await whisperKit.transcribe(audioArray: samples)
        let text = result.map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw WhisperManagerError.emptyTranscript
        }

        transcript = text
        return text
    }
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    func stopRecordingAndReturnTranscript() async -> String {
        guard isRecording else {
            return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        audioService.stopRecording()
        isRecording = false
        
        if !speechBuffer.isEmpty {
            await transcribeCurrentBuffer()
        }
        
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func startRecording() {
        guard isModelLoaded else { return }
        
        transcript = ""
        speechBuffer.removeAll()
        isRecording = true
        
        do {
            try audioService.startRecording { [weak self] audioBuffer in
                guard let self = self else { return }
                
                // Capture samples immediately from the buffer
                if let channelData = audioBuffer.floatChannelData?[0] {
                    let frames = Int(audioBuffer.frameLength)
                    let samples = Array(UnsafeBufferPointer(start: channelData, count: frames))
                    
                    Task { @MainActor in
                        await self.processAudioSamples(samples)
                    }
                }
            }
        } catch {
            print("Failed to start audio engine: \(error)")
            isRecording = false
        }
    }
    
    private func stopRecording() {
        audioService.stopRecording()
        isRecording = false
        
        // Final transcription of remaining buffer if not empty
        if !speechBuffer.isEmpty {
            Task {
                await transcribeCurrentBuffer()
            }
        }
    }
    
    private func processAudioSamples(_ samples: [Float]) async {
        guard isRecording else { return }
        
        speechBuffer.append(contentsOf: samples)
        
        // Transcribe every 2 seconds of audio (32,000 samples at 16kHz)
        if speechBuffer.count >= 32000 {
            await transcribeCurrentBuffer()
        }
    }
    
    private func transcribeCurrentBuffer() async {
        guard let whisperKit = whisperKit, !speechBuffer.isEmpty else { return }
        
        let samplesToTranscribe = speechBuffer
        speechBuffer.removeAll() // Clear for next chunk
        
        print("🤖 Whisper: Transcribing \(samplesToTranscribe.count) samples...")
        
        do {
            let result = try await whisperKit.transcribe(audioArray: samplesToTranscribe)
            if let topResult = result.first, !topResult.text.isEmpty {
                self.transcript += topResult.text + " "
            }
        } catch {
            print("Transcription error: \(error)")
            let errorDescription = error.localizedDescription
            
            if errorDescription.contains("tokenizer") || errorDescription.contains("missingConfig") {
                self.transcript = "⚠️ Model files corrupted. Please tap 'Reset Model' or restart app."
            } else {
                self.transcript += "[Error: \(errorDescription)] "
            }
        }
    }
}

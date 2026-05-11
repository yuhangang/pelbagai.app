import Foundation
import AVFoundation

/// Handles raw audio capture from the device microphone
class AudioService {
    private let audioEngine = AVAudioEngine()
    private var isRecording = false
    
    /// The required audio format for Whisper (16kHz, mono, PCM)
    private let requiredFormat: AVAudioFormat
    
    init() {
        // Whisper expects 16kHz, 1 channel (mono) PCM audio
        self.requiredFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: 16000.0,
                                            channels: 1,
                                            interleaved: false)!
    }
    
    func startRecording(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        guard !isRecording else { return }
        
#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
#endif
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        // Setup converter to convert native hardware format to Whisper's required 16kHz format
        guard let converter = AVAudioConverter(from: inputFormat, to: requiredFormat) else {
            throw AudioError.converterSetupFailed
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 8192, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }
            print("🎤 Audio Tap: Received \(buffer.frameLength) frames")
            // Calculate capacity based on the sample rate conversion ratio
            let capacity = UInt32(Double(buffer.frameLength) * (self.requiredFormat.sampleRate / inputFormat.sampleRate))
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: self.requiredFormat, frameCapacity: capacity) else {
                return
            }
            
            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
            
            if error == nil {
                onBuffer(convertedBuffer)
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }
    
    func stopRecording() {
        guard isRecording else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false
    }
}

enum AudioError: Error {
    case converterSetupFailed
}

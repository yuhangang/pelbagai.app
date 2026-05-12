import Foundation
import AVFoundation

@MainActor
struct MediaPlugin: NativePlugin {
    let id = "media"
    let displayName = "Media"

    var capabilities: [NativePluginCapability] {
        [
            NativePluginCapability(
                id: "record_status",
                displayName: "Recording Status",
                description: "Check if the app is currently recording audio.",
                argumentSchema: [:],
                requiresUserApproval: false
            ),
            NativePluginCapability(
                id: "play_tone",
                displayName: "Play System Tone",
                description: "Play a system notification sound.",
                argumentSchema: [:],
                requiresUserApproval: false
            )
        ]
    }

    var chatTools: [NativeChatTool] {
        [
            NativeChatTool(
                name: "check_media_status",
                displayName: "Media Status",
                description: "Check current recording or playback status.",
                pluginID: id,
                capabilityID: "record_status"
            )
        ]
    }

    func execute(capabilityID: String, arguments: [String: String]) async throws -> NativePluginResult {
        switch capabilityID {
        case "record_status":
            #if os(iOS)
            let status = AVAudioSession.sharedInstance().recordPermission
            return NativePluginResult(summary: "Microphone permission status: \(status == .granted ? "Granted" : "Not Granted")")
            #else
            return NativePluginResult(summary: "Microphone permission check is not supported on this platform.")
            #endif
        case "play_tone":
            AudioServicesPlaySystemSound(1000) // Example system sound
            return NativePluginResult(summary: "Played system tone.")
        default:
            throw NativePluginError.unknownCapability(pluginID: id, capabilityID: capabilityID)
        }
    }
}

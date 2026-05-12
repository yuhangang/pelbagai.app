import Foundation
#if os(iOS)
import UIKit
#endif

@MainActor
struct ClipboardPlugin: NativePlugin {
    let id = "clipboard"
    let displayName = "Clipboard"

    var capabilities: [NativePluginCapability] {
        [
            NativePluginCapability(
                id: "read",
                displayName: "Read Clipboard",
                description: "Get the current text from the system clipboard.",
                argumentSchema: [:],
                requiresUserApproval: false
            ),
            NativePluginCapability(
                id: "write",
                displayName: "Write Clipboard",
                description: "Copy text to the system clipboard.",
                argumentSchema: ["text": "The text to copy"],
                requiresUserApproval: false
            )
        ]
    }

    var chatTools: [NativeChatTool] {
        [
            NativeChatTool(
                name: "read_clipboard",
                displayName: "Read Clipboard",
                description: "Use to get text from the clipboard when requested.",
                pluginID: id,
                capabilityID: "read"
            ),
            NativeChatTool(
                name: "copy_to_clipboard",
                displayName: "Copy to Clipboard",
                description: "Use to copy text or snippets for the user.",
                pluginID: id,
                capabilityID: "write"
            )
        ]
    }

    func execute(capabilityID: String, arguments: [String: String]) async throws -> NativePluginResult {
        #if os(iOS)
        switch capabilityID {
        case "read":
            let text = UIPasteboard.general.string ?? ""
            return NativePluginResult(summary: text.isEmpty ? "Clipboard is empty." : "Clipboard content: \(text)", data: ["text": text])
        case "write":
            let text = arguments["text"] ?? ""
            UIPasteboard.general.string = text
            return NativePluginResult(summary: "Text copied to clipboard.")
        default:
            throw NativePluginError.unknownCapability(pluginID: id, capabilityID: capabilityID)
        }
        #else
        return NativePluginResult(summary: "Clipboard operations only available on iOS.")
        #endif
    }
}

import Foundation
import Combine

#if os(iOS)
import UIKit
#endif

/// A Swift-owned native capability provider.
///
/// Plugins are intentionally not model-generated and not loaded from JSON. They
/// own integration with system frameworks, while chat tools and local tool
/// definitions remain model-facing adapters over this trusted Swift layer.
@MainActor
protocol NativePlugin {
    var id: String { get }
    var displayName: String { get }
    var capabilities: [NativePluginCapability] { get }
    var chatTools: [NativeChatTool] { get }

    func execute(capabilityID: String, arguments: [String: String]) async throws -> NativePluginResult
}

struct NativePluginCapability: Identifiable, Equatable {
    var id: String
    var displayName: String
    var description: String
    var argumentSchema: [String: String]
    var requiresUserApproval: Bool
}

struct NativeChatTool: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var displayName: String
    var description: String
    var pluginID: String
    var capabilityID: String
}

struct NativePluginResult: Equatable {
    var summary: String
    var data: [String: String]
    var isHiddenContext: Bool

    init(
        summary: String,
        data: [String: String] = [:],
        isHiddenContext: Bool = false
    ) {
        self.summary = summary
        self.data = data
        self.isHiddenContext = isHiddenContext
    }
}

enum NativePluginError: LocalizedError {
    case unknownPlugin(String)
    case unknownCapability(pluginID: String, capabilityID: String)
    case unknownChatTool(String)

    var errorDescription: String? {
        switch self {
        case .unknownPlugin(let pluginID):
            return "Native plugin '\(pluginID)' is not available."
        case .unknownCapability(let pluginID, let capabilityID):
            return "Native plugin '\(pluginID)' does not expose capability '\(capabilityID)'."
        case .unknownChatTool(let toolName):
            return "Native chat tool '\(toolName)' is not available."
        }
    }
}

@MainActor
final class NativePluginRegistry: ObservableObject {
    static let shared = NativePluginRegistry()

    @Published private(set) var plugins: [String: any NativePlugin] = [:]
    @Published private(set) var chatTools: [String: NativeChatTool] = [:]

    private init() {
        registerBuiltIns()
    }

    func register(_ plugin: any NativePlugin) {
        plugins[plugin.id] = plugin
        for tool in plugin.chatTools {
            chatTools[tool.name] = tool
        }
    }

    func capability(pluginID: String, capabilityID: String) -> NativePluginCapability? {
        plugins[pluginID]?.capabilities.first { $0.id == capabilityID }
    }

    func chatTool(named name: String) -> NativeChatTool? {
        chatTools[name]
    }

    func executeChatTool(name: String, arguments: [String: String] = [:]) async throws -> NativePluginResult {
        guard let tool = chatTools[name] else {
            throw NativePluginError.unknownChatTool(name)
        }
        return try await execute(
            pluginID: tool.pluginID,
            capabilityID: tool.capabilityID,
            arguments: arguments
        )
    }

    func execute(
        pluginID: String,
        capabilityID: String,
        arguments: [String: String] = [:]
    ) async throws -> NativePluginResult {
        guard let plugin = plugins[pluginID] else {
            throw NativePluginError.unknownPlugin(pluginID)
        }
        guard plugin.capabilities.contains(where: { $0.id == capabilityID }) else {
            throw NativePluginError.unknownCapability(pluginID: pluginID, capabilityID: capabilityID)
        }
        return try await plugin.execute(capabilityID: capabilityID, arguments: arguments)
    }

    private func registerBuiltIns() {
        register(SystemInfoPlugin())
        register(ContactsPlugin())
        register(EventKitPlugin())
        register(HealthKitPlugin())
        register(ClipboardPlugin())
        register(MediaPlugin())
        register(StoragePlugin())
    }
}

private struct SystemInfoPlugin: NativePlugin {
    let id = "system_info"
    let displayName = "System Info"

    var capabilities: [NativePluginCapability] {
        [
            NativePluginCapability(
                id: "current_time",
                displayName: "Current Time",
                description: "Return the device-local current date and time.",
                argumentSchema: [:],
                requiresUserApproval: false
            ),
            NativePluginCapability(
                id: "battery_status",
                displayName: "Battery Status",
                description: "Return the current battery percentage and charging state.",
                argumentSchema: [:],
                requiresUserApproval: false
            )
        ]
    }

    var chatTools: [NativeChatTool] {
        [
            NativeChatTool(
                name: "get_current_time",
                displayName: "Current Time",
                description: "Use only when the user explicitly asks for the current time or date.",
                pluginID: id,
                capabilityID: "current_time"
            ),
            NativeChatTool(
                name: "get_battery_level",
                displayName: "Battery Level",
                description: "Use only when the user explicitly asks for battery level or charging state.",
                pluginID: id,
                capabilityID: "battery_status"
            )
        ]
    }

    func execute(capabilityID: String, arguments: [String: String]) async throws -> NativePluginResult {
        switch capabilityID {
        case "current_time":
            return currentTime()
        case "battery_status":
            return batteryStatus()
        default:
            throw NativePluginError.unknownCapability(pluginID: id, capabilityID: capabilityID)
        }
    }

    private func currentTime() -> NativePluginResult {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = .current

        let isoFormatter = ISO8601DateFormatter()
        let now = Date()
        let localTime = formatter.string(from: now)
        return NativePluginResult(
            summary: localTime,
            data: [
                "local_time": localTime,
                "iso8601": isoFormatter.string(from: now),
                "timezone": TimeZone.current.identifier
            ]
        )
    }

    private func batteryStatus() -> NativePluginResult {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let rawLevel = UIDevice.current.batteryLevel
        let percentage = rawLevel >= 0 ? Int((rawLevel * 100).rounded()) : -1
        let state: String
        switch UIDevice.current.batteryState {
        case .charging:
            state = "charging"
        case .full:
            state = "full"
        case .unplugged:
            state = "unplugged"
        case .unknown:
            fallthrough
        @unknown default:
            state = "unknown"
        }

        let summary = percentage >= 0
            ? "Battery level: \(percentage)%, state: \(state)"
            : "Battery state: \(state). Battery percentage is unavailable."
        return NativePluginResult(
            summary: summary,
            data: [
                "level_percent": percentage >= 0 ? "\(percentage)" : "",
                "state": state
            ]
        )
        #else
        return NativePluginResult(
            summary: "Battery information only available on iOS devices.",
            data: ["available": "false"]
        )
        #endif
    }
}

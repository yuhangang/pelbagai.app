import Foundation

@MainActor
struct AgentRoute {
    var candidateTools: [NativeChatTool]
    var shouldUseToolPrompt: Bool { !candidateTools.isEmpty }
}

@MainActor
final class AgentRouter {
    private let plugins: NativePluginRegistry

    init(plugins: NativePluginRegistry) {
        self.plugins = plugins
    }

    func route(prompt: String) -> AgentRoute {
        let normalized = prompt.lowercased()
        var names: [String] = []

        if containsAny(["battery", "bateri", "charging", "charge level"], in: normalized) {
            names.append("get_battery_level")
        }

        if containsAny(["what time", "what's the time", "current time", "time now", "date today", "today's date", "what date", "pukul berapa", "jam berapa"], in: normalized) {
            names.append("get_current_time")
        }

        if containsAny(["schedule", "calendar", "meeting", "event", "appointment"], in: normalized) {
            if containsAny(["add", "create", "schedule", "book", "set up"], in: normalized) {
                names.append("add_calendar_event")
            }
            names.append("get_calendar_events")
        }

        if containsAny(["reminder", "remind me", "todo", "to-do"], in: normalized) {
            if containsAny(["add", "create", "set", "remind me"], in: normalized) {
                names.append("add_reminder")
            }
            names.append("get_reminders")
        }

        if containsAny(["contact", "phone number", "address book"], in: normalized) {
            if containsAny(["add contact", "create contact", "save contact"], in: normalized) {
                names.append("create_contact")
            }
            names.append("search_contacts")
        }

        if containsAny(["documents", "files", "local file"], in: normalized) {
            names.append("list_documents")
            if containsAny(["read", "open", "show"], in: normalized) {
                names.append("read_local_file")
            }
        }

        let uniqueNames = names.reduce(into: [String]()) { partial, name in
            if !partial.contains(name) {
                partial.append(name)
            }
        }
        let tools = uniqueNames.compactMap { plugins.chatTool(named: $0) }
        return AgentRoute(candidateTools: tools)
    }

    private func containsAny(_ needles: [String], in text: String) -> Bool {
        needles.contains { text.contains($0) }
    }
}

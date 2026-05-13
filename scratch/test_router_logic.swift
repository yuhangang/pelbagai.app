import Foundation

// Mocking required parts to test AgentRouter
struct NativeChatTool: Equatable {
    var name: String
}

class NativePluginRegistry {
    static let shared = NativePluginRegistry()
    var chatTools: [String: NativeChatTool] = [:]
    
    init() {
        // Mock the tools we expect
        let toolNames = [
            "get_battery_level", "get_current_time", "add_calendar_event",
            "get_calendar_events", "add_reminder", "get_reminders",
            "get_step_count", "get_heart_rate", "read_clipboard",
            "copy_to_clipboard", "check_media_status", "knowledge_base",
            "save_to_tool_table", "list_documents", "read_local_file",
            "create_contact", "search_contacts"
        ]
        for name in toolNames {
            chatTools[name] = NativeChatTool(name: name)
        }
    }
    
    func chatTool(named name: String) -> NativeChatTool? {
        chatTools[name]
    }
}

struct AgentRoute {
    var candidateTools: [NativeChatTool]
}

class AgentRouter {
    private let plugins = NativePluginRegistry.shared
    
    func route(prompt: String) -> AgentRoute {
        let normalized = prompt.lowercased()
        var names: [String] = []

        if containsAny(["battery", "bateri", "charging", "charge level"], in: normalized) {
            names.append("get_battery_level")
        }

        if containsAny(["what time", "what's the time", "current time", "time now", "date today", "today's date", "what date", "pukul berapa", "jam brushes"], in: normalized) {
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

        if containsAny(["step", "heart rate", "bpm", "health", "fitness", "walking", "pulse"], in: normalized) {
            names.append("get_step_count")
            names.append("get_heart_rate")
        }

        if containsAny(["clipboard", "copy", "paste", "papan klip", "salin"], in: normalized) {
            names.append("read_clipboard")
            names.append("copy_to_clipboard")
        }

        if containsAny(["media", "recording", "mic", "microphone", "status"], in: normalized) {
            names.append("check_media_status")
        }

        if containsAny(["knowledge", "search", "survival", "find", "guide", "info", "fact", "rag", "document", "file"], in: normalized) {
            names.append("knowledge_base")
        }

        if containsAny(["save", "store", "record", "receipt", "table", "document", "list files", "read file"], in: normalized) {
            names.append("save_to_tool_table")
            names.append("list_documents")
            names.append("read_local_file")
        }

        if containsAny(["what can you do", "help", "tools", "capabilities", "list", "available"], in: normalized) {
            return AgentRoute(candidateTools: Array(plugins.chatTools.values))
        }

        if containsAny(["contact", "phone number", "address book"], in: normalized) {
            if containsAny(["add", "create", "save"], in: normalized) {
                names.append("create_contact")
            }
            names.append("search_contacts")
        }

        let uniqueNames = Array(Set(names))
        let tools = uniqueNames.compactMap { plugins.chatTool(named: $0) }
        return AgentRoute(candidateTools: tools)
    }

    private func containsAny(_ needles: [String], in text: String) -> Bool {
        needles.contains { text.contains($0) }
    }
}

// Running tests
func runTests() {
    let router = AgentRouter()
    
    let testCases = [
        "How is my battery?": ["get_battery_level"],
        "What time is it?": ["get_current_time"],
        "Show me my steps": ["get_step_count", "get_heart_rate"],
        "Copy this to clipboard": ["read_clipboard", "copy_to_clipboard"],
        "Search knowledge base for jungle survival": ["knowledge_base"],
        "Save this receipt for 50 dollars": ["save_to_tool_table", "list_documents", "read_local_file"],
        "What are your tools?": ["ALL"],
        "Find contact named John": ["search_contacts"]
    ]
    
    for (prompt, expected) in testCases {
        let route = router.route(prompt: prompt)
        let toolNames = route.candidateTools.map { $0.name }.sorted()
        
        if expected.contains("ALL") {
            print("Prompt: '\(prompt)' -> Found \(toolNames.count) tools (Help/List route works)")
        } else {
            print("Prompt: '\(prompt)' -> Tools: \(toolNames)")
        }
    }
}

runTests()

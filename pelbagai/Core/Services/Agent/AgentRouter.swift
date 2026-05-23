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

        if containsAny(["schedule", "calendar", "meeting", "event", "appointment", "tomorrow", "tmr", "today"], in: normalized) {
            if containsAny(["add", "create", "generate", "make", "new", "schedule", "book", "set up", "set"], in: normalized) {
                names.append("add_calendar_event")
            }
            names.append("get_calendar_events")
        }

        if containsAny(["reminder", "remind me", "todo", "to-do", "tomorrow", "tmr", "today"], in: normalized) {
            if containsAny(["add", "create", "generate", "make", "new", "set", "remind me"], in: normalized) {
                names.append("add_reminder")
            }
            names.append("get_reminders")
        }

        // --- Health & Fitness ---
        if containsAny(["step", "heart rate", "bpm", "health", "fitness", "walking", "pulse"], in: normalized) {
            names.append("get_step_count")
            names.append("get_heart_rate")
        }

        // --- Clipboard ---
        if containsAny(["clipboard", "copy", "paste", "papan klip", "salin"], in: normalized) {
            names.append("read_clipboard")
            names.append("copy_to_clipboard")
        }

        // --- Media & Status ---
        if containsAny(["media", "recording", "mic", "microphone", "status"], in: normalized) {
            names.append("check_media_status")
        }

        // --- Knowledge Base (RAG) ---
        if containsAny(["knowledge", "search", "survival", "find", "guide", "info", "fact", "rag", "document", "file"], in: normalized) {
            names.append("knowledge_base")
        }

        // --- Storage & Persistence ---
        if containsAny(["save", "store", "record", "receipt", "table", "document", "list files", "read file"], in: normalized) {
            names.append("save_to_tool_table")
            names.append("list_documents")
            names.append("read_local_file")
        }

        if containsAny(["receipt", "expense", "spending", "report", "chart", "summarize receipts", "summarise receipts"], in: normalized),
           containsAny(["report", "chart", "summary", "summarize", "summarise", "analyse", "analyze", "total", "spending", "expense"], in: normalized) {
            names.append("run_tool_workflow")
        }

        // --- Meta: List Tools / Help ---
        if containsAny(["what can you do", "help", "tools", "capabilities", "list", "available"], in: normalized) {
            // Include a representative set of tools so the agent can describe its powers
            return AgentRoute(candidateTools: plugins.enabledChatTools)
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

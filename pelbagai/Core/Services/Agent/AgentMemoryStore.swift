import Foundation

@MainActor
final class AgentMemoryStore {
    static let shared = AgentMemoryStore(database: .shared)

    private let database: DatabaseManager

    init(database: DatabaseManager) {
        self.database = database
    }

    func contextBlock(for prompt: String, limit: Int = 6) -> String {
        let memories = database.searchAgentMemory(query: prompt, limit: limit)
        guard !memories.isEmpty else { return "" }

        let rows = memories.map { memory in
            "- \(memory.kind).\(memory.key): \(memory.value)"
        }
        return """
        Long-term local memory:
        \(rows.joined(separator: "\n"))
        """
    }

    func observeUserMessage(_ text: String, sessionId: UUID) {
        for candidate in Self.memoryCandidates(from: text) {
            database.upsertAgentMemory(
                kind: candidate.kind,
                key: candidate.key,
                value: candidate.value,
                sourceSessionId: sessionId
            )
        }
    }

    func recordToolResult(toolName: String, summary: String, sessionId: UUID) {
        let normalized = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        database.upsertAgentMemory(
            kind: "tool_result",
            key: toolName,
            value: String(normalized.prefix(500)),
            sourceSessionId: sessionId
        )
    }

    private static func memoryCandidates(from text: String) -> [(kind: String, key: String, value: String)] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let lowercased = trimmed.lowercased()
        var candidates: [(kind: String, key: String, value: String)] = []

        if let value = capture(afterAnyPrefix: ["remember that", "please remember that"], in: trimmed) {
            candidates.append(("user_note", stableKey(from: value), value))
        }

        if let value = capture(afterAnyPrefix: ["my name is", "i am called", "call me"], in: trimmed) {
            candidates.append(("user_profile", "name", value))
        }

        if let value = capture(afterAnyPrefix: ["i prefer", "i like", "i usually"], in: trimmed) {
            candidates.append(("user_preference", stableKey(from: value), value))
        }

        if lowercased.contains("don't forget") || lowercased.contains("dont forget") {
            candidates.append(("user_note", stableKey(from: trimmed), trimmed))
        }

        return candidates
    }

    private static func capture(afterAnyPrefix prefixes: [String], in text: String) -> String? {
        for prefix in prefixes {
            guard let range = text.range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
            let suffix = text[range.upperBound...]
                .trimmingCharacters(in: CharacterSet(charactersIn: " .,:;\n\t"))
            if !suffix.isEmpty {
                return String(suffix.prefix(240))
            }
        }
        return nil
    }

    private static func stableKey(from value: String) -> String {
        let words = value
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .prefix(5)
        let key = words.joined(separator: "_")
        return key.isEmpty ? "note" : key
    }
}

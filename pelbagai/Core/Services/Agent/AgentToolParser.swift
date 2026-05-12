import Foundation

enum AgentToolParser {
    private static let toolCallOpenTag = "<tool_call>"
    private static let toolCallCloseTag = "</tool_call>"
    private static let clarifyOpenTag = "<clarify>"
    private static let clarifyCloseTag = "</clarify>"

    static func parseToolCall(from output: String, allowedToolNames: Set<String>) -> AgentToolCall? {
        guard let startRange = output.range(of: toolCallOpenTag),
              let endRange = output.range(of: toolCallCloseTag, range: startRange.upperBound..<output.endIndex) else {
            return nil
        }

        let jsonString = String(output[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawName = object["name"] as? String else {
            return nil
        }

        let name = canonicalToolName(rawName)
        guard allowedToolNames.contains(name) else {
            print("🤖 [Agent] Dropped unregistered tool call: \(rawName)")
            return nil
        }

        let rawArguments = (object["arguments"] as? [String: Any])
            ?? (object["args"] as? [String: Any])
            ?? [:]
        let arguments = rawArguments.reduce(into: [String: String]()) { partial, item in
            partial[item.key] = stringify(item.value)
        }

        return AgentToolCall(name: name, arguments: arguments)
    }

    static func parseClarification(from output: String) -> ClarificationRequest? {
        guard let startRange = output.range(of: clarifyOpenTag),
              let endRange = output.range(of: clarifyCloseTag, range: startRange.upperBound..<output.endIndex) else {
            return nil
        }

        let jsonString = String(output[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ClarificationRequest.self, from: data)
    }

    static func visibleOutput(from output: String) -> String {
        var visible = output
        if visible.contains(toolCallCloseTag) {
            visible = visible.replacingOccurrences(
                of: "\(NSRegularExpression.escapedPattern(for: toolCallOpenTag)).*?\(NSRegularExpression.escapedPattern(for: toolCallCloseTag))",
                with: "",
                options: .regularExpression
            )
        }
        if let range = visible.range(of: toolCallOpenTag) {
            visible = String(visible[..<range.lowerBound])
        }
        if visible.contains(clarifyCloseTag) {
            visible = visible.replacingOccurrences(
                of: "\(NSRegularExpression.escapedPattern(for: clarifyOpenTag)).*?\(NSRegularExpression.escapedPattern(for: clarifyCloseTag))",
                with: "",
                options: .regularExpression
            )
        }
        if let range = visible.range(of: clarifyOpenTag) {
            visible = String(visible[..<range.lowerBound])
        }
        return visible.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canonicalToolName(_ toolName: String) -> String {
        toolName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .lowercased()
    }

    private static func stringify(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        default:
            if JSONSerialization.isValidJSONObject(value),
               let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
            return "\(value)"
        }
    }
}

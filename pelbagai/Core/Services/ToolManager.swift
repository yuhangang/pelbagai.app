import Foundation
import Combine

@MainActor
final class ToolManager: ObservableObject {
    static let shared = ToolManager()

    struct Response {
        let text: String
        var imageURL: String? = nil
        var isHiddenContext: Bool = false
        var contextData: [String: String]? = nil
    }

    struct ExecutionResult {
        var scanResult: ScanResult
        var responses: [Response]
    }

    private init() {}

    func execute(result: ScanResult, definition: LocalToolDefinition) async -> ExecutionResult {
        var updated = applyStateBridges(to: result, definition: definition)
        let actionName = requestedAction(from: updated)

        guard let actionName,
              let runtimeAction = definition.runtimeActions?[actionName] else {
            return ExecutionResult(scanResult: updated, responses: [])
        }

        do {
            let response = try await executeRuntimeAction(
                runtimeAction,
                actionName: actionName,
                result: updated
            )
            return ExecutionResult(scanResult: updated, responses: [response])
        } catch {
            let topic = resolvedTopic(for: runtimeAction, from: updated)
            let message: String
            if let topic, !topic.isEmpty {
                message = "I identified the subject as \(topic), but could not fetch more detail."
            } else {
                message = "I could not fetch more detail for that request."
            }
            return ExecutionResult(
                scanResult: updated,
                responses: [Response(text: message)]
            )
        }
    }

    private func applyStateBridges(
        to result: ScanResult,
        definition: LocalToolDefinition
    ) -> ScanResult {
        guard let bridges = definition.stateBridges, !bridges.isEmpty else {
            return result
        }

        var updated = result
        var mergedState = updated.state ?? [:]

        for bridge in bridges {
            let currentValue = stringValue(for: bridge.field, in: updated)
            let sanitizedCurrent = sanitize(currentValue, using: bridge.sanitizer)

            if bridge.fallbackToState,
               (sanitizedCurrent?.isEmpty ?? true),
               let fallback = mergedState[bridge.stateKey],
               !fallback.isEmpty {
                updated.richFields[bridge.field] = .string(fallback)
            }

            if bridge.persistToState,
               let persistedValue = sanitize(stringValue(for: bridge.field, in: updated), using: bridge.sanitizer),
               !persistedValue.isEmpty {
                mergedState[bridge.stateKey] = persistedValue
                updated.richFields[bridge.field] = .string(persistedValue)
            }
        }

        updated.state = mergedState.isEmpty ? updated.state : mergedState
        return updated
    }

    private func requestedAction(from result: ScanResult) -> String? {
        let action = stringValue(for: "_action", in: result) ?? stringValue(for: "action", in: result)
        let trimmed = action?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func executeRuntimeAction(
        _ runtimeAction: LocalToolDefinition.RuntimeActionDefinition,
        actionName: String,
        result: ScanResult
    ) async throws -> Response {
        if let plugin = runtimeAction.plugin {
            return try await response(for: plugin, result: result)
        }

        guard let request = runtimeAction.request else {
            throw ToolRuntimeError.invalidResponse
        }

        do {
            return try await response(for: request, runtimeAction: runtimeAction, result: result)
        } catch {
            guard let fallbackRequest = runtimeAction.fallbackRequest else {
                throw error
            }
            return try await response(for: fallbackRequest, runtimeAction: runtimeAction, result: result)
        }
    }

    private func response(
        for pluginInvocation: LocalToolDefinition.PluginInvocationDefinition,
        result: ScanResult
    ) async throws -> Response {
        let arguments = resolvedPluginArguments(pluginInvocation.arguments ?? [:], result: result)
        let pluginResult = try await NativePluginRegistry.shared.execute(
            pluginID: pluginInvocation.pluginID,
            capabilityID: pluginInvocation.capabilityID,
            arguments: arguments
        )

        var text = pluginResult.summary
        if let responseField = pluginInvocation.responseField,
           let fieldValue = pluginResult.data[responseField]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fieldValue.isEmpty {
            text = fieldValue
        }

        return Response(
            text: text,
            isHiddenContext: pluginInvocation.hiddenContext ?? pluginResult.isHiddenContext,
            contextData: pluginResult.data
        )
    }

    private func response(
        for request: LocalToolDefinition.RuntimeRequestDefinition,
        runtimeAction: LocalToolDefinition.RuntimeActionDefinition,
        result: ScanResult
    ) async throws -> Response {
        let url = try resolvedURL(for: request, runtimeAction: runtimeAction, result: result)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ToolRuntimeError.requestFailed
        }

        let object = try parseJSONObject(data)
        let question = resolvedQuestion(for: runtimeAction, from: result)
        let topic = resolvedTopic(for: runtimeAction, from: result)

        switch request.responseMode {
        case .textPath:
            guard let textPath = request.textPath,
                  let text = string(at: textPath, in: object)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                throw ToolRuntimeError.invalidResponse
            }
            return Response(text: text, imageURL: string(at: request.imageURLPath, in: object))

        case .htmlLeadSections:
            let paragraphs = sectionBodies(
                at: request.sectionsPath,
                bodyKey: request.sectionBodyKey ?? "text",
                in: object
            )
            let text = paragraphs.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw ToolRuntimeError.invalidResponse
            }
            return Response(text: text, imageURL: string(at: request.imageURLPath, in: object))

        case .rankedHTMLSections:
            let text = rankedSectionText(
                request: request,
                object: object,
                topic: topic,
                question: question
            )
            guard !text.isEmpty else {
                throw ToolRuntimeError.invalidResponse
            }
            return Response(text: text, imageURL: string(at: request.imageURLPath, in: object))
        }
    }

    private func resolvedURL(
        for request: LocalToolDefinition.RuntimeRequestDefinition,
        runtimeAction: LocalToolDefinition.RuntimeActionDefinition,
        result: ScanResult
    ) throws -> URL {
        var endpoint = request.endpointTemplate
        if endpoint.contains("{topic}") {
            guard let topic = resolvedTopic(for: runtimeAction, from: result), !topic.isEmpty else {
                throw ToolRuntimeError.missingTopic
            }
            endpoint = endpoint.replacingOccurrences(of: "{topic}", with: encodePathComponent(topic))
        }
        if endpoint.contains("{question}") {
            let question = resolvedQuestion(for: runtimeAction, from: result) ?? ""
            endpoint = endpoint.replacingOccurrences(of: "{question}", with: encodePathComponent(question))
        }
        guard let url = URL(string: endpoint) else {
            throw ToolRuntimeError.invalidURL
        }
        return url
    }

    private func resolvedTopic(
        for runtimeAction: LocalToolDefinition.RuntimeActionDefinition,
        from result: ScanResult
    ) -> String? {
        if let topicField = runtimeAction.topicField,
           let topic = sanitize(stringValue(for: topicField, in: result), using: "subject"),
           !topic.isEmpty {
            return topic
        }

        if let fallbackStateKey = runtimeAction.fallbackStateKey,
           let topic = result.state?[fallbackStateKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !topic.isEmpty {
            return topic
        }

        return nil
    }

    private func resolvedQuestion(
        for runtimeAction: LocalToolDefinition.RuntimeActionDefinition,
        from result: ScanResult
    ) -> String? {
        guard let questionField = runtimeAction.questionField else { return nil }
        return stringValue(for: questionField, in: result)
    }

    private func resolvedPluginArguments(
        _ arguments: [String: String],
        result: ScanResult
    ) -> [String: String] {
        arguments.mapValues { template in
            resolveTemplate(template, result: result)
        }
    }

    private func resolveTemplate(_ template: String, result: ScanResult) -> String {
        var resolved = template
        let pattern = #"\{([A-Za-z0-9_ -]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return resolved
        }

        let matches = regex.matches(in: template, range: NSRange(template.startIndex..., in: template))
        for match in matches.reversed() {
            guard let placeholderRange = Range(match.range(at: 0), in: resolved),
                  let keyRange = Range(match.range(at: 1), in: template) else {
                continue
            }
            let key = String(template[keyRange])
            let value = stringValue(for: key, in: result) ?? ""
            resolved.replaceSubrange(placeholderRange, with: value)
        }
        return resolved
    }

    private func stringValue(for key: String, in result: ScanResult) -> String? {
        guard let field = result.richFields[key] else { return nil }
        switch field {
        case .string(let string):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .list(let items):
            let first = items.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (first?.isEmpty == false) ? first : nil
        }
    }

    private func sanitize(_ value: String?, using sanitizer: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        switch sanitizer {
        case "subject":
            if let quoted = firstQuotedPhrase(in: value), !quoted.isEmpty {
                value = quoted
            }

            value = value.replacingOccurrences(
                of: #"(?i)\b(document|image|photo|picture|logo|sign|label|text|page|receipt)\b"#,
                with: "",
                options: .regularExpression
            )
            value = value.replacingOccurrences(
                of: #"(?i)\b(bank\s+document|document\s+image|mailing\s+label|address\s+label)\b"#,
                with: "",
                options: .regularExpression
            )
            value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: " -_,.:;"))
            return value.isEmpty ? nil : value
        default:
            return value
        }
    }

    private func firstQuotedPhrase(in text: String) -> String? {
        let patterns = [
            #""([^"]+)""#,
            #"“([^”]+)”"#,
            #"'([^']+)'"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func parseJSONObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolRuntimeError.invalidResponse
        }
        return object
    }

    private func string(at path: String?, in object: [String: Any]) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return value(at: path, in: object) as? String
    }

    private func array(at path: String?, in object: [String: Any]) -> [[String: Any]] {
        guard let path, !path.isEmpty else { return [] }
        return value(at: path, in: object) as? [[String: Any]] ?? []
    }

    private func value(at path: String, in root: [String: Any]) -> Any? {
        let components = path.split(separator: ".").map(String.init)
        var current: Any = root

        for component in components {
            if let dictionary = current as? [String: Any] {
                guard let next = dictionary[component] else { return nil }
                current = next
            } else if let array = current as? [Any],
                      let index = Int(component),
                      array.indices.contains(index) {
                current = array[index]
            } else {
                return nil
            }
        }

        return current
    }

    private func sectionBodies(
        at sectionsPath: String?,
        bodyKey: String,
        in object: [String: Any]
    ) -> [String] {
        array(at: sectionsPath, in: object)
            .compactMap { $0[bodyKey] as? String }
            .compactMap(plainText(fromHTML:))
            .map(normalizeText(_:))
            .filter { !$0.isEmpty }
    }

    private func rankedSectionText(
        request: LocalToolDefinition.RuntimeRequestDefinition,
        object: [String: Any],
        topic: String?,
        question: String?
    ) -> String {
        let sections = array(at: request.sectionsPath, in: object)
        let ranked = rankSections(
            sections,
            titleKey: request.sectionTitleKey ?? "line",
            bodyKey: request.sectionBodyKey ?? "text",
            question: question
        )

        var blocks: [String] = ranked.prefix(max(1, request.maxSections ?? 3)).compactMap { section in
            guard let title = section[request.sectionTitleKey ?? "line"] as? String,
                  let bodyHTML = section[request.sectionBodyKey ?? "text"] as? String,
                  let body = plainText(fromHTML: bodyHTML).map(normalizeText(_:)),
                  !body.isEmpty else {
                return nil
            }
            return "\(title)\n\(body)"
        }

        if blocks.isEmpty {
            let leadBodies = sectionBodies(
                at: request.leadSectionsPath,
                bodyKey: request.sectionBodyKey ?? "text",
                in: object
            )
            let leadText = leadBodies.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !leadText.isEmpty {
                blocks = [leadText]
            }
        }

        let intro = renderIntroTemplate(
            request.introTemplate,
            topic: topic,
            question: question
        )

        let introValue = intro.trimmingCharacters(in: .whitespacesAndNewlines)
        return ([introValue.isEmpty ? nil : introValue] + blocks)
            .compactMap { $0 }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func renderIntroTemplate(_ template: String?, topic: String?, question: String?) -> String {
        guard var template else { return "" }
        let questionClause = (question?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? " for \"\(question!.trimmingCharacters(in: .whitespacesAndNewlines))\""
            : ""
        template = template.replacingOccurrences(of: "{topic}", with: topic ?? "")
        template = template.replacingOccurrences(of: "{question}", with: question ?? "")
        template = template.replacingOccurrences(of: "{question_clause}", with: questionClause)
        return template
    }

    private func rankSections(
        _ sections: [[String: Any]],
        titleKey: String,
        bodyKey: String,
        question: String?
    ) -> [[String: Any]] {
        let keywords = questionKeywords(from: question)
        guard !keywords.isEmpty else { return sections }

        return sections.sorted { lhs, rhs in
            let leftScore = sectionScore(lhs, titleKey: titleKey, bodyKey: bodyKey, keywords: keywords)
            let rightScore = sectionScore(rhs, titleKey: titleKey, bodyKey: bodyKey, keywords: keywords)
            if leftScore == rightScore {
                let leftLevel = lhs["tocLevel"] as? Int ?? Int.max
                let rightLevel = rhs["tocLevel"] as? Int ?? Int.max
                return leftLevel < rightLevel
            }
            return leftScore > rightScore
        }
    }

    private func questionKeywords(from question: String?) -> [String] {
        guard let question else { return [] }
        let stopWords: Set<String> = [
            "the", "a", "an", "about", "tell", "me", "more", "detail", "details", "what",
            "when", "where", "who", "why", "how", "is", "are", "was", "were", "of", "for",
            "to", "on", "in", "and", "please", "can", "you"
        ]

        return question
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopWords.contains($0) }
    }

    private func sectionScore(
        _ section: [String: Any],
        titleKey: String,
        bodyKey: String,
        keywords: [String]
    ) -> Int {
        let title = (section[titleKey] as? String ?? "").lowercased()
        let body = plainText(fromHTML: section[bodyKey] as? String ?? "")?.lowercased() ?? ""
        let haystack = "\(title) \(body)"

        return keywords.reduce(into: 0) { score, keyword in
            if haystack.contains(keyword) {
                score += title.contains(keyword) ? 4 : 1
            }
        }
    }

    private func plainText(fromHTML html: String) -> String? {
        guard !html.isEmpty else { return nil }

        var text = html
        let blockTags: [(String, String)] = [
            (#"(?i)<br\s*/?>"#, "\n"),
            (#"(?i)</p>"#, "\n\n"),
            (#"(?i)</div>"#, "\n"),
            (#"(?i)</li>"#, "\n"),
            (#"(?i)</h[1-6]>"#, "\n\n")
        ]

        for (pattern, replacement) in blockTags {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }

        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = decodeHTMLEntities(in: text)
        text = text.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return text.isEmpty ? nil : text
    }

    private func decodeHTMLEntities(in text: String) -> String {
        let namedEntities: [String: String] = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&quot;": "\"",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&#39;": "'",
            "&#34;": "\"",
            "&#160;": " "
        ]

        var decoded = text
        for (entity, replacement) in namedEntities {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }

        if let regex = try? NSRegularExpression(pattern: #"&#(\d+);"#) {
            let matches = regex.matches(in: decoded, range: NSRange(decoded.startIndex..., in: decoded)).reversed()
            for match in matches {
                guard let range = Range(match.range(at: 1), in: decoded),
                      let scalarValue = UInt32(decoded[range]),
                      let scalar = UnicodeScalar(scalarValue),
                      let wholeRange = Range(match.range(at: 0), in: decoded) else {
                    continue
                }
                decoded.replaceSubrange(wholeRange, with: String(Character(scalar)))
            }
        }

        if let hexRegex = try? NSRegularExpression(pattern: #"&#x([0-9A-Fa-f]+);"#) {
            let matches = hexRegex.matches(in: decoded, range: NSRange(decoded.startIndex..., in: decoded)).reversed()
            for match in matches {
                guard let range = Range(match.range(at: 1), in: decoded),
                      let scalarValue = UInt32(decoded[range], radix: 16),
                      let scalar = UnicodeScalar(scalarValue),
                      let wholeRange = Range(match.range(at: 0), in: decoded) else {
                    continue
                }
                decoded.replaceSubrange(wholeRange, with: String(Character(scalar)))
            }
        }

        return decoded
    }

    private func normalizeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func encodePathComponent(_ value: String) -> String {
        let slug = value.replacingOccurrences(of: " ", with: "_")
        return slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
    }
}

private enum ToolRuntimeError: Error {
    case missingTopic
    case invalidURL
    case requestFailed
    case invalidResponse
}

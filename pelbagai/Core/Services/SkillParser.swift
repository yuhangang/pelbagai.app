import Foundation
import OSLog

/// Parses `.md` skill files into `Skill` instances.
///
/// Both chat skills and tool skills use the same markdown format:
/// - YAML frontmatter (between `---` delimiters) for identity and config
/// - Body content interpreted based on `type:` in frontmatter
///
/// Chat skills: body = instructions text + optional ```html block
/// Tool skills: body = briefing prose + structured ## sections
struct SkillParser {
    private static let logger = Logger(subsystem: "com.pelbagai", category: "SkillParser")

    // MARK: - Public API

    /// Parse a skill from markdown content.
    /// Returns nil if the markdown is unparseable or missing required fields.
    static func parse(from markdown: String, isBuiltIn: Bool = false, fallbackName: String = "imported_skill") -> Skill? {
        let lines = markdown.components(separatedBy: "\n")
        let frontmatter = parseFrontmatter(lines: lines)
        let bodyLines = extractBody(lines: lines)
        let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        // Determine name
        let name = frontmatter["name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? fallbackName
        guard !name.isEmpty else {
            logger.warning("SkillParser: No name found in frontmatter")
            return nil
        }

        // Determine type
        let typeStr = frontmatter["type"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "chat"
        let type: SkillType = typeStr == "tool" ? .tool : .chat

        // Parse shared fields
        let description = frontmatter["description"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let icon = frontmatter["icon"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? Skill.defaultIcon(for: name)
        let color = frontmatter["color"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? Skill.defaultColor(for: name)
        let capabilities = parseCapabilities(frontmatter["capabilities"])
        let keywords = parseStringList(frontmatter["keywords"])
        let chainTo = parseStringList(frontmatter["chainTo"] ?? frontmatter["chainto"])
        let suggestedPrompts = parseStringList(frontmatter["suggestedPrompts"] ?? frontmatter["suggestedprompts"])
        let urlTemplate = frontmatter["urlTemplate"] ?? frontmatter["urltemplate"]
        let version = frontmatter["version"]
        let categoryStr = frontmatter["category"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let category: SkillCategory? = categoryStr.flatMap { SkillCategory(rawValue: $0) }

        // Parse HTML content (shared between both types)
        let htmlContent = parseHTMLBlock(from: markdown)

        switch type {
        case .chat:
            // Chat skill: body (minus HTML block) = instructions
            let instructions = extractInstructions(from: body, htmlContent: htmlContent)

            let displayName = frontmatter["displayName"]
                ?? name.replacingOccurrences(of: "-", with: " ")
                       .replacingOccurrences(of: "_", with: " ")
                       .capitalized

            return Skill(
                name: name,
                displayName: displayName,
                description: description.isEmpty ? "Specialized assistant skill." : description,
                type: .chat,
                icon: icon,
                color: color,
                isBuiltIn: isBuiltIn,
                version: version,
                capabilities: capabilities,
                keywords: keywords,
                category: category,
                instructions: instructions.isEmpty ? body : instructions,
                htmlContent: htmlContent
            )

        case .tool:
            // Tool skill: body = briefing + structured sections
            let sections = parseSections(from: bodyLines)
            let briefing = extractBriefing(from: bodyLines)
            let fields = parseFieldsTable(sections["Fields"] ?? sections["fields"] ?? "")
            let rules = parseRulesList(sections["Rules"] ?? sections["rules"] ?? "")
            let prompt = (sections["Prompt"] ?? sections["prompt"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let examples = parseExamples(sections["Examples"] ?? sections["examples"] ?? "")
            let stateSchema = parseStateTable(sections["State"] ?? sections["state"] ?? "")
            let stateBridges = parseStateBridgesYAML(sections["State Bridges"] ?? sections["state bridges"] ?? "")
            let runtimeActions = parseRuntimeActionsYAML(sections["Actions"] ?? sections["actions"] ?? "")
            let workflow = parseWorkflowSection(sections["Workflow"] ?? sections["workflow"] ?? "")
            let transformScript = parseJavaScriptBlock(sections["Script"] ?? sections["script"] ?? "")

            // Build outputSchema from fields for backward compat
            var outputSchema: [String: String] = [:]
            for field in fields {
                let typeStr = field.type == .list ? "list of strings" : "string"
                outputSchema[field.name] = typeStr
            }

            // Build legacy stateSchema dict
            var legacyStateSchema: [String: String] = [:]
            for state in stateSchema {
                legacyStateSchema[state.key] = state.type
            }

            let displayName = frontmatter["displayName"]
                ?? name.replacingOccurrences(of: "-", with: " ")
                       .replacingOccurrences(of: "_", with: " ")
                       .capitalized

            return Skill(
                name: name,
                displayName: displayName,
                description: description,
                type: .tool,
                icon: icon,
                color: color,
                isBuiltIn: isBuiltIn,
                version: version,
                capabilities: capabilities,
                keywords: keywords,
                category: category,
                briefing: briefing.isEmpty ? nil : briefing,
                fields: fields.isEmpty ? nil : fields,
                rules: rules.isEmpty ? nil : rules,
                prompt: prompt.isEmpty ? nil : prompt,
                examples: examples.isEmpty ? nil : examples,
                stateSchema: stateSchema.isEmpty ? nil : stateSchema,
                stateBridges: stateBridges,
                runtimeActions: runtimeActions,
                chainTo: chainTo,
                workflow: workflow,
                transformScript: transformScript,
                suggestedPrompts: suggestedPrompts,
                urlTemplate: urlTemplate,
                outputSchema: outputSchema.isEmpty ? nil : outputSchema,
                inputSchema: capabilities.contains(.camera) || capabilities.contains(.scanImage)
                    ? ["image": "CIImage"] : nil,
                legacyStateSchema: legacyStateSchema.isEmpty ? nil : legacyStateSchema
            )
        }
    }

    // MARK: - Frontmatter Parsing

    /// Extract YAML frontmatter key-value pairs from between --- delimiters.
    static func parseFrontmatter(lines: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var inFrontmatter = false
        var foundStart = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "---" {
                if !foundStart {
                    foundStart = true
                    inFrontmatter = true
                    continue
                } else {
                    break
                }
            }
            if inFrontmatter {
                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                if parts.count == 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    result[key] = value
                }
            }
        }
        return result
    }

    /// Lines after the frontmatter closing ---.
    static func extractBody(lines: [String]) -> [String] {
        var dashCount = 0
        var bodyStart = 0
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
                dashCount += 1
                if dashCount == 2 {
                    bodyStart = i + 1
                    break
                }
            }
        }
        if dashCount < 2 { return lines }
        return Array(lines[bodyStart...])
    }

    // MARK: - HTML Block

    /// Extract the first ```html ... ``` code block from the full markdown.
    static func parseHTMLBlock(from markdown: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "```html\\s*([\\s\\S]*?)\\s*```", options: []) else {
            return nil
        }
        let nsString = markdown as NSString
        if let match = regex.firstMatch(in: markdown, options: [], range: NSRange(location: 0, length: nsString.length)) {
            let content = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? nil : content
        }
        return nil
    }

    // MARK: - Chat Skill Parsing

    /// Extract instructions text, removing the HTML block if present.
    static func extractInstructions(from body: String, htmlContent: String?) -> String {
        var text = body
        if let _ = htmlContent {
            // Remove the ```html ... ``` block from instructions
            if let regex = try? NSRegularExpression(pattern: "```html\\s*[\\s\\S]*?\\s*```", options: []) {
                text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "")
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tool Skill Section Parsing

    /// Split body into named sections by ## headings.
    static func parseSections(from bodyLines: [String]) -> [String: String] {
        var sections: [String: String] = [:]
        var currentSection: String?
        var currentContent: [String] = []

        for line in bodyLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("## ") {
                // Save previous section
                if let section = currentSection {
                    sections[section] = currentContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                currentSection = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                currentContent = []
            } else if currentSection != nil {
                currentContent.append(line)
            }
        }
        // Save last section
        if let section = currentSection {
            sections[section] = currentContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return sections
    }

    /// Extract briefing text — prose before the first ## heading.
    static func extractBriefing(from bodyLines: [String]) -> String {
        var briefingLines: [String] = []
        for line in bodyLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("## ") { break }
            // Skip the # title if present
            if trimmed.hasPrefix("# ") { continue }
            briefingLines.append(line)
        }
        return briefingLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parse a markdown table into field definitions.
    /// Expected format: | Field | Type | Required |
    static func parseFieldsTable(_ section: String) -> [SkillFieldDefinition] {
        let lines = section.components(separatedBy: "\n")
        var fields: [SkillFieldDefinition] = []
        var headerParsed = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("|") else { continue }

            // Skip separator row (|---|---|...)
            if trimmed.contains("---") {
                headerParsed = true
                continue
            }

            // Skip header row
            if !headerParsed {
                headerParsed = false // will be set by separator
                continue
            }

            let cells = trimmed.split(separator: "|").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard cells.count >= 2 else { continue }

            let name = cells[0]
            guard !name.isEmpty && name.lowercased() != "field" else { continue }

            let typeStr = cells.count > 1 ? cells[1] : "text"
            let requiredStr = cells.count > 2 ? cells[2].lowercased() : "no"

            let fieldType = SkillFieldDefinition.FieldDataType(rawValue: typeStr.lowercased())
                ?? SkillFieldDefinition.FieldDataType.from(schemaType: typeStr)

            fields.append(SkillFieldDefinition(
                name: name,
                type: fieldType,
                required: requiredStr == "yes" || requiredStr == "true"
            ))
        }
        return fields
    }

    /// Parse bullet list into array of strings.
    static func parseRulesList(_ section: String) -> [String] {
        section.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("- ") || $0.hasPrefix("* ") }
            .map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Parse examples section. Looks for ### Example N headers with tables below.
    static func parseExamples(_ section: String) -> [[String: FieldValue]] {
        let lines = section.components(separatedBy: "\n")
        var examples: [[String: FieldValue]] = []
        var currentExample: [String: FieldValue] = [:]
        var inExample = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("### ") {
                if inExample && !currentExample.isEmpty {
                    examples.append(currentExample)
                }
                currentExample = [:]
                inExample = true
                continue
            }

            guard inExample, trimmed.hasPrefix("|") else { continue }
            guard !trimmed.contains("---") else { continue }

            let cells = trimmed.split(separator: "|").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard cells.count >= 2 else { continue }

            let field = cells[0]
            let value = cells[1]
            guard !field.isEmpty, field.lowercased() != "field" else { continue }

            // Detect list values (comma-separated)
            if value.contains(", ") && !value.hasPrefix("$") && !value.hasPrefix("€") {
                let items = value.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if items.count > 1 {
                    currentExample[field] = .list(items)
                    continue
                }
            }
            currentExample[field] = .string(value)
        }

        if inExample && !currentExample.isEmpty {
            examples.append(currentExample)
        }

        return examples
    }

    /// Parse state schema table.
    /// Expected format: | Key | Type | Description |
    static func parseStateTable(_ section: String) -> [SkillStateFieldDef] {
        let lines = section.components(separatedBy: "\n")
        var states: [SkillStateFieldDef] = []
        var headerParsed = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("|") else { continue }
            if trimmed.contains("---") { headerParsed = true; continue }
            if !headerParsed { continue }

            let cells = trimmed.split(separator: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard cells.count >= 2 else { continue }
            let key = cells[0]
            guard !key.isEmpty, key.lowercased() != "key" else { continue }
            let type = cells.count > 1 ? cells[1] : "text"
            let desc = cells.count > 2 ? cells[2] : nil

            states.append(SkillStateFieldDef(key: key, type: type, description: desc))
        }
        return states
    }

    /// Extract a ```javascript code block.
    static func parseJavaScriptBlock(_ section: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "```javascript\\s*([\\s\\S]*?)\\s*```", options: []) else {
            return nil
        }
        let nsString = section as NSString
        if let match = regex.firstMatch(in: section, options: [], range: NSRange(location: 0, length: nsString.length)) {
            let content = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? nil : content
        }
        return nil
    }

    /// Extract a ```yaml code block.
    static func parseYAMLBlock(_ section: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "```yaml\\s*([\\s\\S]*?)\\s*```", options: []) else {
            return nil
        }
        let nsString = section as NSString
        if let match = regex.firstMatch(in: section, options: [], range: NSRange(location: 0, length: nsString.length)) {
            let content = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? nil : content
        }
        return nil
    }

    // MARK: - Advanced Config Parsing (YAML blocks)

    /// Parse state bridges from a YAML block.
    /// These are currently stored as JSON-compatible structures, so we parse
    /// the YAML block as JSON since our YAML subset is JSON-compatible.
    static func parseStateBridgesYAML(_ section: String) -> [LocalToolDefinition.StateBridgeDefinition]? {
        guard let yaml = parseYAMLBlock(section) else { return nil }
        // Try JSON decode (our YAML subset is JSON-compatible for arrays)
        guard let data = "[\(yaml)]".data(using: .utf8),
              let bridges = try? JSONDecoder().decode([LocalToolDefinition.StateBridgeDefinition].self, from: data) else {
            // Fall back to line-by-line YAML parsing
            return parseStateBridgesFromLines(yaml)
        }
        return bridges.isEmpty ? nil : bridges
    }

    /// Simple line-by-line state bridge parser for YAML format.
    private static func parseStateBridgesFromLines(_ yaml: String) -> [LocalToolDefinition.StateBridgeDefinition]? {
        // Parse simple YAML entries like:
        // - field: topic
        //   stateKey: last_topic
        //   fallbackToState: true
        //   persistToState: true
        //   sanitizer: subject
        let lines = yaml.components(separatedBy: "\n")
        var bridges: [LocalToolDefinition.StateBridgeDefinition] = []
        var current: [String: String] = [:]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("- ") {
                if !current.isEmpty {
                    if let bridge = bridgeFromDict(current) { bridges.append(bridge) }
                }
                current = [:]
                let rest = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let (k, v) = parseYAMLKeyValue(rest) { current[k] = v }
            } else if !trimmed.isEmpty {
                if let (k, v) = parseYAMLKeyValue(trimmed) { current[k] = v }
            }
        }
        if !current.isEmpty {
            if let bridge = bridgeFromDict(current) { bridges.append(bridge) }
        }
        return bridges.isEmpty ? nil : bridges
    }

    private static func bridgeFromDict(_ dict: [String: String]) -> LocalToolDefinition.StateBridgeDefinition? {
        guard let field = dict["field"], let stateKey = dict["stateKey"] else { return nil }
        return LocalToolDefinition.StateBridgeDefinition(
            field: field,
            stateKey: stateKey,
            fallbackToState: dict["fallbackToState"]?.lowercased() == "true",
            persistToState: dict["persistToState"]?.lowercased() == "true",
            sanitizer: dict["sanitizer"]
        )
    }

    /// Parse runtime actions from YAML block.
    /// Returns nil if no valid actions found.
    static func parseRuntimeActionsYAML(_ section: String) -> [String: LocalToolDefinition.RuntimeActionDefinition]? {
        guard let yaml = parseYAMLBlock(section) else { return nil }
        // Try JSON decode first
        if let data = "{\(yaml)}".data(using: .utf8),
           let actions = try? JSONDecoder().decode([String: LocalToolDefinition.RuntimeActionDefinition].self, from: data) {
            return actions.isEmpty ? nil : actions
        }
        // Fall back to line-by-line parsing for simple YAML
        return parseRuntimeActionsFromLines(yaml)
    }

    /// Simple runtime action YAML parser.
    private static func parseRuntimeActionsFromLines(_ yaml: String) -> [String: LocalToolDefinition.RuntimeActionDefinition]? {
        // This handles the common case of simple runtime actions.
        // Complex nested runtime actions should use JSON blocks instead.
        let lines = yaml.components(separatedBy: "\n")
        var actions: [String: LocalToolDefinition.RuntimeActionDefinition] = [:]
        var currentActionName: String?
        var currentDict: [String: String] = [:]
        var currentRequestDict: [String: String] = [:]
        var inRequest = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let indent = line.prefix(while: { $0 == " " }).count

            if indent == 0 && trimmed.hasSuffix(":") {
                // Save previous action
                if let name = currentActionName {
                    actions[name] = buildRuntimeAction(from: currentDict, request: currentRequestDict)
                }
                currentActionName = String(trimmed.dropLast())
                currentDict = [:]
                currentRequestDict = [:]
                inRequest = false
            } else if indent >= 2 {
                if trimmed == "request:" {
                    inRequest = true
                } else if let (k, v) = parseYAMLKeyValue(trimmed) {
                    if inRequest {
                        currentRequestDict[k] = v
                    } else {
                        currentDict[k] = v
                    }
                }
            }
        }
        if let name = currentActionName {
            actions[name] = buildRuntimeAction(from: currentDict, request: currentRequestDict)
        }
        return actions.isEmpty ? nil : actions
    }

    private static func buildRuntimeAction(from dict: [String: String], request reqDict: [String: String]) -> LocalToolDefinition.RuntimeActionDefinition {
        var request: LocalToolDefinition.RuntimeRequestDefinition?
        if let endpoint = reqDict["endpoint"] ?? reqDict["endpointTemplate"] {
            let modeStr = reqDict["responseMode"] ?? "text_path"
            let mode = LocalToolDefinition.RuntimeRequestDefinition.ResponseMode(rawValue: modeStr) ?? .textPath
            request = LocalToolDefinition.RuntimeRequestDefinition(
                endpointTemplate: endpoint,
                responseMode: mode,
                textPath: reqDict["textPath"],
                imageURLPath: reqDict["imageURLPath"],
                sectionsPath: reqDict["sectionsPath"],
                sectionTitleKey: reqDict["sectionTitleKey"],
                sectionBodyKey: reqDict["sectionBodyKey"],
                leadSectionsPath: reqDict["leadSectionsPath"],
                maxSections: reqDict["maxSections"].flatMap { Int($0) },
                introTemplate: reqDict["introTemplate"]
            )
        }
        return LocalToolDefinition.RuntimeActionDefinition(
            topicField: dict["topicField"],
            questionField: dict["questionField"],
            fallbackStateKey: dict["fallbackStateKey"],
            request: request,
            fallbackRequest: nil,
            plugin: nil
        )
    }

    /// Parse workflow section — looks for ```yaml config and ```javascript script.
    static func parseWorkflowSection(_ section: String) -> LocalToolDefinition.WorkflowDefinition? {
        guard let yaml = parseYAMLBlock(section) else { return nil }
        let script = parseJavaScriptBlock(section)

        // Parse workflow config from YAML
        var triggerSourceToolIDs: [String] = []
        var triggerKeywords: [String] = []
        var inputToolIDs: [String] = []
        var saveLatestSourceResult = false

        for line in yaml.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let (key, value) = parseYAMLKeyValue(trimmed) {
                switch key {
                case "triggerSourceToolIDs": triggerSourceToolIDs = parseInlineList(value)
                case "triggerKeywords": triggerKeywords = parseInlineList(value)
                case "inputToolIDs": inputToolIDs = parseInlineList(value)
                case "saveLatestSourceResult": saveLatestSourceResult = value.lowercased() == "true"
                default: break
                }
            }
        }

        guard !triggerSourceToolIDs.isEmpty else { return nil }

        return LocalToolDefinition.WorkflowDefinition(
            triggerSourceToolIDs: triggerSourceToolIDs,
            triggerKeywords: triggerKeywords,
            inputToolIDs: inputToolIDs,
            saveLatestSourceResult: saveLatestSourceResult,
            transformScript: script ?? ""
        )
    }

    // MARK: - Utility Helpers

    /// Parse a YAML-style key: value pair.
    private static func parseYAMLKeyValue(_ line: String) -> (String, String)? {
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return (key, value)
    }

    /// Parse a bracketed list like [a, b, c] from a frontmatter value.
    static func parseStringList(_ value: String?) -> [String]? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return parseInlineList(value)
    }

    /// Parse [a, b, c] or a, b, c into array.
    static func parseInlineList(_ value: String) -> [String] {
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return cleaned
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Parse capabilities from frontmatter value.
    static func parseCapabilities(_ value: String?) -> Set<SkillCapability> {
        guard let list = parseStringList(value) else { return [] }
        return Set(list.compactMap { SkillCapability(rawValue: $0) })
    }
}

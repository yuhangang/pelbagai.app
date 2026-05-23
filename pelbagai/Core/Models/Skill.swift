import Foundation
import SwiftUI

// MARK: - Skill Type

/// Determines which frontend experience renders this skill.
/// Chat skills flow through ChatView; tool skills flow through ToolSkillView.
enum SkillType: String, Codable, Hashable {
    case chat
    case tool
}

// MARK: - Skill Capability

/// Declared capabilities that a skill can use.
/// The runtime checks these before granting access to services.
enum SkillCapability: String, Codable, Hashable {
    // Input
    case camera
    case photoLibrary
    case fileImport

    // Processing
    case exportCSV = "export_csv"
    case persistentState = "persistent_state"
    case openURL = "open_url"
    case htmlView = "html_view"
    case canvas
    case vectorSearch = "vector_search"
    case chatbot
    case javascript
    case openWebpage
    case workflow
    case fileStorage

    // Compatibility aliases for JSON parsing
    case scanImage = "scan_image"
}

// MARK: - Skill Category

/// Visual grouping for the skills dashboard.
enum SkillCategory: String, Codable, CaseIterable, Hashable {
    case scanner
    case assistant
    case productivity
    case media
    case utility
    case integration
    case custom
}

// MARK: - Field Definition

/// A field definition for tool-type skills. Parsed from ## Fields tables.
struct SkillFieldDefinition: Codable, Equatable, Hashable {
    let name: String
    let type: FieldDataType
    let required: Bool

    enum FieldDataType: String, Codable, Hashable {
        case text
        case number
        case currency
        case date
        case url
        case boolean
        case list
        case object
        case image

        /// Map from legacy outputSchema type strings.
        static func from(schemaType: String) -> FieldDataType {
            let lower = schemaType.lowercased()
            if lower.contains("list") { return .list }
            if lower.contains("number") || lower.contains("int") { return .number }
            if lower.contains("currency") || lower.contains("money") { return .currency }
            if lower.contains("date") { return .date }
            if lower.contains("url") || lower.contains("link") { return .url }
            if lower.contains("bool") { return .boolean }
            if lower.contains("image") { return .image }
            if lower.contains("object") || lower.contains("json") { return .object }
            return .text
        }
    }
}

// MARK: - State Field Definition

/// A state field for tool skills with persistent state.
struct SkillStateFieldDef: Codable, Equatable, Hashable {
    let key: String
    let type: String
    let description: String?
}

// MARK: - Skill

/// The unified skill model. Both chat-type and tool-type skills are represented
/// by this single struct. The `type` field determines which frontend renders it,
/// while both types share the same backend infrastructure (SkillRegistry,
/// ToolStorage, ToolScriptRuntime, NativePluginRegistry, etc.).
struct Skill: Identifiable, Codable, Hashable {
    var id: String { name }

    // Custom Hashable by name (identity)
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
    static func == (lhs: Skill, rhs: Skill) -> Bool {
        lhs.name == rhs.name
    }

    // MARK: Shared identity (from YAML frontmatter)

    var name: String
    var displayName: String
    var description: String
    var type: SkillType
    var icon: String
    var color: String
    var isBuiltIn: Bool
    var version: String?
    var capabilities: Set<SkillCapability>
    var keywords: [String]?
    var category: SkillCategory?

    // MARK: Chat skill content

    /// Instructions text prepended to the LLM system prompt when this chat skill
    /// is active. For chat skills, this is the body of the markdown after the
    /// frontmatter (before any HTML block).
    var instructions: String?

    /// Optional interactive HTML widget rendered in a WKWebView.
    /// Uses the `pelbagaiBridge` message handler for Swift ↔ JS communication.
    var htmlContent: String?

    // MARK: Tool skill content (parsed from ## sections)

    /// Briefing text — the prose between the frontmatter and the first ## heading.
    var briefing: String?

    /// Structured field definitions parsed from the ## Fields table.
    var fields: [SkillFieldDefinition]?

    /// Extraction rules as bullet points from ## Rules.
    var rules: [String]?

    /// Model prompt from ## Prompt section.
    var prompt: String?

    /// Few-shot examples from ## Examples section.
    var examples: [[String: FieldValue]]?

    /// State schema from ## State section.
    var stateSchema: [SkillStateFieldDef]?

    /// State bridge definitions for persistent state.
    var stateBridges: [LocalToolDefinition.StateBridgeDefinition]?

    /// Runtime action definitions (HTTP endpoints, plugin invocations).
    var runtimeActions: [String: LocalToolDefinition.RuntimeActionDefinition]?

    /// Tool chaining allowlist.
    var chainTo: [String]?

    /// Workflow definition for multi-tool flows.
    var workflow: LocalToolDefinition.WorkflowDefinition?

    /// JavaScript transform script from ## Script code block.
    var transformScript: String?

    /// Suggested prompts for chatbot-type tools.
    var suggestedPrompts: [String]?

    /// URL template for tools that link to external resources.
    var urlTemplate: String?

    /// Resource path for skill-scoped files.
    var resourcePath: String?

    // MARK: Legacy output schema

    /// Preserved for backward compat with existing code that reads outputSchema.
    var outputSchema: [String: String]?

    /// Preserved for backward compat with existing code that reads inputSchema.
    var inputSchema: [String: String]?

    /// Preserved for backward compat with existing code that reads stateSchema dict.
    var legacyStateSchema: [String: String]?
}

// MARK: - Convenience Accessors

extension Skill {
    /// Whether this skill can scan images (camera or photo library input).
    var canScanImage: Bool {
        capabilities.contains(.camera) || capabilities.contains(.scanImage)
    }

    /// Whether this skill has structured data storage.
    var hasDataTable: Bool {
        fields != nil && !(fields?.isEmpty ?? true)
    }

    /// Resolved UI icon (SF Symbol name).
    var uiIcon: String {
        icon.isEmpty ? Self.defaultIcon(for: name) : icon
    }

    /// Resolved UI color.
    var uiColor: Color {
        Self.resolveColor(color)
    }

    /// Inferred category if not explicitly set.
    var resolvedCategory: SkillCategory {
        if let c = category { return c }
        switch type {
        case .chat: return .assistant
        case .tool:
            if canScanImage { return .scanner }
            if capabilities.contains(.vectorSearch) { return .utility }
            return .productivity
        }
    }
}

// MARK: - Color & Icon Defaults

extension Skill {
    static func resolveColor(_ colorName: String) -> Color {
        switch colorName.lowercased() {
        case "orange": return .orange
        case "blue": return .blue
        case "green": return .green
        case "purple": return .purple
        case "cyan": return .cyan
        case "indigo": return .indigo
        case "teal": return .teal
        case "red": return .red
        case "pink": return .pink
        case "yellow": return .yellow
        case "mint": return .mint
        case "brown": return .brown
        default: return .cyan
        }
    }

    static func defaultIcon(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("wiki") { return "globe.americas.fill" }
        if lower.contains("finance") || lower.contains("money") || lower.contains("budget") { return "dollarsign.circle.fill" }
        if lower.contains("fire") || lower.contains("burn") { return "flame.fill" }
        if lower.contains("law") || lower.contains("legal") { return "gavel.fill" }
        if lower.contains("music") || lower.contains("song") { return "music.note" }
        if lower.contains("health") || lower.contains("medical") { return "heart.text.square.fill" }
        if lower.contains("receipt") { return "receipt" }
        if lower.contains("scan") || lower.contains("camera") { return "camera.viewfinder" }
        if lower.contains("document") || lower.contains("doc") { return "doc.text.fill" }
        if lower.contains("card") || lower.contains("contact") { return "person.crop.rectangle.fill" }
        return "bolt.fill"
    }

    static func defaultColor(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("wiki") { return "cyan" }
        if lower.contains("finance") { return "green" }
        if lower.contains("fire") { return "orange" }
        if lower.contains("legal") { return "purple" }
        if lower.contains("music") { return "pink" }
        if lower.contains("receipt") { return "green" }
        return "blue"
    }
}

// MARK: - Backward Compatibility

extension Skill {
    /// Compatibility shim: delegates to SkillParser.parse().
    /// Callers that used `Skill.parse(from:)` will continue to work.
    static func parse(from markdown: String, fallbackName: String = "imported_skill") -> Skill? {
        SkillParser.parse(from: markdown, isBuiltIn: false, fallbackName: fallbackName)
    }

    /// Non-optional instructions accessor for chat skills.
    /// Returns the instructions text or an empty string.
    var resolvedInstructions: String {
        instructions ?? prompt ?? description
    }

    /// Convenience initializer matching the old chat-skill init signature.
    /// Used by the hardcoded fallback skills in SkillRegistry.
    init(
        name: String,
        displayName: String,
        description: String,
        instructions: String,
        isBuiltIn: Bool = false,
        icon: String = "bolt.fill",
        color: String = "blue",
        htmlContent: String? = nil
    ) {
        self.name = name
        self.displayName = displayName
        self.description = description
        self.type = .chat
        self.icon = icon
        self.color = color
        self.isBuiltIn = isBuiltIn
        self.capabilities = htmlContent != nil ? [.htmlView] : []
        self.instructions = instructions
        self.htmlContent = htmlContent
    }
}

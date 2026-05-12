import Foundation
import SwiftUI
import Combine

// MARK: - FieldValue

/// A field value that can be a simple string or an ordered list of strings.
/// This lets the custom template return rich structured data (e.g. receipt line items).
enum FieldValue: Codable, Equatable {
    case string(String)
    case list([String])
    
    // Encode as a plain string or a JSON array
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .list(let a):   try container.encode(a)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let arr = try? container.decode([String].self) {
            self = .list(arr)
        } else {
            self = .string((try? container.decode(String.self)) ?? "")
        }
    }
    
    /// Flat string representation used for legacy CSV export and display.
    var flatString: String {
        switch self {
        case .string(let s): return s
        case .list(let a):   return a.joined(separator: ", ")
        }
    }
    
    var isEmpty: Bool {
        switch self {
        case .string(let s): return s.isEmpty
        case .list(let a):   return a.isEmpty
        }
    }
    
    var isList: Bool {
        if case .list = self { return true }
        return false
    }
    
    var asList: [String] {
        switch self {
        case .string(let s): return s.isEmpty ? [] : [s]
        case .list(let a):   return a
        }
    }
}

// MARK: - Tool Actions

/// A declarative, Swift-owned action requested by a local tool result.
/// Model output may request an action, but app code decides whether it is valid
/// and when to execute it.
struct ToolAction: Identifiable, Codable, Equatable {
    enum ActionType: String, Codable {
        case openURL
    }
    
    var id: UUID
    var type: ActionType
    var url: String?
    var label: String?
    var requiresUserApproval: Bool
    
    init(
        id: UUID = UUID(),
        type: ActionType,
        url: String? = nil,
        label: String? = nil,
        requiresUserApproval: Bool = true
    ) {
        self.id = id
        self.type = type
        self.url = url
        self.label = label
        self.requiresUserApproval = requiresUserApproval
    }
    
    var summary: String {
        switch type {
        case .openURL:
            return [label, url].compactMap { $0 }.joined(separator: ": ")
        }
    }
}

// MARK: - Tool Registry

/// Central registry for local tool definitions.
/// Loads bundled definitions from LOCAL_TOOLS.json, then applies user-created
/// definitions from Documents so local tool definitions can be created and
/// edited at runtime without modifying the app bundle.
@MainActor
final class ToolRegistry: ObservableObject {
    static let shared = ToolRegistry()
    
    @Published private(set) var definitions: [String: LocalToolDefinition] = [:]
    @Published private(set) var userDefinitions: [String: LocalToolDefinition] = [:]
    @Published private(set) var allDefinitions: [LocalToolDefinition] = []
    
    private var bundledDefinitions: [String: LocalToolDefinition] = [:]
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        loadDefinitions()
    }
    
    private func loadDefinitions() {
        loadBundledDefinitions()
        loadUserDefinitions()
        rebuildDefinitions()
    }
    
    private func loadBundledDefinitions() {
        guard let url = Bundle.main.url(forResource: "LOCAL_TOOLS", withExtension: "json") else {
            print("🛠 ToolRegistry: LOCAL_TOOLS.json not found in bundle")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let defs = try decoder.decode([LocalToolDefinition].self, from: data)
            bundledDefinitions = Dictionary(uniqueKeysWithValues: defs.map { ($0.toolID, $0.normalized()) })
            print("🛠 ToolRegistry: Loaded \(defs.count) tool definitions")
        } catch {
            print("🛠 ToolRegistry: Failed to load definitions: \(error)")
        }
    }
    
    private var userDefinitionsURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("local_tool_definitions.json")
    }
    
    private func loadUserDefinitions() {
        let url = userDefinitionsURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        
        do {
            let data = try Data(contentsOf: url)
            let defs = try decoder.decode([LocalToolDefinition].self, from: data)
            userDefinitions = Dictionary(uniqueKeysWithValues: defs.map { ($0.toolID, $0.normalized()) })
            print("🛠 ToolRegistry: Loaded \(defs.count) user tool definitions")
        } catch {
            print("🛠 ToolRegistry: Failed to load user definitions: \(error)")
        }
    }
    
    private func rebuildDefinitions() {
        definitions = bundledDefinitions.merging(userDefinitions) { _, user in user }
        allDefinitions = definitions.values.sorted { $0.displayName < $1.displayName }
    }
    
    private func persistUserDefinitions() {
        do {
            let defs = userDefinitions.values.sorted { $0.displayName < $1.displayName }
            let data = try encoder.encode(defs)
            try data.write(to: userDefinitionsURL, options: .atomic)
            rebuildDefinitions()
            print("🛠 ToolRegistry: Saved \(defs.count) user tool definitions")
        } catch {
            print("🛠 ToolRegistry: Failed to save user definitions: \(error)")
        }
    }
    
    func definition(for toolID: String) -> LocalToolDefinition? {
        definitions[LocalToolDefinition.normalizedToolID(toolID)]
    }
    
    func isUserDefinition(_ toolID: String) -> Bool {
        userDefinitions[LocalToolDefinition.normalizedToolID(toolID)] != nil
    }
    
    func upsert(_ definition: LocalToolDefinition) {
        let normalized = definition.normalized()
        userDefinitions[normalized.toolID] = normalized
        persistUserDefinitions()
    }
    
    func deleteUserDefinition(toolID: String) {
        userDefinitions.removeValue(forKey: LocalToolDefinition.normalizedToolID(toolID))
        persistUserDefinitions()
    }
    
    func resetUserDefinitions() {
        userDefinitions.removeAll()
        try? FileManager.default.removeItem(at: userDefinitionsURL)
        rebuildDefinitions()
    }
}

/// A small local tool definition. This intentionally models only the pieces
/// Pelbagai needs locally instead of implementing the full MCP transport layer.
struct LocalToolDefinition: Identifiable, Codable, Equatable {
    enum Capability: String, Codable {
        case scanImage = "scan_image"
        case exportCSV = "export_csv"
        case openURL = "open_url"
        case persistentState = "persistent_state"
        case htmlView = "html_view"
    }
    
    struct ActionDefinition: Codable, Equatable {
        enum Effect: String, Codable {
            case store
            case notify
            case open
            case trigger
            case run_js
        }
        var effect: Effect
        var message: String?
        var script: String?
    }

    struct StateBridgeDefinition: Codable, Equatable {
        var field: String
        var stateKey: String
        var fallbackToState: Bool
        var persistToState: Bool
        var sanitizer: String?
    }

    struct RuntimeRequestDefinition: Codable, Equatable {
        enum ResponseMode: String, Codable {
            case textPath = "text_path"
            case htmlLeadSections = "html_lead_sections"
            case rankedHTMLSections = "ranked_html_sections"
        }

        var endpointTemplate: String
        var responseMode: ResponseMode
        var textPath: String?
        var imageURLPath: String?
        var sectionsPath: String?
        var sectionTitleKey: String?
        var sectionBodyKey: String?
        var leadSectionsPath: String?
        var maxSections: Int?
        var introTemplate: String?
    }

    struct PluginInvocationDefinition: Codable, Equatable {
        var pluginID: String
        var capabilityID: String
        var arguments: [String: String]?
        var responseField: String?
        var hiddenContext: Bool?
    }

    struct RuntimeActionDefinition: Codable, Equatable {
        var topicField: String?
        var questionField: String?
        var fallbackStateKey: String?
        var request: RuntimeRequestDefinition?
        var fallbackRequest: RuntimeRequestDefinition?
        var plugin: PluginInvocationDefinition?
    }
    
    var schemaVersion: Int
    var toolID: String
    var displayName: String
    var description: String
    var briefing: String?
    var index: [String]?
    var rules: [String]?
    var prompt: String?
    var inputSchema: [String: String]
    var outputSchema: [String: String]
    var stateSchema: [String: String]
    var capabilities: [Capability]
    var htmlTemplate: String?
    var actions: [String: ActionDefinition]?
    var examples: [[String: String]]?
    var chainTo: [String]?
    var stateBridges: [StateBridgeDefinition]?
    var runtimeActions: [String: RuntimeActionDefinition]?
    var icon: String?
    var color: String?
    
    var id: String { toolID }
    
    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case toolID
        case displayName
        case description
        case briefing
        case index
        case rules
        case prompt
        case inputSchema
        case outputSchema
        case stateSchema
        case capabilities
        case htmlTemplate
        case actions
        case examples
        case chainTo
        case stateBridges
        case runtimeActions
        case icon
        case color
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedToolID = try container.decodeIfPresent(String.self, forKey: .toolID) ?? ""
        let decodedDisplayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? decodedToolID
        
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        toolID = Self.normalizedToolID(decodedToolID.isEmpty ? decodedDisplayName : decodedToolID)
        displayName = decodedDisplayName.isEmpty ? toolID.replacingOccurrences(of: "_", with: " ").capitalized : decodedDisplayName
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        briefing = try container.decodeIfPresent(String.self, forKey: .briefing)
        index = try container.decodeIfPresent([String].self, forKey: .index)
        rules = try container.decodeIfPresent([String].self, forKey: .rules)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        inputSchema = try container.decodeIfPresent([String: String].self, forKey: .inputSchema) ?? ["image": "CIImage"]
        outputSchema = try container.decodeIfPresent([String: String].self, forKey: .outputSchema) ?? [:]
        stateSchema = try container.decodeIfPresent([String: String].self, forKey: .stateSchema) ?? [:]
        capabilities = try container.decodeIfPresent([Capability].self, forKey: .capabilities) ?? []
        htmlTemplate = try container.decodeIfPresent(String.self, forKey: .htmlTemplate)

        actions = try container.decodeIfPresent([String: ActionDefinition].self, forKey: .actions)
        examples = try container.decodeIfPresent([[String: String]].self, forKey: .examples)
        chainTo = try container.decodeIfPresent([String].self, forKey: .chainTo)
        stateBridges = try container.decodeIfPresent([StateBridgeDefinition].self, forKey: .stateBridges)
        runtimeActions = try container.decodeIfPresent([String: RuntimeActionDefinition].self, forKey: .runtimeActions)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        color = try container.decodeIfPresent(String.self, forKey: .color)
    }
    
    init(
        schemaVersion: Int = 1,
        toolID: String,
        displayName: String,
        description: String,
        briefing: String? = nil,
        index: [String]? = nil,
        rules: [String]? = nil,
        prompt: String? = nil,
        inputSchema: [String: String] = [:],
        outputSchema: [String: String] = [:],
        stateSchema: [String: String] = [:],
        capabilities: [Capability] = [],
        htmlTemplate: String? = nil,
        actions: [String: ActionDefinition]? = nil,
        examples: [[String: String]]? = nil,
        chainTo: [String]? = nil,
        stateBridges: [StateBridgeDefinition]? = nil,
        runtimeActions: [String: RuntimeActionDefinition]? = nil,
        icon: String? = nil,
        color: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.toolID = toolID
        self.displayName = displayName
        self.description = description
        self.briefing = briefing
        self.index = index
        self.rules = rules
        self.prompt = prompt
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.stateSchema = stateSchema
        self.capabilities = capabilities
        self.htmlTemplate = htmlTemplate
        self.actions = actions
        self.examples = examples
        self.chainTo = chainTo
        self.stateBridges = stateBridges
        self.runtimeActions = runtimeActions
        self.icon = icon
        self.color = color
    }
    
    static func normalizedToolID(_ rawValue: String) -> String {
        let lowered = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let scalars = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "_"
        }
        let collapsed = String(scalars)
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return collapsed.isEmpty ? "custom_tool" : collapsed
    }
    
    func normalized() -> LocalToolDefinition {
        LocalToolDefinition(
            schemaVersion: schemaVersion,
            toolID: Self.normalizedToolID(toolID),
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? Self.normalizedToolID(toolID).replacingOccurrences(of: "_", with: " ").capitalized
                : displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            briefing: briefing?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            index: index?.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            rules: rules?.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            prompt: prompt?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            inputSchema: inputSchema.isEmpty ? ["image": "CIImage"] : inputSchema,
            outputSchema: outputSchema,
            stateSchema: stateSchema,
            capabilities: capabilities,
            htmlTemplate: htmlTemplate?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            actions: actions,
            examples: examples,
            chainTo: chainTo?.map(Self.normalizedToolID).filter { !$0.isEmpty },
            stateBridges: stateBridges,
            runtimeActions: runtimeActions,
            icon: icon,
            color: color
        )
    }
}

extension LocalToolDefinition {
    var uiIcon: String {
        if let i = icon, !i.isEmpty { return i }
        return "sparkles"
    }
    
    var uiColor: Color {
        if let colorName = color, !colorName.isEmpty {
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
            default: break
            }
        }
        return .cyan
    }
}

// MARK: - Capability UI Metadata

extension LocalToolDefinition.Capability {
    var displayName: String {
        switch self {
        case .scanImage:       return "Scan Image"
        case .exportCSV:       return "Export CSV"
        case .openURL:         return "Open URL"
        case .persistentState: return "Persistent State"
        case .htmlView:        return "Custom View"
        }
    }
    
    var icon: String {
        switch self {
        case .scanImage:       return "camera.viewfinder"
        case .exportCSV:       return "tablecells"
        case .openURL:         return "safari"
        case .persistentState: return "memorychip"
        case .htmlView:        return "globe"
        }
    }
    
    var color: Color {
        switch self {
        case .scanImage:       return .orange
        case .exportCSV:       return .blue
        case .openURL:         return .indigo
        case .persistentState: return .purple
        case .htmlView:        return .cyan
        }
    }
    
    var blockDescription: String {
        switch self {
        case .scanImage:       return "Capture or select images for AI extraction"
        case .exportCSV:       return "Export results to CSV spreadsheet"
        case .openURL:         return "Open validated web links"
        case .persistentState: return "Cross-scan memory and state variables"
        case .htmlView:        return "Interactive custom UI via embedded web view"
        }
    }
}

struct ToolFollowUp: Codable, Equatable {
    var tool: String
    var reason: String?
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

/// Generic data model representing extracted information from a scanned image.
/// Fields are stored as a flexible key-value dictionary of `FieldValue` so any
/// scan template can return strings, lists, scripts, and state.
struct ScanResult: Identifiable, Codable {
    static let currentSchemaVersion = 1
    
    var schemaVersion: Int
    let id: UUID
    var toolID: String
    let template: String
    /// Primary extracted data. Values may be plain strings or ordered lists.
    var richFields: [String: FieldValue]
    var isValidated: Bool
    var validationNotes: String
    var confidence: Double?
    var followUp: ToolFollowUp?
    var timestamp: Date
    
    /// Optional extraction notes embedded in this result (custom template only).
    /// The model outputs `_scriptNotes`; legacy `_script` values decode here as
    /// notes for backward compatibility. This is never executable code.
    var scriptNotes: String?
    
    /// Persistent cross-scan state for the custom template.
    /// Populated from `_state` in the model output and merged into ToolStorage.
    var state: [String: String]?
    
    /// Declarative actions requested by the tool result. Swift validates and
    /// executes these actions; the model never receives execution privileges.
    var actions: [ToolAction]
    
    /// Backward-compatible UI accessor for older call sites and saved records.
    var script: String? {
        get { scriptNotes }
        set { scriptNotes = newValue }
    }
    
    init(
        schemaVersion: Int = ScanResult.currentSchemaVersion,
        id: UUID = UUID(),
        toolID: String? = nil,
        template: String = "",
        richFields: [String: FieldValue] = [:],
        isValidated: Bool = false,
        validationNotes: String = "",
        confidence: Double? = nil,
        followUp: ToolFollowUp? = nil,
        timestamp: Date = Date(),
        script: String? = nil,
        state: [String: String]? = nil,
        actions: [ToolAction] = []
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.toolID = toolID ?? template.lowercased().replacingOccurrences(of: " ", with: "_")
        self.template = template
        self.richFields = richFields
        self.isValidated = isValidated
        self.validationNotes = validationNotes
        self.confidence = confidence
        self.followUp = followUp
        self.timestamp = timestamp
        self.scriptNotes = script
        self.state = state
        self.actions = actions
    }
    
    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case toolID
        case template
        case richFields
        case isValidated
        case validationNotes
        case confidence
        case followUp
        case timestamp
        case scriptNotes
        case script
        case state
        case actions
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let template = try container.decode(String.self, forKey: .template)
        
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        id = try container.decode(UUID.self, forKey: .id)
        toolID = try container.decodeIfPresent(String.self, forKey: .toolID)
            ?? template.lowercased().replacingOccurrences(of: " ", with: "_")
        self.template = template
        richFields = try container.decode([String: FieldValue].self, forKey: .richFields)
        isValidated = try container.decode(Bool.self, forKey: .isValidated)
        validationNotes = try container.decodeIfPresent(String.self, forKey: .validationNotes) ?? ""
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        followUp = try container.decodeIfPresent(ToolFollowUp.self, forKey: .followUp)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        scriptNotes = try container.decodeIfPresent(String.self, forKey: .scriptNotes)
            ?? container.decodeIfPresent(String.self, forKey: .script)
        state = try container.decodeIfPresent([String: String].self, forKey: .state)
        actions = try container.decodeIfPresent([ToolAction].self, forKey: .actions) ?? []
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ScanResult.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(toolID, forKey: .toolID)
        try container.encode(template, forKey: .template)
        try container.encode(richFields, forKey: .richFields)
        try container.encode(isValidated, forKey: .isValidated)
        try container.encode(validationNotes, forKey: .validationNotes)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encodeIfPresent(followUp, forKey: .followUp)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(scriptNotes, forKey: .scriptNotes)
        try container.encodeIfPresent(state, forKey: .state)
        try container.encode(actions, forKey: .actions)
    }
    
    // MARK: - Legacy flat-string compatibility
    
    /// Legacy accessor — returns flat string values for all richFields.
    /// Used by CSV export and views that haven't migrated to richFields yet.
    var fields: [String: String] {
        get { richFields.mapValues(\.flatString) }
        set { richFields = newValue.mapValues { .string($0) } }
    }
    
    /// Whether the result has at least some extracted data.
    var hasData: Bool {
        richFields.values.contains { !$0.isEmpty }
    }
    
    /// A short summary string for list display.
    var summary: String {
        let nonEmpty = richFields.filter { !$0.value.isEmpty }
        if let first = nonEmpty.first {
            let extra = nonEmpty.count > 1 ? " (+\(nonEmpty.count - 1) fields)" : ""
            return "\(first.value.flatString)\(extra)"
        }
        return "No data extracted"
    }
    
    /// Primary display value (first non-empty field).
    var primaryValue: String {
        richFields.values.first(where: { !$0.isEmpty })?.flatString ?? "—"
    }
    
    /// All field keys sorted alphabetically (excludes internal meta keys).
    var sortedKeys: [String] {
        richFields.keys.sorted()
    }
    
    // MARK: - CSV Support
    
    /// CSV header row using the actual field keys.
    static func csvHeader(for results: [ScanResult]) -> String {
        let allKeys = allFieldKeys(from: results)
        let metaColumns = ["Tool ID", "Template", "Validated", "Notes", "Script Notes", "Actions", "Scanned At"]
        return (allKeys + metaColumns).joined(separator: ",")
    }
    
    /// CSV row representation. Lists are serialised as a quoted, comma-separated string.
    func csvRow(allKeys: [String]) -> String {
        var values: [String] = allKeys.map { key in
            escapeCSV(richFields[key]?.flatString ?? "")
        }
        values.append(escapeCSV(toolID))
        values.append(escapeCSV(template))
        values.append(isValidated ? "Yes" : "No")
        values.append(escapeCSV(validationNotes))
        values.append(escapeCSV(scriptNotes ?? ""))
        values.append(escapeCSV(actions.map(\.summary).joined(separator: "; ")))
        values.append(ISO8601DateFormatter().string(from: timestamp))
        return values.joined(separator: ",")
    }
    
    /// Collects all unique field keys from a batch of results.
    static func allFieldKeys(from results: [ScanResult]) -> [String] {
        var keys = [String]()
        var seen = Set<String>()
        for result in results {
            for key in result.sortedKeys where !seen.contains(key) {
                keys.append(key)
                seen.insert(key)
            }
        }
        return keys
    }
    
    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

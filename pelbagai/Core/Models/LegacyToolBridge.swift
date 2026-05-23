import Foundation

// MARK: - Skill → LocalToolDefinition Bridge

/// Bidirectional conversion between the unified Skill model and the legacy
/// LocalToolDefinition. This bridge keeps existing code that depends on
/// LocalToolDefinition (ToolManager, VisionManager, WorkbenchView, etc.)
/// working during and after the migration.
extension Skill {

    /// Convert a tool-type Skill to a legacy LocalToolDefinition.
    /// Returns nil for chat-type skills (they have no tool definition).
    func toToolDefinition() -> LocalToolDefinition? {
        guard type == .tool else { return nil }

        // Map SkillCapability → LocalToolDefinition.Capability
        let legacyCaps: [LocalToolDefinition.Capability] = capabilities.compactMap { cap in
            switch cap {
            case .scanImage, .camera: return .scanImage
            case .exportCSV:         return .exportCSV
            case .openURL:           return .openURL
            case .persistentState:   return .persistentState
            case .htmlView:          return .htmlView
            case .vectorSearch:      return .vectorSearch
            case .chatbot:           return .chatbot
            default:                 return nil
            }
        }

        // Build outputSchema from fields
        var outSchema: [String: String] = outputSchema ?? [:]
        if outSchema.isEmpty, let fields = fields {
            for field in fields {
                outSchema[field.name] = field.type == .list ? "list of strings" : "string"
            }
        }

        // Build inputSchema
        let inSchema = inputSchema ?? (canScanImage ? ["image": "CIImage"] : [:])

        // Build stateSchema
        let stateDict = legacyStateSchema ?? {
            guard let stateSchema = stateSchema else { return [:] }
            return Dictionary(uniqueKeysWithValues: stateSchema.map { ($0.key, $0.type) })
        }()

        return LocalToolDefinition(
            schemaVersion: 1,
            toolID: name,
            displayName: displayName,
            description: description,
            briefing: briefing,
            index: keywords,
            rules: rules,
            prompt: prompt,
            inputSchema: inSchema,
            outputSchema: outSchema,
            stateSchema: stateDict,
            capabilities: legacyCaps,
            htmlTemplate: htmlContent,
            examples: examples,
            chainTo: chainTo,
            stateBridges: stateBridges,
            runtimeActions: runtimeActions,
            workflow: workflow,
            icon: icon,
            color: color,
            urlTemplate: urlTemplate,
            suggestedPrompts: suggestedPrompts
        )
    }
}

// MARK: - LocalToolDefinition → Skill Bridge

extension Skill {

    /// Create a Skill from a legacy LocalToolDefinition.
    /// This is used to import existing JSON-defined tools into the skill system.
    static func from(definition def: LocalToolDefinition, isBuiltIn: Bool = true) -> Skill {
        // Map legacy capabilities
        var caps = Set<SkillCapability>()
        for cap in def.capabilities {
            switch cap {
            case .scanImage:       caps.insert(.camera); caps.insert(.scanImage)
            case .exportCSV:       caps.insert(.exportCSV)
            case .openURL:         caps.insert(.openURL)
            case .persistentState: caps.insert(.persistentState)
            case .htmlView:        caps.insert(.htmlView)
            case .vectorSearch:    caps.insert(.vectorSearch)
            case .chatbot:         caps.insert(.chatbot)
            }
        }

        // Build field definitions from outputSchema
        let fields: [SkillFieldDefinition]? = def.outputSchema.isEmpty ? nil : def.outputSchema.map { key, value in
            SkillFieldDefinition(
                name: key,
                type: SkillFieldDefinition.FieldDataType.from(schemaType: value),
                required: false
            )
        }.sorted(by: { $0.name < $1.name })

        // Build state schema
        let stateSchema: [SkillStateFieldDef]? = def.stateSchema.isEmpty ? nil : def.stateSchema.map { key, value in
            SkillStateFieldDef(key: key, type: value, description: nil)
        }

        return Skill(
            name: def.toolID,
            displayName: def.displayName,
            description: def.description,
            type: .tool,
            icon: def.icon ?? Skill.defaultIcon(for: def.toolID),
            color: def.color ?? Skill.defaultColor(for: def.toolID),
            isBuiltIn: isBuiltIn,
            capabilities: caps,
            keywords: def.index,
            briefing: def.briefing,
            fields: fields,
            rules: def.rules,
            prompt: def.prompt,
            examples: def.examples,
            stateSchema: stateSchema,
            stateBridges: def.stateBridges,
            runtimeActions: def.runtimeActions,
            chainTo: def.chainTo,
            workflow: def.workflow,
            suggestedPrompts: def.suggestedPrompts,
            urlTemplate: def.urlTemplate,
            outputSchema: def.outputSchema,
            inputSchema: def.inputSchema,
            legacyStateSchema: def.stateSchema
        )
    }
}

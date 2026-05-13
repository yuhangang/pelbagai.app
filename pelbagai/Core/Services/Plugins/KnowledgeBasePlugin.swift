import Foundation

/// A native plugin that implements semantic search across local knowledge.
/// Bridges the 'knowledge_base' chat tool and 'vector_search' capability.
@MainActor
struct KnowledgeBasePlugin: NativePlugin {
    let id = "knowledge_base"
    let displayName = "Knowledge Base"

    var capabilities: [NativePluginCapability] {
        [
            NativePluginCapability(
                id: "vector_search",
                displayName: "Vector Search",
                description: "Perform semantic search across vectorized local documents.",
                argumentSchema: ["query": "The search query or question"],
                requiresUserApproval: false
            )
        ]
    }

    var chatTools: [NativeChatTool] {
        [
            NativeChatTool(
                name: "knowledge_base",
                displayName: "Knowledge Base",
                description: "Use to find reliable survival tips, technical guides, or historical facts from local knowledge base.",
                pluginID: id,
                capabilityID: "vector_search"
            )
        ]
    }

    func execute(capabilityID: String, arguments: [String: String]) async throws -> NativePluginResult {
        switch capabilityID {
        case "vector_search":
            return try await performSearch(query: arguments["query"] ?? "")
        default:
            throw NativePluginError.unknownCapability(pluginID: id, capabilityID: capabilityID)
        }
    }

    private func performSearch(query: String) async throws -> NativePluginResult {
        let normalizedQuery = query.lowercased()
        
        // Mock data representing the "survival tips" archive
        let knowledge = [
            "Jungle Survival: Prioritize finding a water source and building a shelter before nightfall. Signals like smoke or mirrors can help rescuers find you.",
            "Water Procurement: Look for vines like the Water Vine (Cissus), or collect rainwater using large leaves. Boiling water is essential to avoid parasites.",
            "Shelter: Build an A-frame shelter using large palm leaves for rain protection. Keep the floor elevated to avoid dampness and insects.",
            "Signaling: A small mirror or even a polished tin can can reflect sunlight for miles. Use three of anything (fires, whistles, flashes) as the international SOS signal.",
            "Fire Making: Use dry bamboo shavings as tinder. Bamboo-on-bamboo friction is an effective way to start a fire in the jungle.",
            "Navigation: If lost, follow streams downhill; they usually lead to larger rivers and eventual human settlement."
        ]
        
        let results = knowledge.filter { entry in
            let terms = normalizedQuery.split(separator: " ").filter { $0.count > 3 }
            return terms.isEmpty || terms.contains { entry.lowercased().contains($0) }
        }
        
        if results.isEmpty {
            return NativePluginResult(summary: "No specific match found in the knowledge base for '\(query)'. Advice: stay calm and stay put if you are lost.")
        }
        
        let summary = results.joined(separator: "\n\n")
        return NativePluginResult(summary: "Found in Knowledge Base:\n\n\(summary)")
    }
}

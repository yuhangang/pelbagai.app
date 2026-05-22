import Foundation

@MainActor
struct WorkflowPlugin: NativePlugin {
    let id = "workflow"
    let displayName = "Workflow"

    var capabilities: [NativePluginCapability] {
        [
            NativePluginCapability(
                id: "run_tool_workflow",
                displayName: "Run Tool Workflow",
                description: "Run a JSON-configured local tool workflow by target tool ID.",
                argumentSchema: [
                    "target_tool_id": "The workflow target tool ID, for example expense_report.",
                    "reason": "Short user-facing reason for running the workflow."
                ],
                requiresUserApproval: false
            )
        ]
    }

    var chatTools: [NativeChatTool] {
        [
            NativeChatTool(
                name: "run_tool_workflow",
                displayName: "Run Workflow",
                description: "Use when the user asks to run a configured workflow such as generating a report or chart from saved tool data.",
                pluginID: id,
                capabilityID: "run_tool_workflow"
            )
        ]
    }

    func execute(capabilityID: String, arguments: [String: String]) async throws -> NativePluginResult {
        switch capabilityID {
        case "run_tool_workflow":
            let targetToolID = LocalToolDefinition.normalizedToolID(arguments["target_tool_id"] ?? "")
            let rawReason = arguments["reason"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let reason = rawReason.isEmpty ? "Run configured workflow" : rawReason

            guard let definition = ToolRegistry.shared.definition(for: targetToolID),
                  definition.workflow != nil else {
                return NativePluginResult(summary: "No configured workflow found for \(targetToolID).")
            }

            let result = await WorkflowExecutor.shared.runWorkflow(
                targetDefinition: definition,
                latestSourceResult: nil,
                reason: reason
            )

            guard let artifact = result.artifact else {
                return NativePluginResult(
                    summary: result.run.events.last?.detail ?? "Workflow failed."
                )
            }

            return NativePluginResult(
                summary: artifact.summary,
                data: [
                    "target_tool_id": targetToolID,
                    "output_result_id": result.outputResult?.id.uuidString ?? "",
                    "workflow_run_id": result.run.id.uuidString
                ]
            )
        default:
            throw NativePluginError.unknownCapability(pluginID: id, capabilityID: capabilityID)
        }
    }
}

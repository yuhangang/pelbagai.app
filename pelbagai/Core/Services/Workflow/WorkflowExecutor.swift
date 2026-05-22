import Foundation
import Combine

struct WorkflowExecutionResult {
    var run: WorkflowRun
    var artifact: WorkflowArtifact?
    var outputResult: ScanResult?
}

@MainActor
final class WorkflowExecutor: ObservableObject {
    static let shared = WorkflowExecutor(
        storage: .shared,
        workflowStore: .shared,
        scriptRuntime: ToolScriptRuntime()
    )

    @Published private(set) var activeRun: WorkflowRun?
    @Published private(set) var lastArtifact: WorkflowArtifact?
    @Published private(set) var isRunning = false
    @Published private(set) var status = ""

    private let storage: ToolStorage
    private let workflowStore: WorkflowStore
    private let scriptRuntime: ToolScriptRuntime

    init(
        storage: ToolStorage,
        workflowStore: WorkflowStore,
        scriptRuntime: ToolScriptRuntime
    ) {
        self.storage = storage
        self.workflowStore = workflowStore
        self.scriptRuntime = scriptRuntime
    }

    func runWorkflow(
        targetDefinition: LocalToolDefinition,
        latestSourceResult: ScanResult?,
        reason: String
    ) async -> WorkflowExecutionResult {
        guard let workflow = targetDefinition.workflow else {
            let run = WorkflowRun(
                targetToolID: targetDefinition.toolID,
                sourceToolID: latestSourceResult?.toolID,
                status: .failed,
                events: [
                    WorkflowEvent(
                        title: "Workflow unavailable",
                        detail: "\(targetDefinition.displayName) does not declare a JSON workflow script."
                    )
                ],
                finishedAt: Date()
            )
            workflowStore.upsert(run)
            return WorkflowExecutionResult(run: run, artifact: nil, outputResult: nil)
        }

        guard !isRunning else {
            let existing = activeRun ?? WorkflowRun(
                targetToolID: targetDefinition.toolID,
                sourceToolID: latestSourceResult?.toolID,
                status: .running
            )
            return WorkflowExecutionResult(run: existing, artifact: lastArtifact, outputResult: nil)
        }

        isRunning = true
        status = "Running \(targetDefinition.displayName)..."
        var run = WorkflowRun(
            targetToolID: targetDefinition.toolID,
            sourceToolID: latestSourceResult?.toolID,
            status: .running,
            sourceResultIDs: latestSourceResult.map { [$0.id] } ?? [],
            events: [
                WorkflowEvent(
                    title: "Workflow started",
                    detail: reason
                )
            ]
        )
        activeRun = run
        workflowStore.upsert(run)

        defer {
            isRunning = false
            status = ""
        }

        if workflow.saveLatestSourceResult, let latestSourceResult {
            status = "Saving source result..."
            storage.save(latestSourceResult, to: latestSourceResult.toolID)
            run.events.append(
                WorkflowEvent(
                    title: "Source saved",
                    detail: "Saved latest \(latestSourceResult.toolID) result before workflow transform."
                )
            )
        }

        let inputToolIDs = Array(Set(workflow.inputToolIDs + workflow.triggerSourceToolIDs))
        let recordsByTool = inputToolIDs.reduce(into: [String: [ScanResult]]()) { partial, toolID in
            partial[toolID] = storage.loadAll(from: toolID)
        }

        let input = WorkflowScriptInput(
            reason: reason,
            targetToolID: targetDefinition.toolID,
            latestResult: latestSourceResult,
            recordsByTool: recordsByTool
        )

        do {
            status = "Executing JSON workflow script..."
            var artifact = try scriptRuntime.execute(
                script: workflow.transformScript,
                input: input
            )
            artifact.sourceResultIDs = workflowSourceIDs(
                artifact: artifact,
                recordsByTool: recordsByTool,
                latestSourceResult: latestSourceResult
            )
            let output = scanResult(from: artifact, targetDefinition: targetDefinition)
            storage.save(output, to: targetDefinition.toolID)

            run.status = .completed
            run.outputResultID = output.id
            run.sourceResultIDs = artifact.sourceResultIDs
            run.finishedAt = Date()
            run.events.append(
                WorkflowEvent(
                    title: "Workflow completed",
                    detail: artifact.summary
                )
            )
            activeRun = run
            lastArtifact = artifact
            workflowStore.upsert(run)
            return WorkflowExecutionResult(run: run, artifact: artifact, outputResult: output)
        } catch {
            run.status = .failed
            run.finishedAt = Date()
            run.events.append(
                WorkflowEvent(
                    title: "Workflow failed",
                    detail: error.localizedDescription
                )
            )
            activeRun = run
            workflowStore.upsert(run)
            return WorkflowExecutionResult(run: run, artifact: nil, outputResult: nil)
        }
    }

    private func workflowSourceIDs(
        artifact: WorkflowArtifact,
        recordsByTool: [String: [ScanResult]],
        latestSourceResult: ScanResult?
    ) -> [UUID] {
        if !artifact.sourceResultIDs.isEmpty {
            return artifact.sourceResultIDs
        }
        let storedIDs = recordsByTool.values.flatMap { $0.map(\.id) }
        if let latestSourceResult, !storedIDs.contains(latestSourceResult.id) {
            return storedIDs + [latestSourceResult.id]
        }
        return storedIDs
    }

    private func scanResult(
        from artifact: WorkflowArtifact,
        targetDefinition: LocalToolDefinition
    ) -> ScanResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let chartJSON = (try? encoder.encode(artifact.charts))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        var fields = artifact.fields.mapValues(FieldValue.string)
        fields["Title"] = .string(artifact.title)
        fields["Summary"] = .string(artifact.summary)
        fields["Metrics"] = .list(artifact.metrics.map { "\($0.title): \($0.value)" })
        fields["Chart Spec"] = .string(chartJSON)

        return ScanResult(
            id: artifact.id,
            toolID: targetDefinition.toolID,
            template: targetDefinition.displayName,
            richFields: fields,
            isValidated: true,
            validationNotes: "Generated by JSON workflow script.",
            timestamp: artifact.generatedAt
        )
    }
}

import Foundation
import Combine

@MainActor
final class WorkflowStore: ObservableObject {
    static let shared = WorkflowStore()

    @Published private(set) var runs: [WorkflowRun] = []

    private let fileName = "workflow_runs.json"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        load()
    }

    func upsert(_ run: WorkflowRun) {
        if let index = runs.firstIndex(where: { $0.id == run.id }) {
            runs[index] = run
        } else {
            runs.insert(run, at: 0)
        }
        persist()
    }

    func recentRuns(limit: Int = 20) -> [WorkflowRun] {
        Array(runs.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
    }

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            runs = []
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            runs = try decoder.decode([WorkflowRun].self, from: data)
        } catch {
            print("🔁 [WorkflowStore] Failed to load workflow runs: \(error)")
            runs = []
        }
    }

    private func persist() {
        do {
            let data = try encoder.encode(runs)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("🔁 [WorkflowStore] Failed to persist workflow runs: \(error)")
        }
    }
}

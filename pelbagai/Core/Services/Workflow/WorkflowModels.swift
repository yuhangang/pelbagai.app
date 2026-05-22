import Foundation

enum WorkflowRunStatus: String, Codable, Equatable {
    case planned
    case running
    case waitingForInput = "waiting_for_input"
    case completed
    case failed
    case cancelled
}

struct WorkflowEvent: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var detail: String
    var timestamp: Date

    init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
    }
}

struct WorkflowRun: Identifiable, Codable, Equatable {
    let id: UUID
    var targetToolID: String
    var sourceToolID: String?
    var status: WorkflowRunStatus
    var sourceResultIDs: [UUID]
    var outputResultID: UUID?
    var events: [WorkflowEvent]
    var startedAt: Date
    var finishedAt: Date?

    init(
        id: UUID = UUID(),
        targetToolID: String,
        sourceToolID: String? = nil,
        status: WorkflowRunStatus = .planned,
        sourceResultIDs: [UUID] = [],
        outputResultID: UUID? = nil,
        events: [WorkflowEvent] = [],
        startedAt: Date = Date(),
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.targetToolID = targetToolID
        self.sourceToolID = sourceToolID
        self.status = status
        self.sourceResultIDs = sourceResultIDs
        self.outputResultID = outputResultID
        self.events = events
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

struct WorkflowMetric: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var value: String

    init(id: UUID = UUID(), title: String, value: String) {
        self.id = id
        self.title = title
        self.value = value
    }
}

struct WorkflowChartPoint: Identifiable, Codable, Equatable {
    let id: UUID
    var label: String
    var value: Double

    init(id: UUID = UUID(), label: String, value: Double) {
        self.id = id
        self.label = label
        self.value = value
    }
}

struct WorkflowChart: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case bar
        case line
    }

    let id: UUID
    var title: String
    var kind: Kind
    var points: [WorkflowChartPoint]

    init(id: UUID = UUID(), title: String, kind: Kind, points: [WorkflowChartPoint]) {
        self.id = id
        self.title = title
        self.kind = kind
        self.points = points
    }
}

struct WorkflowArtifact: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var summary: String
    var metrics: [WorkflowMetric]
    var charts: [WorkflowChart]
    var fields: [String: String]
    var generatedAt: Date
    var sourceResultIDs: [UUID]

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        metrics: [WorkflowMetric] = [],
        charts: [WorkflowChart] = [],
        fields: [String: String] = [:],
        generatedAt: Date = Date(),
        sourceResultIDs: [UUID] = []
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.metrics = metrics
        self.charts = charts
        self.fields = fields
        self.generatedAt = generatedAt
        self.sourceResultIDs = sourceResultIDs
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case metrics
        case charts
        case fields
        case generatedAt
        case sourceResultIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Workflow Result"
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        metrics = try container.decodeIfPresent([WorkflowMetric].self, forKey: .metrics) ?? []
        charts = try container.decodeIfPresent([WorkflowChart].self, forKey: .charts) ?? []
        fields = try container.decodeIfPresent([String: String].self, forKey: .fields) ?? [:]
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? Date()
        sourceResultIDs = try container.decodeIfPresent([UUID].self, forKey: .sourceResultIDs) ?? []
    }
}

enum WorkflowPlanner {
    static func workflowTarget(
        forSourceToolID sourceToolID: String,
        userPrompt: String?,
        definitions: [LocalToolDefinition]
    ) -> LocalToolDefinition? {
        let normalizedSource = LocalToolDefinition.normalizedToolID(sourceToolID)
        let prompt = (userPrompt ?? "").lowercased()

        return definitions.first { definition in
            guard let workflow = definition.workflow,
                  workflow.triggerSourceToolIDs.contains(normalizedSource) else {
                return false
            }
            guard !prompt.isEmpty else { return false }
            return workflow.triggerKeywords.contains { prompt.contains($0) }
        }
    }
}

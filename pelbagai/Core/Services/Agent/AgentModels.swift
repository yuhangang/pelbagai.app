import Foundation
import GRDB

struct AgentToolCall: Codable, Hashable {
    var name: String
    var arguments: [String: String]
}

struct PendingToolCall: Equatable {
    let toolName: String
    let displayName: String
    let arguments: [String: String]
    let schema: [String: String]
    let pluginID: String
    let capabilityID: String
}

struct AgentTurnResult {
    var response: String
    var clarification: ClarificationRequest?
    var pendingToolCall: PendingToolCall?
    var diagnostics: AgentTurnDiagnostics?

    init(
        response: String,
        clarification: ClarificationRequest? = nil,
        pendingToolCall: PendingToolCall? = nil,
        diagnostics: AgentTurnDiagnostics? = nil
    ) {
        self.response = response
        self.clarification = clarification
        self.pendingToolCall = pendingToolCall
        self.diagnostics = diagnostics
    }
}

struct AgentTurnDiagnostics: Codable, Equatable {
    let startedAt: Date
    var finishedAt: Date?
    var routeToolNames: [String]
    var attempts: Int
    var historyMessagesIncluded: Int
    var estimatedPromptCharacters: Int
    var headroomMBAtStart: Int
    var headroomMBAtEnd: Int?
    var retryReason: String?
    var failureReason: String?
    var usedCompactContext: Bool
    var toolName: String?
}

struct AgentMemory: Identifiable, Codable, Hashable, FetchableRecord, PersistableRecord {
    let id: UUID
    var kind: String
    var key: String
    var value: String
    var sourceSessionId: UUID?
    var createdAt: Date
    var updatedAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let kind = Column(CodingKeys.kind)
        static let key = Column(CodingKeys.key)
        static let value = Column(CodingKeys.value)
        static let sourceSessionId = Column(CodingKeys.sourceSessionId)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }
}

import Foundation
import GRDB

struct ChatSession: Identifiable, Hashable, Codable, FetchableRecord, PersistableRecord {
    let id: UUID
    var title: String
    var createdAt: Date
    
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let title = Column(CodingKeys.title)
        static let createdAt = Column(CodingKeys.createdAt)
    }
}

struct ChatMessage: Identifiable, Hashable, Codable, FetchableRecord, PersistableRecord {
    let id: UUID
    let sessionId: UUID
    let role: MessageRole
    let content: String
    let imageData: Data?
    let timestamp: Date
    
    enum MessageRole: String, Codable, DatabaseValueConvertible {
        case user
        case assistant
        case system
    }
    
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let sessionId = Column(CodingKeys.sessionId)
        static let role = Column(CodingKeys.role)
        static let content = Column(CodingKeys.content)
        static let imageData = Column(CodingKeys.imageData)
        static let timestamp = Column(CodingKeys.timestamp)
    }
}

extension Notification.Name {
    static let sessionUpdated = Notification.Name("sessionUpdated")
}

class DatabaseManager {
    static let shared = DatabaseManager()
    
    private var dbQueue: DatabaseQueue!
    
    private init() {
        do {
            let fileURL = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("pelbagai.sqlite")
            
            dbQueue = try DatabaseQueue(path: fileURL.path)
            try migrator.migrate(dbQueue)
        } catch {
            fatalError("Error opening database: \(error)")
        }
    }
    
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("v1") { db in
            try db.create(table: "chatSession") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            
            try db.create(table: "chatMessage") { t in
                t.column("id", .text).primaryKey()
                t.column("sessionId", .text).notNull().references("chatSession", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("timestamp", .datetime).notNull()
            }
        }
        
        migrator.registerMigration("v2") { db in
            try db.alter(table: "chatMessage") { t in
                t.add(column: "imageData", .blob)
            }
        }

        migrator.registerMigration("v3_agent_memory") { db in
            try db.create(table: "agentMemory") { t in
                t.column("id", .text).primaryKey()
                t.column("kind", .text).notNull()
                t.column("key", .text).notNull()
                t.column("value", .text).notNull()
                t.column("sourceSessionId", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "agentMemory_kind_key", on: "agentMemory", columns: ["kind", "key"], unique: true)
            try db.create(index: "agentMemory_updatedAt", on: "agentMemory", columns: ["updatedAt"])
        }
        
        return migrator
    }
    
    // MARK: - CRUD for Sessions
    
    func createSession(title: String) -> ChatSession {
        let session = ChatSession(id: UUID(), title: title, createdAt: Date())
        do {
            try dbQueue.write { db in
                try session.insert(db)
            }
        } catch {
            print("Error inserting session: \(error)")
        }
        return session
    }
    
    func getOrCreateEmptySession(title: String = "New Chat") -> ChatSession {
        do {
            if let emptySession = try dbQueue.write({ db -> ChatSession? in
                let sessions = try ChatSession.filter(ChatSession.Columns.title == title).fetchAll(db)
                for var session in sessions {
                    let messageCount = try ChatMessage.filter(ChatMessage.Columns.sessionId == session.id).fetchCount(db)
                    if messageCount == 0 {
                        session.createdAt = Date()
                        try session.update(db)
                        return session
                    }
                }
                return nil
            }) {
                return emptySession
            }
        } catch {
            print("Error finding or updating empty session: \(error)")
        }
        
        return createSession(title: title)
    }
    
    func getAllSessions() -> [ChatSession] {
        do {
            return try dbQueue.read { db in
                try ChatSession.order(ChatSession.Columns.createdAt.desc).fetchAll(db)
            }
        } catch {
            print("Error getting sessions: \(error)")
            return []
        }
    }
    
    func updateSessionTitle(id: UUID, newTitle: String) {
        do {
            try dbQueue.write { db in
                if var session = try ChatSession.fetchOne(db, key: id) {
                    session.title = newTitle
                    try session.update(db)
                }
            }
        } catch {
            print("Error updating session title: \(error)")
        }
    }
    
    func deleteSession(id: UUID) {
        do {
            try dbQueue.write { db in
                _ = try ChatSession.deleteOne(db, key: id)
            }
        } catch {
            print("Error deleting session: \(error)")
        }
    }
    
    // MARK: - CRUD for Messages
    
    func addMessage(_ message: ChatMessage) {
        do {
            try dbQueue.write { db in
                try message.insert(db)
            }
        } catch {
            print("Error inserting message: \(error)")
        }
    }
    
    func getMessages(for sessionId: UUID) -> [ChatMessage] {
        do {
            return try dbQueue.read { db in
                try ChatMessage
                    .filter(ChatMessage.Columns.sessionId == sessionId)
                    .order(ChatMessage.Columns.timestamp.asc)
                    .fetchAll(db)
            }
        } catch {
            print("Error getting messages: \(error)")
            return []
        }
    }
    
    func deleteMessage(id: UUID) {
        do {
            try dbQueue.write { db in
                _ = try ChatMessage.deleteOne(db, key: id)
            }
        } catch {
            print("Error deleting message: \(error)")
        }
    }

    // MARK: - Agent Memory

    func upsertAgentMemory(kind: String, key: String, value: String, sourceSessionId: UUID?) {
        let normalizedKind = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKind.isEmpty, !normalizedKey.isEmpty, !trimmedValue.isEmpty else { return }

        do {
            try dbQueue.write { db in
                if var existing = try AgentMemory
                    .filter(AgentMemory.Columns.kind == normalizedKind)
                    .filter(AgentMemory.Columns.key == normalizedKey)
                    .fetchOne(db) {
                    existing.value = trimmedValue
                    existing.sourceSessionId = sourceSessionId ?? existing.sourceSessionId
                    existing.updatedAt = Date()
                    try existing.update(db)
                } else {
                    let memory = AgentMemory(
                        id: UUID(),
                        kind: normalizedKind,
                        key: normalizedKey,
                        value: trimmedValue,
                        sourceSessionId: sourceSessionId,
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                    try memory.insert(db)
                }
            }
        } catch {
            print("Error upserting agent memory: \(error)")
        }
    }

    func searchAgentMemory(query: String, limit: Int = 6) -> [AgentMemory] {
        let terms = query
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 }
        guard !terms.isEmpty else {
            return recentAgentMemories(limit: limit)
        }

        do {
            return try dbQueue.read { db in
                let memories = try AgentMemory
                    .order(AgentMemory.Columns.updatedAt.desc)
                    .fetchAll(db)
                return memories
                    .filter { memory in
                        let haystack = "\(memory.kind) \(memory.key) \(memory.value)".lowercased()
                        return terms.contains { haystack.contains($0) }
                    }
                    .prefix(limit)
                    .map { $0 }
            }
        } catch {
            print("Error searching agent memory: \(error)")
            return []
        }
    }

    func recentAgentMemories(limit: Int = 6) -> [AgentMemory] {
        do {
            return try dbQueue.read { db in
                try AgentMemory
                    .order(AgentMemory.Columns.updatedAt.desc)
                    .limit(limit)
                    .fetchAll(db)
            }
        } catch {
            print("Error getting agent memories: \(error)")
            return []
        }
    }
}

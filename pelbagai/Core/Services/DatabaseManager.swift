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

struct ChatAttachment: Identifiable, Hashable, Codable {
    let id: UUID
    let filename: String
    let fileType: String // e.g., "pdf", "text"
    let localPath: String
    let extractedText: String?
}

struct CanvasAppInfo: Identifiable, Hashable, Codable {
    let id: UUID
    let title: String
    let localPath: String
    let sessionId: UUID
    let timestamp: Date
}

struct ChatMessage: Identifiable, Hashable, Codable, FetchableRecord, PersistableRecord {
    let id: UUID
    let sessionId: UUID
    let role: MessageRole
    let content: String
    let imageData: Data?
    let attachmentsData: Data?
    let timestamp: Date
    
    var attachments: [ChatAttachment] {
        guard let data = attachmentsData else { return [] }
        return (try? JSONDecoder().decode([ChatAttachment].self, from: data)) ?? []
    }
    
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
        static let attachmentsData = Column(CodingKeys.attachmentsData)
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
        
        migrator.registerMigration("v4_attachments_support") { db in
            try db.alter(table: "chatMessage") { t in
                t.add(column: "attachmentsData", .blob)
            }
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
            // Find all attachments associated with this session before deleting
            let attachments: [ChatAttachment] = try dbQueue.read { db in
                try ChatMessage
                    .filter(ChatMessage.Columns.sessionId == id)
                    .filter(ChatMessage.Columns.attachmentsData != nil)
                    .fetchAll(db)
                    .flatMap { $0.attachments }
            }
            
            try dbQueue.write { db in
                _ = try ChatSession.deleteOne(db, key: id)
            }
            
            // Cleanup filesystem
            for attachment in attachments {
                deleteAttachmentFile(named: attachment.localPath)
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
    func updateMessageAttachments(id: UUID, attachmentsData: Data?) {
        do {
            try dbQueue.write { db in
                if var message = try ChatMessage.fetchOne(db, key: id) {
                    let updated = ChatMessage(
                        id: message.id,
                        sessionId: message.sessionId,
                        role: message.role,
                        content: message.content,
                        imageData: message.imageData,
                        attachmentsData: attachmentsData,
                        timestamp: message.timestamp
                    )
                    try updated.update(db)
                }
            }
        } catch {
            print("Error updating message attachments: \(error)")
        }
    }
    
    func updateMessageImageData(id: UUID, imageData: Data?) {
        do {
            try dbQueue.write { db in
                if var message = try ChatMessage.fetchOne(db, key: id) {
                    let updated = ChatMessage(
                        id: message.id,
                        sessionId: message.sessionId,
                        role: message.role,
                        content: message.content,
                        imageData: imageData,
                        attachmentsData: message.attachmentsData,
                        timestamp: message.timestamp
                    )
                    try updated.update(db)
                }
            }
        } catch {
            print("Error updating message imageData: \(error)")
        }
    }
    
    func deleteMessage(id: UUID) {
        do {
            let attachments = try dbQueue.read { db in
                try ChatMessage.fetchOne(db, key: id)?.attachments ?? []
            }
            
            try dbQueue.write { db in
                _ = try ChatMessage.deleteOne(db, key: id)
            }
            
            for attachment in attachments {
                deleteAttachmentFile(named: attachment.localPath)
            }
        } catch {
            print("Error deleting message: \(error)")
        }
    }
    
    private func deleteAttachmentFile(named filename: String) {
        do {
            let fileManager = FileManager.default
            let documentsURL = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            // Use generic "Attachments" directory or stay with "PDFs" for now?
            // User said treat pdf as attachment, so let's use an "Attachments" folder.
            let attachmentsDirectory = documentsURL.appendingPathComponent("Attachments", isDirectory: true)
            let fileURL = attachmentsDirectory.appendingPathComponent(filename)
            
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
                print("🧠 Database: Deleted attachment file \(filename)")
            }
        } catch {
            print("🧠 Database: Failed to delete attachment file \(filename): \(error)")
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
    
    // MARK: - Canvas Apps
    
    func getAllCanvasApps() -> [CanvasAppInfo] {
        var apps: [CanvasAppInfo] = []
        
        // 1. Load pre-bundled default Canvas Examples
        let defaultExamples = [
            (id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, filename: "pos_terminal", title: "Sleek POS Terminal"),
            (id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!, filename: "kitchen_timer", title: "Kitchen Timers"),
            (id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, filename: "workout_timer", title: "Interval Workout Timer"),
            (id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, filename: "reaction_game", title: "Reaction Color Game")
        ]
        
        for example in defaultExamples {
            // Check if it exists in the bundle (we don't strictly require it to exist to append it, but it's a safe validation)
            let hasResource = Bundle.main.url(forResource: example.filename, withExtension: "html") != nil ||
                              Bundle.main.url(forResource: example.filename, withExtension: "html", subdirectory: "CanvasExamples") != nil
            
            if hasResource {
                apps.append(CanvasAppInfo(
                    id: example.id,
                    title: example.title,
                    localPath: "bundle:\(example.filename)",
                    sessionId: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, // Special dummy session ID
                    timestamp: Date(timeIntervalSince1970: 0) // Past date so they go to the bottom/end of descending order
                ))
            } else {
                // If not in bundle yet (e.g. before compilation sync), still append as a safe placeholder
                apps.append(CanvasAppInfo(
                    id: example.id,
                    title: example.title,
                    localPath: "bundle:\(example.filename)",
                    sessionId: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
                    timestamp: Date(timeIntervalSince1970: 0)
                ))
            }
        }
        
        do {
            let messages: [ChatMessage] = try dbQueue.read { db in
                try ChatMessage
                    .filter(ChatMessage.Columns.attachmentsData != nil)
                    .order(ChatMessage.Columns.timestamp.desc)
                    .fetchAll(db)
            }
            
            let fileManager = FileManager.default
            let documentsURL = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let attachmentsDirectory = documentsURL.appendingPathComponent("Attachments", isDirectory: true)
            
            for msg in messages {
                for attachment in msg.attachments {
                    if attachment.fileType.lowercased() == "html" && attachment.extractedText == "[AI Canvas Micro-App]" {
                        let fileURL = attachmentsDirectory.appendingPathComponent(attachment.localPath)
                        guard fileManager.fileExists(atPath: fileURL.path) else { continue }
                        
                        // Extract title dynamically
                        var appTitle = attachment.filename.replacingOccurrences(of: ".html", with: "")
                        if let htmlContent = try? String(contentsOf: fileURL, encoding: .utf8) {
                            if let titleRange = htmlContent.range(of: "<title>", options: .caseInsensitive),
                               let endTitleRange = htmlContent.range(of: "</title>", options: .caseInsensitive, range: titleRange.upperBound..<htmlContent.endIndex) {
                                let extracted = htmlContent[titleRange.upperBound..<endTitleRange.lowerBound]
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                if !extracted.isEmpty {
                                    appTitle = extracted
                                }
                            }
                        }
                        
                        // Prevent duplicates in case multiple messages reference the exact same file
                        if !apps.contains(where: { $0.localPath == attachment.localPath }) {
                            apps.append(CanvasAppInfo(
                                id: attachment.id,
                                title: appTitle,
                                localPath: attachment.localPath,
                                sessionId: msg.sessionId,
                                timestamp: msg.timestamp
                            ))
                        }
                    }
                }
            }
        } catch {
            print("Error fetching all canvas apps: \(error)")
        }
        
        // Sort: user generated apps (recent timestamps) first, then bundled default apps at the end
        return apps.sorted(by: { $0.timestamp > $1.timestamp })
    }
}

import Foundation
import GRDB
import LibraryCore
import ReaderCore
import ReflectionCore

private func decodeUUID(_ value: String, table: String, recordID: String, field: String) throws -> UUID {
    guard let id = UUID(uuidString: value) else {
        throw PersistenceError.corruptRecord(table: table, recordID: recordID, field: field)
    }
    return id
}

public final class GRDBJournalRepository: JournalRepository, @unchecked Sendable {
    private let db: AppDatabase
    public init(database: AppDatabase) { db = database }

    public func thoughts(for reflectionID: ReflectionID) async throws -> [JournalThought] {
        try await db.writer.read { db in
            try JournalThoughtRecord.filter(Column("reflectionID") == reflectionID.description)
                .order(Column("createdAt"), Column("id")).fetchAll(db).map { try $0.domain() }
        }
    }

    public func saveThought(_ thought: JournalThought) async throws {
        try await db.writer.write { db in try JournalThoughtRecord(thought).insert(db) }
    }

    public func questions(for reflectionID: ReflectionID) async throws -> [AgentQuestion] {
        try await db.writer.read { db in
            try AgentQuestionRecord.filter(Column("reflectionID") == reflectionID.description)
                .order(Column("createdAt"), Column("id")).fetchAll(db).map { try $0.domain() }
        }
    }

    public func saveQuestion(_ question: AgentQuestion) async throws {
        try await db.writer.write { db in try AgentQuestionRecord(question).insert(db) }
    }

    public func citations(for reflectionID: ReflectionID) async throws -> [ReflectionCitation] {
        try await db.writer.read { db in
            try ReflectionCitationRecord.filter(Column("reflectionID") == reflectionID.description)
                .order(Column("createdAt"), Column("id")).fetchAll(db).map { try $0.domain() }
        }
    }

    public func saveCitation(_ citation: ReflectionCitation) async throws {
        try await db.writer.write { db in try ReflectionCitationRecord(citation).insert(db) }
    }

    public func memoryChanges(for journalID: ReflectionID) async throws -> [JournalMemoryChange] {
        try await db.writer.read { db in
            try JournalMemoryChangeRecord.filter(Column("journalID") == journalID.description)
                .order(Column("createdAt"), Column("id")).fetchAll(db).map { try $0.domain() }
        }
    }

    public func saveMemoryChange(_ change: JournalMemoryChange) async throws {
        try await db.writer.write { db in
            // journalMemoryChanges is keyed by journalID (per spec), so dedup by
            // content to keep repeated materialization idempotent.
            let existing = try Int.fetchOne(db, sql: """
                SELECT count(*) FROM journalMemoryChanges
                WHERE journalID=? AND changeType=? AND summary=?
                """, arguments: [change.journalID.description, change.changeType.rawValue, change.summary]) ?? 0
            guard existing == 0 else { return }
            try JournalMemoryChangeRecord(change).insert(db)
        }
    }

    public func hasStructuredData(for reflectionID: ReflectionID, messageID: UUID) async throws -> Bool {
        try await db.writer.read { db in
            let id = messageID.uuidString.lowercased()
            for table in ["journalThoughts", "agentQuestions", "reflectionCitations"] {
                let count = try Int.fetchOne(
                    db, sql: "SELECT count(*) FROM \(table) WHERE messageID = ?", arguments: [id]
                ) ?? 0
                if count > 0 { return true }
            }
            return false
        }
    }
}

private struct JournalThoughtRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "journalThoughts"
    var id, reflectionID, messageID, thought: String
    var createdAt: Date

    init(_ thought: JournalThought) {
        id = thought.id.uuidString.lowercased()
        reflectionID = thought.reflectionID.description
        messageID = thought.messageID.uuidString.lowercased()
        self.thought = thought.thought
        createdAt = thought.createdAt
    }

    func domain() throws -> JournalThought {
        JournalThought(
            id: try decodeUUID(id, table: Self.databaseTableName, recordID: id, field: "id"),
            reflectionID: .init(rawValue: try decodeUUID(reflectionID, table: Self.databaseTableName, recordID: id, field: "reflectionID")),
            messageID: try decodeUUID(messageID, table: Self.databaseTableName, recordID: id, field: "messageID"),
            thought: thought,
            createdAt: createdAt
        )
    }
}

private struct AgentQuestionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "agentQuestions"
    var id, reflectionID, messageID, text, status: String
    var createdAt: Date
    var answeredByMessageID: String?

    init(_ question: AgentQuestion) {
        id = question.id.uuidString.lowercased()
        reflectionID = question.reflectionID.description
        messageID = question.messageID.uuidString.lowercased()
        text = question.text
        status = question.status.rawValue
        createdAt = question.createdAt
        answeredByMessageID = question.answeredByMessageID?.uuidString.lowercased()
    }

    func domain() throws -> AgentQuestion {
        guard let decodedStatus = AgentQuestionStatus(rawValue: status) else {
            throw PersistenceError.corruptRecord(table: Self.databaseTableName, recordID: id, field: "status")
        }
        return AgentQuestion(
            id: try decodeUUID(id, table: Self.databaseTableName, recordID: id, field: "id"),
            reflectionID: .init(rawValue: try decodeUUID(reflectionID, table: Self.databaseTableName, recordID: id, field: "reflectionID")),
            messageID: try decodeUUID(messageID, table: Self.databaseTableName, recordID: id, field: "messageID"),
            text: text,
            createdAt: createdAt,
            status: decodedStatus,
            answeredByMessageID: answeredByMessageID.flatMap(UUID.init(uuidString:))
        )
    }
}

private struct ReflectionCitationRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "reflectionCitations"
    var id, reflectionID, messageID, sourceType, bookID: String
    var sourceID: String?
    var locatorJSON: Data?
    var href: String?
    var progression, totalProgression: Double?
    var textBefore, textHighlight, textAfter: String?
    var title, excerpt: String?
    var createdAt: Date

    init(_ citation: ReflectionCitation) {
        id = citation.id.uuidString.lowercased()
        reflectionID = citation.reflectionID.description
        messageID = citation.messageID.uuidString.lowercased()
        sourceType = citation.sourceType.rawValue
        sourceID = citation.sourceID
        bookID = citation.bookID.description
        locatorJSON = citation.locator?.json
        href = citation.locator?.href
        progression = citation.locator?.progression
        totalProgression = citation.locator?.totalProgression
        textBefore = citation.locator?.textBefore
        textHighlight = citation.locator?.textHighlight
        textAfter = citation.locator?.textAfter
        title = citation.title
        excerpt = citation.excerpt
        createdAt = citation.createdAt
    }

    func domain() throws -> ReflectionCitation {
        guard let decodedSourceType = ReflectionEvidenceSourceType(rawValue: sourceType) else {
            throw PersistenceError.corruptRecord(table: Self.databaseTableName, recordID: id, field: "sourceType")
        }
        let locator: BookLocator?
        if let locatorJSON, let href {
            locator = try BookLocator(json: locatorJSON, href: href, progression: progression, totalProgression: totalProgression, textBefore: textBefore, textHighlight: textHighlight, textAfter: textAfter)
        } else if locatorJSON == nil, href == nil {
            locator = nil
        } else {
            throw PersistenceError.corruptRecord(table: Self.databaseTableName, recordID: id, field: "locator")
        }
        return ReflectionCitation(
            id: try decodeUUID(id, table: Self.databaseTableName, recordID: id, field: "id"),
            reflectionID: .init(rawValue: try decodeUUID(reflectionID, table: Self.databaseTableName, recordID: id, field: "reflectionID")),
            messageID: try decodeUUID(messageID, table: Self.databaseTableName, recordID: id, field: "messageID"),
            sourceType: decodedSourceType,
            sourceID: sourceID,
            bookID: .init(rawValue: try decodeUUID(bookID, table: Self.databaseTableName, recordID: id, field: "bookID")),
            locator: locator,
            title: title,
            excerpt: excerpt,
            createdAt: createdAt
        )
    }
}

private struct JournalMemoryChangeRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "journalMemoryChanges"
    var id, journalID, changeType, summary: String
    var memoryID: String?
    var createdAt: Date

    init(_ change: JournalMemoryChange) {
        id = change.id.uuidString.lowercased()
        journalID = change.journalID.description
        changeType = change.changeType.rawValue
        memoryID = change.memoryID
        summary = change.summary
        createdAt = change.createdAt
    }

    func domain() throws -> JournalMemoryChange {
        guard let decodedType = JournalMemoryChangeType(rawValue: changeType) else {
            throw PersistenceError.corruptRecord(table: Self.databaseTableName, recordID: id, field: "changeType")
        }
        return JournalMemoryChange(
            id: try decodeUUID(id, table: Self.databaseTableName, recordID: id, field: "id"),
            journalID: .init(rawValue: try decodeUUID(journalID, table: Self.databaseTableName, recordID: id, field: "journalID")),
            changeType: decodedType,
            memoryID: memoryID,
            summary: summary,
            createdAt: createdAt
        )
    }
}

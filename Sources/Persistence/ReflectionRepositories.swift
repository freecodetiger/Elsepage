#if canImport(ReadingSessionCore) && canImport(ReflectionCore)
import Foundation
import GRDB
import LibraryCore
import ReaderCore
import ReadingSessionCore
import ReflectionCore

public final class GRDBReadingSessionRepository: ReadingSessionRepository, @unchecked Sendable {
    private let db: AppDatabase
    public init(database: AppDatabase) { db = database }

    public func session(id: ReadingSessionID) async throws -> ReadingSession? {
        try await db.writer.read { db in try SessionRecord.fetchOne(db, key: id.description)?.domain() }
    }

    public func sessions(for bookID: BookID) async throws -> [ReadingSession] {
        try await db.writer.read { db in
            try SessionRecord.filter(Column("bookID") == bookID.description)
                .order(Column("startedAt").desc).fetchAll(db).map { try $0.domain() }
        }
    }

    public func insert(_ session: ReadingSession) async throws {
        try await db.writer.write { db in try SessionRecord(session).insert(db) }
    }

    public func complete(
        id: ReadingSessionID, endedAt: Date, endLocator: BookLocator,
        highlightCount: Int, noteCount: Int, agentDiscussionCount: Int
    ) async throws {
        try await db.writer.write { db in
            guard var record = try SessionRecord.fetchOne(db, key: id.description) else {
                throw PersistenceError.missingReadingSession
            }
            record.endedAt = endedAt
            record.setEndLocator(endLocator)
            record.highlightCount = highlightCount
            record.noteCount = noteCount
            record.agentDiscussionCount = agentDiscussionCount
            try record.update(db)
        }
    }

    public func delete(id: ReadingSessionID) async throws {
        _ = try await db.writer.write { db in try SessionRecord.deleteOne(db, key: id.description) }
    }
}

public final class GRDBReflectionRepository: ReflectionRepository, @unchecked Sendable {
    private let db: AppDatabase
    public init(database: AppDatabase) { db = database }

    public func reflection(id: ReflectionID) async throws -> Reflection? {
        try await db.writer.read { db in try ReflectionRecord.fetchOne(db, key: id.description)?.domain }
    }

    public func reflections(for bookID: BookID) async throws -> [Reflection] {
        try await db.writer.read { db in
            try ReflectionRecord.filter(Column("bookID") == bookID.description)
                .order(Column("createdAt").desc).fetchAll(db).map(\.domain)
        }
    }

    public func insert(_ reflection: Reflection, linkedHighlightIDs: [UUID] = []) async throws {
        try await db.writer.write { db in
            if let sessionID = reflection.sessionID {
                guard let sessionBookID = try String.fetchOne(
                    db, sql: "SELECT bookID FROM readingSessions WHERE id = ?", arguments: [sessionID.description]
                ) else { throw PersistenceError.missingReadingSession }
                guard sessionBookID == reflection.bookID.description else { throw PersistenceError.inconsistentReflectionContext }
            }
            try ReflectionRecord(reflection).insert(db)
            for highlightID in linkedHighlightIDs {
                let highlightBookID = try String.fetchOne(
                    db, sql: "SELECT bookID FROM highlights WHERE id = ?", arguments: [highlightID.uuidString.lowercased()]
                )
                guard highlightBookID == reflection.bookID.description else { throw PersistenceError.inconsistentReflectionContext }
                try db.execute(
                    sql: "INSERT INTO reflectionHighlights (reflectionID, highlightID) VALUES (?, ?)",
                    arguments: [reflection.id.description, highlightID.uuidString.lowercased()]
                )
            }
        }
    }

    public func linkedHighlightIDs(for reflectionID: ReflectionID) async throws -> [UUID] {
        try await db.writer.read { db in
            try String.fetchAll(
                db, sql: "SELECT highlightID FROM reflectionHighlights WHERE reflectionID = ? ORDER BY highlightID",
                arguments: [reflectionID.description]
            ).compactMap(UUID.init(uuidString:))
        }
    }

    public func derivedMessages(for reflectionID: ReflectionID) async throws -> [ReflectionDerivedMessage] {
        try await db.writer.read { db in
            try ReflectionMessageRecord.filter(Column("reflectionID") == reflectionID.description)
                .order(Column("createdAt"), Column("id")).fetchAll(db).compactMap(\.domain)
        }
    }

    public func appendDerivedMessage(_ message: ReflectionDerivedMessage) async throws {
        try await db.writer.write { db in try ReflectionMessageRecord(message).insert(db) }
    }

    public func delete(id: ReflectionID) async throws {
        _ = try await db.writer.write { db in try ReflectionRecord.deleteOne(db, key: id.description) }
    }
}

private struct SessionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "readingSessions"
    var id, bookID: String
    var startedAt: Date
    var endedAt: Date?
    var startLocatorJSON: Data
    var startHref: String
    var startProgression, startTotalProgression: Double?
    var startTextBefore, startTextHighlight, startTextAfter: String?
    var endLocatorJSON: Data?
    var endHref: String?
    var endProgression, endTotalProgression: Double?
    var endTextBefore, endTextHighlight, endTextAfter: String?
    var highlightCount, noteCount, agentDiscussionCount: Int

    init(_ session: ReadingSession) {
        id = session.id.description; bookID = session.bookID.description
        startedAt = session.startedAt; endedAt = session.endedAt
        startLocatorJSON = session.startLocator.json; startHref = session.startLocator.href
        startProgression = session.startLocator.progression; startTotalProgression = session.startLocator.totalProgression
        startTextBefore = session.startLocator.textBefore; startTextHighlight = session.startLocator.textHighlight; startTextAfter = session.startLocator.textAfter
        endLocatorJSON = nil; endHref = nil; endProgression = nil; endTotalProgression = nil
        endTextBefore = nil; endTextHighlight = nil; endTextAfter = nil
        highlightCount = session.highlightCount; noteCount = session.noteCount; agentDiscussionCount = session.agentDiscussionCount
        if let locator = session.endLocator { setEndLocator(locator) }
    }

    mutating func setEndLocator(_ locator: BookLocator) {
        endLocatorJSON = locator.json; endHref = locator.href
        endProgression = locator.progression; endTotalProgression = locator.totalProgression
        endTextBefore = locator.textBefore; endTextHighlight = locator.textHighlight; endTextAfter = locator.textAfter
    }

    func domain() throws -> ReadingSession {
        let start = try BookLocator(json: startLocatorJSON, href: startHref, progression: startProgression, totalProgression: startTotalProgression, textBefore: startTextBefore, textHighlight: startTextHighlight, textAfter: startTextAfter)
        let end: BookLocator?
        if let json = endLocatorJSON, let href = endHref {
            end = try BookLocator(json: json, href: href, progression: endProgression, totalProgression: endTotalProgression, textBefore: endTextBefore, textHighlight: endTextHighlight, textAfter: endTextAfter)
        } else { end = nil }
        return ReadingSession(id: .init(rawValue: UUID(uuidString: id)!), bookID: .init(rawValue: UUID(uuidString: bookID)!), startedAt: startedAt, endedAt: endedAt, startLocator: start, endLocator: end, highlightCount: highlightCount, noteCount: noteCount, agentDiscussionCount: agentDiscussionCount)
    }
}

private struct ReflectionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "reflections"
    var id, bookID: String
    var sessionID: String?
    var originalText, inputKind: String
    var audioFileName: String?
    var createdAt: Date
    init(_ reflection: Reflection) {
        id = reflection.id.description; bookID = reflection.bookID.description
        sessionID = reflection.sessionID?.description; originalText = reflection.originalText
        inputKind = reflection.inputKind.rawValue; audioFileName = reflection.audioFileName; createdAt = reflection.createdAt
    }
    var domain: Reflection {
        Reflection(id: .init(rawValue: UUID(uuidString: id)!), bookID: .init(rawValue: UUID(uuidString: bookID)!), sessionID: sessionID.flatMap(UUID.init(uuidString:)).map(ReadingSessionID.init(rawValue:)), originalText: originalText, inputKind: ReflectionInputKind(rawValue: inputKind)!, audioFileName: audioFileName, createdAt: createdAt)
    }
}

private struct ReflectionMessageRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "reflectionMessages"
    var id, reflectionID, role, content: String
    var createdAt: Date
    init(_ message: ReflectionDerivedMessage) {
        id = message.id.uuidString.lowercased(); reflectionID = message.reflectionID.description
        role = message.role.rawValue; content = message.content; createdAt = message.createdAt
    }
    var domain: ReflectionDerivedMessage? {
        guard let id = UUID(uuidString: id), let reflectionID = UUID(uuidString: reflectionID), let role = ReflectionDerivedMessage.Role(rawValue: role) else { return nil }
        return ReflectionDerivedMessage(id: id, reflectionID: .init(rawValue: reflectionID), role: role, content: content, createdAt: createdAt)
    }
}
#endif

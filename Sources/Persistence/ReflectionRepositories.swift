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
                .order(Column("createdAt").desc).fetchAll(db).map { try $0.domain }
        }
    }

    public func insert(
        _ reflection: Reflection, linkedHighlightIDs: [UUID] = [], evidence: [ReflectionEvidence] = []
    ) async throws {
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
            for item in evidence {
                guard item.reflectionID == reflection.id else { throw PersistenceError.inconsistentReflectionContext }
                try Self.validate(item, belongsTo: reflection.bookID, in: db)
                try ReflectionEvidenceRecord(item).insert(db)
            }
        }
    }

    public func linkedHighlightIDs(for reflectionID: ReflectionID) async throws -> [UUID] {
        try await db.writer.read { db in
            try String.fetchAll(
                db, sql: "SELECT highlightID FROM reflectionHighlights WHERE reflectionID = ? ORDER BY highlightID",
                arguments: [reflectionID.description]
            ).map { value in
                guard let id = UUID(uuidString: value) else {
                    throw PersistenceError.corruptRecord(table: "reflectionHighlights", recordID: reflectionID.description, field: "highlightID")
                }
                return id
            }
        }
    }

    public func messages(for reflectionID: ReflectionID) async throws -> [ReflectionMessage] {
        try await db.writer.read { db in
            let records = try ReflectionMessageRecord.filter(Column("reflectionID") == reflectionID.description)
                .order(Column("createdAt"), Column("id")).fetchAll(db)
            var result: [ReflectionMessage] = []
            result.reserveCapacity(records.count)
            for record in records {
                let message = try record.domain()
                guard message.author == .agent else {
                    result.append(message); continue
                }
                let citations = try AgentCitationRecord
                    .filter(Column("messageID") == message.id.uuidString.lowercased())
                    .order(Column("id")).fetchAll(db).map { try $0.domain() }
                result.append(message.withCitations(citations))
            }
            return result
        }
    }

    public func appendMessage(_ message: ReflectionMessage) async throws {
        try await db.writer.write { db in
            if let existing = try ReflectionMessageRecord.fetchOne(db, key: message.id.uuidString.lowercased()) {
                guard try existing.domain() == message else { throw PersistenceError.inconsistentReflectionContext }
                return
            }
            try ReflectionMessageRecord(message).insert(db)
        }
    }

    public func appendAgentMessage(
        _ message: ReflectionMessage,
        evidence: [AgentResponseEvidence],
        citations: [AgentCitation]
    ) async throws {
        try await db.writer.write { db in
            guard message.author == .agent, message.source == .agentGenerated,
                  evidence.allSatisfy({ $0.messageID == message.id }),
                  citations.allSatisfy({ $0.messageID == message.id }) else {
                throw PersistenceError.inconsistentReflectionContext
            }
            let evidenceIDs = Set(evidence.map(\.id))
            guard Set(citations.map(\.evidenceID)).isSubset(of: evidenceIDs),
                  evidenceIDs.count == evidence.count else {
                throw PersistenceError.inconsistentReflectionContext
            }
            if let existing = try ReflectionMessageRecord.fetchOne(db, key: message.id.uuidString.lowercased()) {
                guard try existing.domain() == message else { throw PersistenceError.inconsistentReflectionContext }
                return
            }
            try ReflectionMessageRecord(message).insert(db)
            for item in evidence { try AgentResponseEvidenceRecord(item).insert(db) }
            for citation in citations { try AgentCitationRecord(citation).insert(db) }
        }
    }

    public func provenance(for messageID: UUID) async throws -> AgentResponseProvenance {
        try await db.writer.read { db in
            let key = messageID.uuidString.lowercased()
            let evidence = try AgentResponseEvidenceRecord
                .filter(Column("messageID") == key).order(Column("id"))
                .fetchAll(db).map { try $0.domain() }
            let citations = try AgentCitationRecord
                .filter(Column("messageID") == key).order(Column("id"))
                .fetchAll(db).map { try $0.domain() }
            return .init(evidence: evidence, citations: citations)
        }
    }

    public func message(id: UUID) async throws -> ReflectionMessage? {
        try await db.writer.read { db in
            try ReflectionMessageRecord.fetchOne(db, key: id.uuidString.lowercased())?.domain()
        }
    }

    public func recentReflections(limit: Int) async throws -> [Reflection] {
        try await db.writer.read { db in
            try ReflectionRecord.order(Column("createdAt").desc)
                .limit(max(0, limit)).fetchAll(db).map { try $0.domain }
        }
    }

    public func connections(for reflectionID: ReflectionID) async throws -> [ReflectionConnection] {
        try await db.writer.read { db in
            try ReflectionConnectionRecord.filter(Column("reflectionID") == reflectionID.description)
                .order(Column("relevance").desc, Column("createdAt").desc)
                .fetchAll(db).map { try $0.domain() }
        }
    }

    public func saveConnection(_ connection: ReflectionConnection) async throws {
        try await db.writer.write { db in
            guard connection.reflectionID != connection.sourceReflectionID else {
                throw PersistenceError.inconsistentReflectionContext
            }
            try ReflectionConnectionRecord(connection).insert(db, onConflict: .ignore)
        }
    }

    public func evidence(for reflectionID: ReflectionID) async throws -> [ReflectionEvidence] {
        try await db.writer.read { db in
            try ReflectionEvidenceRecord.filter(Column("reflectionID") == reflectionID.description)
                .order(Column("createdAt"), Column("id")).fetchAll(db).map { try $0.domain() }
        }
    }

    public func appendEvidence(_ evidence: ReflectionEvidence) async throws {
        try await db.writer.write { db in
            guard let bookID = try String.fetchOne(
                db, sql: "SELECT bookID FROM reflections WHERE id = ?", arguments: [evidence.reflectionID.description]
            ) else { throw PersistenceError.inconsistentReflectionContext }
            let reflectionBookID = BookID(rawValue: try decodeUUID(
                bookID, table: "reflections", recordID: evidence.reflectionID.description, field: "bookID"
            ))
            try Self.validate(evidence, belongsTo: reflectionBookID, in: db)
            try ReflectionEvidenceRecord(evidence).insert(db)
        }
    }

    public func delete(id: ReflectionID) async throws {
        _ = try await db.writer.write { db in try ReflectionRecord.deleteOne(db, key: id.description) }
    }

    private static func validate(_ evidence: ReflectionEvidence, belongsTo bookID: BookID, in db: Database) throws {
        if evidence.sourceType == .bookLocator {
            guard evidence.locator != nil else { throw PersistenceError.inconsistentReflectionContext }
            return
        }
        guard let sourceID = evidence.sourceID else { throw PersistenceError.inconsistentReflectionContext }
        let table: String
        switch evidence.sourceType {
        case .highlight: table = "highlights"
        case .note: table = "notes"
        case .readingSession: table = "readingSessions"
        case .bookLocator: return
        }
        let sourceBookID = try String.fetchOne(
            db, sql: "SELECT bookID FROM \(table) WHERE id = ?", arguments: [sourceID.lowercased()]
        )
        guard sourceBookID == bookID.description else { throw PersistenceError.inconsistentReflectionContext }
    }
}

private struct AgentResponseEvidenceRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "agentResponseEvidence"
    var messageID, id, kind, sourceID, bookID: String
    var title: String?
    var excerpt: String
    var locatorJSON: Data?
    var href: String?
    var progression, totalProgression: Double?
    var textBefore, textHighlight, textAfter: String?

    init(_ evidence: AgentResponseEvidence) {
        messageID = evidence.messageID.uuidString.lowercased(); id = evidence.id
        kind = evidence.kind.rawValue; sourceID = evidence.sourceID; bookID = evidence.bookID.description
        title = evidence.title; excerpt = evidence.excerpt
        locatorJSON = evidence.locator?.json; href = evidence.locator?.href
        progression = evidence.locator?.progression; totalProgression = evidence.locator?.totalProgression
        textBefore = evidence.locator?.textBefore; textHighlight = evidence.locator?.textHighlight
        textAfter = evidence.locator?.textAfter
    }

    func domain() throws -> AgentResponseEvidence {
        guard let messageUUID = UUID(uuidString: messageID), let bookUUID = UUID(uuidString: bookID),
              let decodedKind = AgentEvidenceKind(rawValue: kind) else {
            throw PersistenceError.corruptRecord(table: Self.databaseTableName, recordID: "\(messageID):\(id)", field: "identity")
        }
        let locator: BookLocator?
        if let locatorJSON, let href {
            locator = try decodeLocator(
                json: locatorJSON, href: href, progression: progression, totalProgression: totalProgression,
                textBefore: textBefore, textHighlight: textHighlight, textAfter: textAfter,
                table: Self.databaseTableName, recordID: "\(messageID):\(id)"
            )
        } else { locator = nil }
        return .init(
            id: id, messageID: messageUUID, kind: decodedKind, sourceID: sourceID,
            bookID: .init(rawValue: bookUUID), title: title, excerpt: excerpt, locator: locator
        )
    }
}

private struct AgentCitationRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "agentCitations"
    var id, messageID, evidenceID, marker: String

    init(_ citation: AgentCitation) {
        id = citation.id.uuidString.lowercased(); messageID = citation.messageID.uuidString.lowercased()
        evidenceID = citation.evidenceID; marker = citation.marker
    }

    func domain() throws -> AgentCitation {
        guard let id = UUID(uuidString: id), let messageID = UUID(uuidString: messageID) else {
            throw PersistenceError.corruptRecord(table: Self.databaseTableName, recordID: self.id, field: "identity")
        }
        return .init(id: id, messageID: messageID, evidenceID: evidenceID, marker: marker)
    }
}

private struct ReflectionConnectionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "reflectionConnections"
    var id, reflectionID, sourceReflectionID: String
    var relevance: Double
    var createdAt: Date

    init(_ connection: ReflectionConnection) {
        id = connection.id.uuidString.lowercased()
        reflectionID = connection.reflectionID.description
        sourceReflectionID = connection.sourceReflectionID.description
        relevance = connection.relevance
        createdAt = connection.createdAt
    }

    func domain() throws -> ReflectionConnection {
        guard let id = UUID(uuidString: id),
              let reflectionID = UUID(uuidString: reflectionID),
              let sourceReflectionID = UUID(uuidString: sourceReflectionID) else {
            throw PersistenceError.corruptRecord(
                table: Self.databaseTableName, recordID: self.id, field: "identity"
            )
        }
        return ReflectionConnection(
            id: id,
            reflectionID: .init(rawValue: reflectionID),
            sourceReflectionID: .init(rawValue: sourceReflectionID),
            relevance: relevance,
            createdAt: createdAt
        )
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
        let start = try decodeLocator(json: startLocatorJSON, href: startHref, progression: startProgression, totalProgression: startTotalProgression, textBefore: startTextBefore, textHighlight: startTextHighlight, textAfter: startTextAfter, table: Self.databaseTableName, recordID: id)
        let end: BookLocator?
        if let json = endLocatorJSON, let href = endHref {
            end = try decodeLocator(json: json, href: href, progression: endProgression, totalProgression: endTotalProgression, textBefore: endTextBefore, textHighlight: endTextHighlight, textAfter: endTextAfter, table: Self.databaseTableName, recordID: id)
        } else { end = nil }
        return ReadingSession(
            id: .init(rawValue: try decodeUUID(id, table: Self.databaseTableName, recordID: id, field: "id")),
            bookID: .init(rawValue: try decodeUUID(bookID, table: Self.databaseTableName, recordID: id, field: "bookID")),
            startedAt: startedAt, endedAt: endedAt, startLocator: start, endLocator: end,
            highlightCount: highlightCount, noteCount: noteCount, agentDiscussionCount: agentDiscussionCount
        )
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
        get throws {
            let decodedSessionID: ReadingSessionID?
            if let sessionID {
                decodedSessionID = ReadingSessionID(rawValue: try decodeUUID(sessionID, table: Self.databaseTableName, recordID: id, field: "sessionID"))
            } else { decodedSessionID = nil }
            guard let decodedInputKind = ReflectionInputKind(rawValue: inputKind) else {
                throw PersistenceError.corruptRecord(table: Self.databaseTableName, recordID: id, field: "inputKind")
            }
            return Reflection(
                id: .init(rawValue: try decodeUUID(id, table: Self.databaseTableName, recordID: id, field: "id")),
                bookID: .init(rawValue: try decodeUUID(bookID, table: Self.databaseTableName, recordID: id, field: "bookID")),
                sessionID: decodedSessionID, originalText: originalText, inputKind: decodedInputKind,
                audioFileName: audioFileName, createdAt: createdAt
            )
        }
    }
}

private struct ReflectionMessageRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "reflectionMessages"
    var id, reflectionID, author, source, content: String
    var createdAt: Date
    init(_ message: ReflectionMessage) {
        id = message.id.uuidString.lowercased(); reflectionID = message.reflectionID.description
        author = message.author.rawValue; source = message.source.rawValue
        content = message.content; createdAt = message.createdAt
    }
    func domain() throws -> ReflectionMessage {
        guard let decodedAuthor = ReflectionMessageAuthor(rawValue: author) else {
            throw PersistenceError.corruptRecord(table: Self.databaseTableName, recordID: id, field: "author")
        }
        guard let decodedSource = ReflectionMessageSource(rawValue: source) else {
            throw PersistenceError.corruptRecord(table: Self.databaseTableName, recordID: id, field: "source")
        }
        do {
            return try ReflectionMessage(
                id: decodeUUID(id, table: Self.databaseTableName, recordID: id, field: "id"),
                reflectionID: .init(rawValue: decodeUUID(reflectionID, table: Self.databaseTableName, recordID: id, field: "reflectionID")),
                author: decodedAuthor, source: decodedSource, content: content, createdAt: createdAt
            )
        } catch is ReflectionValidationError {
            throw PersistenceError.corruptRecord(table: Self.databaseTableName, recordID: id, field: "author/source")
        }
    }
}

private struct ReflectionEvidenceRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "reflectionEvidence"
    var id, reflectionID, sourceType: String
    var sourceID: String?
    var locatorJSON: Data?
    var href: String?
    var progression, totalProgression: Double?
    var textBefore, textHighlight, textAfter: String?
    var createdAt: Date

    init(_ evidence: ReflectionEvidence) {
        id = evidence.id.uuidString.lowercased(); reflectionID = evidence.reflectionID.description
        sourceType = evidence.sourceType.rawValue; sourceID = evidence.sourceID
        locatorJSON = evidence.locator?.json; href = evidence.locator?.href
        progression = evidence.locator?.progression; totalProgression = evidence.locator?.totalProgression
        textBefore = evidence.locator?.textBefore; textHighlight = evidence.locator?.textHighlight
        textAfter = evidence.locator?.textAfter; createdAt = evidence.createdAt
    }

    func domain() throws -> ReflectionEvidence {
        guard let decodedSourceType = ReflectionEvidenceSourceType(rawValue: sourceType) else {
            throw PersistenceError.corruptRecord(table: Self.databaseTableName, recordID: id, field: "sourceType")
        }
        let locator: BookLocator?
        if let locatorJSON, let href {
            locator = try decodeLocator(json: locatorJSON, href: href, progression: progression, totalProgression: totalProgression, textBefore: textBefore, textHighlight: textHighlight, textAfter: textAfter, table: Self.databaseTableName, recordID: id)
        } else if locatorJSON == nil, href == nil {
            locator = nil
        } else {
            throw PersistenceError.corruptRecord(table: Self.databaseTableName, recordID: id, field: "locator")
        }
        do {
            return try ReflectionEvidence(
                id: decodeUUID(id, table: Self.databaseTableName, recordID: id, field: "id"),
                reflectionID: .init(rawValue: decodeUUID(reflectionID, table: Self.databaseTableName, recordID: id, field: "reflectionID")),
                sourceType: decodedSourceType, sourceID: sourceID, locator: locator, createdAt: createdAt
            )
        } catch is ReflectionValidationError {
            throw PersistenceError.corruptRecord(table: Self.databaseTableName, recordID: id, field: "provenance")
        }
    }
}

private func decodeUUID(_ value: String, table: String, recordID: String, field: String) throws -> UUID {
    guard let id = UUID(uuidString: value) else {
        throw PersistenceError.corruptRecord(table: table, recordID: recordID, field: field)
    }
    return id
}

private func decodeLocator(
    json: Data, href: String, progression: Double?, totalProgression: Double?,
    textBefore: String?, textHighlight: String?, textAfter: String?,
    table: String, recordID: String
) throws -> BookLocator {
    do {
        return try BookLocator(
            json: json, href: href, progression: progression, totalProgression: totalProgression,
            textBefore: textBefore, textHighlight: textHighlight, textAfter: textAfter
        )
    } catch {
        throw PersistenceError.corruptRecord(table: table, recordID: recordID, field: "locatorJSON")
    }
}

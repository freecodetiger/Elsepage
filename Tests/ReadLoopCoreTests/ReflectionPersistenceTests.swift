import Foundation
import GRDB
import LibraryCore
import Persistence
import ReaderCore
import ReadingSessionCore
import ReflectionCore
import Testing

@Test func migratesReaderDatabaseForwardToReflectionLoop() async throws {
    var configuration = Configuration(); configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try AppDatabase.migrator.migrate(queue, upTo: "v2_reader_preferences")
    let legacyBook = TestFixtures.book(fingerprint: "before-reflection")
    try await queue.write { db in
        try db.execute(
            sql: "INSERT INTO books (id, fingerprint, title, fileName, fileSize, importedAt) VALUES (?, ?, ?, ?, ?, ?)",
            arguments: [legacyBook.id.description, legacyBook.fingerprint.rawValue, legacyBook.title, legacyBook.fileName, legacyBook.fileSize, legacyBook.importedAt]
        )
    }

    let database = try AppDatabase(writer: queue)
    #expect(try await GRDBBookRepository(database: database).book(id: legacyBook.id) != nil)
    let tables = try await queue.read { db in
        try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
    }
    #expect(tables.contains("readingSessions"))
    #expect(tables.contains("reflections"))
    #expect(tables.contains("reflectionMessages"))
    #expect(tables.contains("reflectionHighlights"))
    #expect(tables.contains("reflectionEvidence"))
}

@Test func readingSessionRoundTripsAndCompletes() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book(); try await GRDBBookRepository(database: database).insert(book)
    let repository = GRDBReadingSessionRepository(database: database)
    let start = try TestFixtures.realisticLocator(progression: 0.2)
    let end = try TestFixtures.realisticLocator(progression: 0.4)
    let startedAt = Date(timeIntervalSince1970: 100)
    let session = ReadingSession(bookID: book.id, startedAt: startedAt, startLocator: start)
    try await repository.insert(session)
    try await repository.complete(id: session.id, endedAt: Date(timeIntervalSince1970: 400), endLocator: end, highlightCount: 2, noteCount: 1, agentDiscussionCount: 0)

    let stored = try #require(try await repository.session(id: session.id))
    #expect(stored.duration == 300)
    #expect(stored.endLocator == end)
    #expect(stored.highlightCount == 2)
    #expect(stored.noteCount == 1)
}

@Test func userReflectionAndDerivedMessagesRemainSeparate() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book(); try await GRDBBookRepository(database: database).insert(book)
    let repository = GRDBReflectionRepository(database: database)
    let reflection = Reflection(bookID: book.id, originalText: "This is what I actually thought.", inputKind: .text)
    try await repository.insert(reflection, linkedHighlightIDs: [], evidence: [])
    try await repository.appendMessage(try .init(reflectionID: reflection.id, author: .agent, source: .agentGenerated, content: "A generated interpretation"))

    #expect(try await repository.reflection(id: reflection.id)?.originalText == reflection.originalText)
    #expect(try await repository.messages(for: reflection.id).map(\.content) == ["A generated interpretation"])
}

@Test func reflectionInsertWithInvalidHighlightRollsBack() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book(); try await GRDBBookRepository(database: database).insert(book)
    let repository = GRDBReflectionRepository(database: database)
    let reflection = Reflection(bookID: book.id, originalText: "Keep this atomic", inputKind: .text)

    await #expect(throws: (any Error).self) {
        try await repository.insert(reflection, linkedHighlightIDs: [UUID()], evidence: [])
    }
    #expect(try await repository.reflection(id: reflection.id) == nil)
}

@Test func sessionDeletionPreservesReflectionAndNullsSessionLink() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book(); try await GRDBBookRepository(database: database).insert(book)
    let sessions = GRDBReadingSessionRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let session = ReadingSession(bookID: book.id, startLocator: try TestFixtures.realisticLocator())
    try await sessions.insert(session)
    let reflection = Reflection(bookID: book.id, sessionID: session.id, originalText: "Preserve my thought", inputKind: .voiceTranscript, audioFileName: "voice.m4a")
    try await reflections.insert(reflection, linkedHighlightIDs: [], evidence: [])

    try await sessions.delete(id: session.id)
    #expect(try await reflections.reflection(id: reflection.id)?.sessionID == nil)
    #expect(try await reflections.reflection(id: reflection.id)?.originalText == reflection.originalText)
}

@Test func deletingReflectionCascadesOnlyItsDerivedRowsAndLinks() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reading = GRDBReadingRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let book = TestFixtures.book(); try await books.insert(book)
    let highlight = Highlight(bookID: book.id, locator: try TestFixtures.realisticLocator())
    try await reading.save(highlight: highlight)
    let reflection = Reflection(bookID: book.id, originalText: "Source", inputKind: .text)
    let evidence = try ReflectionEvidence(reflectionID: reflection.id, sourceType: .highlight, sourceID: highlight.id.uuidString.lowercased())
    try await reflections.insert(reflection, linkedHighlightIDs: [highlight.id], evidence: [evidence])
    try await reflections.appendMessage(try .init(reflectionID: reflection.id, author: .agent, source: .agentGenerated, content: "Derived"))

    try await reflections.delete(id: reflection.id)
    #expect(try await reflections.messages(for: reflection.id).isEmpty)
    #expect(try await reflections.linkedHighlightIDs(for: reflection.id).isEmpty)
    #expect(try await reflections.evidence(for: reflection.id).isEmpty)
    #expect(try await reading.highlights(for: book.id).map(\.id) == [highlight.id])
}

@Test func deletingConversationTurnsIsStrictlyNewestFirstAndFinallyDeletesRoot() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book(); try await GRDBBookRepository(database: database).insert(book)
    let repository = GRDBReflectionRepository(database: database)
    let reflection = Reflection(bookID: book.id, originalText: "最初的想法", inputKind: .text)
    try await repository.insert(reflection, linkedHighlightIDs: [], evidence: [])

    let initialAgent = try ReflectionMessage(
        reflectionID: reflection.id, author: .agent, source: .agentGenerated,
        content: "第一次回应", createdAt: Date(timeIntervalSince1970: 1)
    )
    let firstFollowUp = try ReflectionMessage(
        reflectionID: reflection.id, author: .user, source: .userInput,
        content: "第一次追加", createdAt: Date(timeIntervalSince1970: 2)
    )
    let firstReply = try ReflectionMessage(
        reflectionID: reflection.id, author: .agent, source: .agentGenerated,
        content: "对第一次追加的回应", createdAt: Date(timeIntervalSince1970: 3)
    )
    let latestFollowUp = try ReflectionMessage(
        reflectionID: reflection.id, author: .user, source: .userInput,
        content: "最新追加", createdAt: Date(timeIntervalSince1970: 4)
    )
    let latestReply = try ReflectionMessage(
        reflectionID: reflection.id, author: .agent, source: .agentGenerated,
        content: "对最新追加的回应", createdAt: Date(timeIntervalSince1970: 5)
    )
    for message in [initialAgent, firstFollowUp, firstReply, latestFollowUp, latestReply] {
        try await repository.appendMessage(message)
    }

    #expect(try await repository.deleteLatestUserTurn(in: reflection.id) == .deletedFollowUp(latestFollowUp.id))
    #expect(try await repository.messages(for: reflection.id).map(\.id) == [initialAgent.id, firstFollowUp.id, firstReply.id])
    #expect(try await repository.deleteLatestUserTurn(in: reflection.id) == .deletedFollowUp(firstFollowUp.id))
    #expect(try await repository.messages(for: reflection.id).map(\.id) == [initialAgent.id])
    #expect(try await repository.deleteLatestUserTurn(in: reflection.id) == .deletedConversation)
    #expect(try await repository.reflection(id: reflection.id) == nil)
    #expect(try await repository.messages(for: reflection.id).isEmpty)
}

@Test func deletingBookCascadesSessionsAndReflections() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let sessions = GRDBReadingSessionRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let book = TestFixtures.book(); try await books.insert(book)
    let session = ReadingSession(bookID: book.id, startLocator: try TestFixtures.realisticLocator())
    try await sessions.insert(session)
    let reflection = Reflection(bookID: book.id, sessionID: session.id, originalText: "Delete with book", inputKind: .text)
    try await reflections.insert(reflection, linkedHighlightIDs: [], evidence: [])

    try await books.delete(book.id)
    #expect(try await sessions.session(id: session.id) == nil)
    #expect(try await reflections.reflection(id: reflection.id) == nil)
}

@Test func migratesV3FollowUpAsUserOwnedMessage() async throws {
    var configuration = Configuration(); configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try AppDatabase.migrator.migrate(queue, upTo: "v3_reflection_loop")
    let book = TestFixtures.book()
    let reflectionID = ReflectionID()
    let messageID = UUID()
    try await queue.write { db in
        try db.execute(
            sql: "INSERT INTO books (id, fingerprint, title, fileName, fileSize, importedAt) VALUES (?, ?, ?, ?, ?, ?)",
            arguments: [book.id.description, book.fingerprint.rawValue, book.title, book.fileName, book.fileSize, book.importedAt]
        )
        try db.execute(
            sql: "INSERT INTO reflections (id, bookID, originalText, inputKind, createdAt) VALUES (?, ?, ?, ?, ?)",
            arguments: [reflectionID.description, book.id.description, "Original", "text", Date()]
        )
        try db.execute(
            sql: "INSERT INTO reflectionMessages (id, reflectionID, role, content, createdAt) VALUES (?, ?, ?, ?, ?)",
            arguments: [messageID.uuidString.lowercased(), reflectionID.description, "userFollowUp", "My later thought", Date()]
        )
    }

    let database = try AppDatabase(writer: queue)
    let message = try #require(try await GRDBReflectionRepository(database: database).messages(for: reflectionID).first)
    #expect(message.author == .user)
    #expect(message.source == .userInput)
    #expect(message.isUserSourceOfTruth)
    #expect(message.content == "My later thought")
}

@Test func messageModelRejectsAgentAuthoredUserSource() throws {
    #expect(throws: ReflectionValidationError.inconsistentMessageProvenance) {
        try ReflectionMessage(
            reflectionID: ReflectionID(), author: .agent, source: .userInput, content: "invalid"
        )
    }
}

@Test func reflectionEvidenceRoundTripsStableIDAndFullLocator() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book(); try await GRDBBookRepository(database: database).insert(book)
    let repository = GRDBReflectionRepository(database: database)
    let reflection = Reflection(bookID: book.id, originalText: "Evidence matters", inputKind: .text)
    let locator = try TestFixtures.realisticLocator()
    let highlight = Highlight(bookID: book.id, locator: locator)
    try await GRDBReadingRepository(database: database).save(highlight: highlight)
    let evidence = [
        try ReflectionEvidence(reflectionID: reflection.id, sourceType: .highlight, sourceID: highlight.id.uuidString.lowercased()),
        try ReflectionEvidence(reflectionID: reflection.id, sourceType: .bookLocator, locator: locator),
    ]
    try await repository.insert(reflection, linkedHighlightIDs: [], evidence: evidence)

    let stored = try await repository.evidence(for: reflection.id)
    #expect(stored.count == 2)
    let storedID = try #require(stored.first { $0.sourceType == .highlight })
    let storedLocator = try #require(stored.first { $0.sourceType == .bookLocator })
    #expect(storedID.sourceID == evidence[0].sourceID)
    #expect(storedLocator.locator?.json == locator.json)
}

@Test func reflectionEvidenceRejectsSourceFromAnotherBook() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reading = GRDBReadingRepository(database: database)
    let firstBook = TestFixtures.book(fingerprint: "evidence-first")
    let secondBook = TestFixtures.book(fingerprint: "evidence-second")
    try await books.insert(firstBook); try await books.insert(secondBook)
    let highlight = Highlight(bookID: secondBook.id, locator: try TestFixtures.realisticLocator())
    try await reading.save(highlight: highlight)
    let repository = GRDBReflectionRepository(database: database)
    let reflection = Reflection(bookID: firstBook.id, originalText: "Wrong book", inputKind: .text)
    let evidence = try ReflectionEvidence(
        reflectionID: reflection.id, sourceType: .highlight,
        sourceID: highlight.id.uuidString.lowercased()
    )

    await #expect(throws: (any Error).self) {
        try await repository.insert(reflection, linkedHighlightIDs: [], evidence: [evidence])
    }
    #expect(try await repository.reflection(id: reflection.id) == nil)
}

@Test func reflectionAndEvidenceInsertRollBackTogether() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book(); try await GRDBBookRepository(database: database).insert(book)
    let repository = GRDBReflectionRepository(database: database)
    let reflection = Reflection(bookID: book.id, originalText: "Atomic source", inputKind: .text)
    let wrongEvidence = try ReflectionEvidence(
        reflectionID: ReflectionID(), sourceType: .readingSession, sourceID: ReadingSessionID().description
    )

    await #expect(throws: (any Error).self) {
        try await repository.insert(reflection, linkedHighlightIDs: [], evidence: [wrongEvidence])
    }
    #expect(try await repository.reflection(id: reflection.id) == nil)
}

@Test func foreignKeysRejectOrphanReflectionEvidence() async throws {
    let database = try AppDatabase.inMemory()
    let repository = GRDBReflectionRepository(database: database)
    let evidence = try ReflectionEvidence(
        reflectionID: ReflectionID(), sourceType: .note, sourceID: UUID().uuidString.lowercased()
    )
    await #expect(throws: (any Error).self) { try await repository.appendEvidence(evidence) }
}

@Test func corruptMessageRowThrowsExplicitPersistenceError() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book(); try await GRDBBookRepository(database: database).insert(book)
    let repository = GRDBReflectionRepository(database: database)
    let reflection = Reflection(bookID: book.id, originalText: "Source", inputKind: .text)
    try await repository.insert(reflection, linkedHighlightIDs: [], evidence: [])
    try await database.writer.write { db in
        try db.execute(
            sql: "INSERT INTO reflectionMessages (id, reflectionID, author, source, content, createdAt) VALUES (?, ?, ?, ?, ?, ?)",
            arguments: ["not-a-uuid", reflection.id.description, "agent", "agentGenerated", "bad row", Date()]
        )
    }

    do {
        _ = try await repository.messages(for: reflection.id)
        Issue.record("Expected corrupt row to throw")
    } catch let error as Persistence.PersistenceError {
        guard case let .corruptRecord(table, recordID, field) = error else {
            Issue.record("Unexpected persistence error: \(error)"); return
        }
        #expect(table == "reflectionMessages"); #expect(recordID == "not-a-uuid"); #expect(field == "id")
    }
}

@Test func corruptEvidenceLocatorThrowsExplicitPersistenceError() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book(); try await GRDBBookRepository(database: database).insert(book)
    let repository = GRDBReflectionRepository(database: database)
    let reflection = Reflection(bookID: book.id, originalText: "Source", inputKind: .text)
    try await repository.insert(reflection, linkedHighlightIDs: [], evidence: [])
    let evidenceID = UUID().uuidString.lowercased()
    try await database.writer.write { db in
        try db.execute(
            sql: "INSERT INTO reflectionEvidence (id, reflectionID, sourceType, locatorJSON, href, createdAt) VALUES (?, ?, ?, ?, ?, ?)",
            arguments: [evidenceID, reflection.id.description, "bookLocator", Data("invalid".utf8), "chapter.xhtml", Date()]
        )
    }

    do {
        _ = try await repository.evidence(for: reflection.id)
        Issue.record("Expected corrupt evidence to throw")
    } catch let error as Persistence.PersistenceError {
        guard case let .corruptRecord(table, recordID, field) = error else {
            Issue.record("Unexpected persistence error: \(error)"); return
        }
        #expect(table == "reflectionEvidence"); #expect(recordID == evidenceID); #expect(field == "locatorJSON")
    }
}

@Test func polishedTextRoundTripsAndDisplayTextPrefersPolished() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let book = TestFixtures.book(); try await books.insert(book)
    let repository = GRDBReflectionRepository(database: database)
    let reflection = Reflection(
        bookID: book.id,
        originalText: "原始 口述 乱句",
        inputKind: .voiceTranscript,
        polishedText: "整理后的文字",
        createdAt: Date(timeIntervalSince1970: 50)
    )
    try await repository.insert(reflection, linkedHighlightIDs: [], evidence: [])
    let loaded = try #require(try await repository.reflection(id: reflection.id))
    #expect(loaded.originalText == "原始 口述 乱句")
    #expect(loaded.polishedText == "整理后的文字")
    #expect(loaded.displayText == "整理后的文字")
    let plain = Reflection(bookID: book.id, originalText: "普通文字", inputKind: .text)
    #expect(plain.displayText == "普通文字")
}

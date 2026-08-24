#if canImport(ReadingSessionCore) && canImport(ReflectionCore)
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
    try await repository.insert(reflection, linkedHighlightIDs: [])
    try await repository.appendDerivedMessage(.init(reflectionID: reflection.id, role: .agent, content: "A generated interpretation"))

    #expect(try await repository.reflection(id: reflection.id)?.originalText == reflection.originalText)
    #expect(try await repository.derivedMessages(for: reflection.id).map(\.content) == ["A generated interpretation"])
}

@Test func reflectionInsertWithInvalidHighlightRollsBack() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book(); try await GRDBBookRepository(database: database).insert(book)
    let repository = GRDBReflectionRepository(database: database)
    let reflection = Reflection(bookID: book.id, originalText: "Keep this atomic", inputKind: .text)

    await #expect(throws: (any Error).self) {
        try await repository.insert(reflection, linkedHighlightIDs: [UUID()])
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
    try await reflections.insert(reflection, linkedHighlightIDs: [])

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
    try await reflections.insert(reflection, linkedHighlightIDs: [highlight.id])
    try await reflections.appendDerivedMessage(.init(reflectionID: reflection.id, role: .agent, content: "Derived"))

    try await reflections.delete(id: reflection.id)
    #expect(try await reflections.derivedMessages(for: reflection.id).isEmpty)
    #expect(try await reflections.linkedHighlightIDs(for: reflection.id).isEmpty)
    #expect(try await reading.highlights(for: book.id).map(\.id) == [highlight.id])
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
    try await reflections.insert(reflection, linkedHighlightIDs: [])

    try await books.delete(book.id)
    #expect(try await sessions.session(id: session.id) == nil)
    #expect(try await reflections.reflection(id: reflection.id) == nil)
}
#endif

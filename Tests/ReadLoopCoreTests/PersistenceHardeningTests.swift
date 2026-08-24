import Foundation
import GRDB
import LibraryCore
import Persistence
import ReaderCore
import Testing

@Test func migratesV1DatabaseForwardWithoutChangingExistingBook() async throws {
    var configuration = Configuration(); configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try AppDatabase.migrator.migrate(queue, upTo: "v1_reader_foundation")
    let book = TestFixtures.book(fingerprint: "legacy")
    try await queue.write { db in
        try db.execute(
            sql: "INSERT INTO books (id, fingerprint, title, fileName, fileSize, importedAt) VALUES (?, ?, ?, ?, ?, ?)",
            arguments: [book.id.description, book.fingerprint.rawValue, book.title, book.fileName, book.fileSize, book.importedAt]
        )
    }
    let database = try AppDatabase(writer: queue)
    let books = GRDBBookRepository(database: database)
    let reading = GRDBReadingRepository(database: database)
    #expect(try await books.book(id: book.id)?.fingerprint == book.fingerprint)
    #expect(try await reading.preferences(for: book.id) == .default)
    let migrations = try await queue.read { db in try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid") }
    #expect(migrations == ["v1_reader_foundation", "v2_reader_preferences", "v3_reflection_loop", "v4_reflection_provenance"])
}

@Test func bookDeletionCascadesPositionHighlightsNotesAndPreferences() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reading = GRDBReadingRepository(database: database)
    let book = TestFixtures.book(); try await books.insert(book)
    let locator = try TestFixtures.realisticLocator()
    let highlight = Highlight(bookID: book.id, locator: locator)
    try await reading.save(position: .init(bookID: book.id, locator: locator))
    try await reading.save(highlight: highlight)
    try await reading.save(note: .init(bookID: book.id, highlightID: highlight.id, locator: locator, body: "User note"))
    try await reading.save(preferences: .init(theme: .sepia, fontSize: 1.2, lineHeight: 1.1, pageMargins: 0.8, readingMode: .scroll), for: book.id)
    try await books.delete(book.id)
    #expect(try await reading.position(for: book.id) == nil)
    #expect(try await reading.highlights(for: book.id).isEmpty)
    #expect(try await reading.notes(for: book.id).isEmpty)
    let preferenceRows = try await database.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM readerPreferences") }
    #expect(preferenceRows == 0)
}

@Test func foreignKeysRejectOrphanReaderData() async throws {
    let database = try AppDatabase.inMemory()
    let reading = GRDBReadingRepository(database: database)
    let missingBook = BookID()
    await #expect(throws: (any Error).self) { try await reading.save(position: .init(bookID: missingBook, locator: try TestFixtures.realisticLocator())) }
    await #expect(throws: (any Error).self) { try await reading.save(highlight: .init(bookID: missingBook, locator: try TestFixtures.realisticLocator())) }
    await #expect(throws: (any Error).self) { try await reading.save(note: .init(bookID: missingBook, locator: try TestFixtures.realisticLocator(), body: "orphan")) }
}

@Test func linkedHighlightAndNoteWriteRollsBackAsOneTransaction() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reading = GRDBReadingRepository(database: database)
    let book = TestFixtures.book(); try await books.insert(book)
    let locator = try TestFixtures.realisticLocator()
    let duplicateNoteID = UUID()
    try await reading.save(note: .init(id: duplicateNoteID, bookID: book.id, locator: locator, body: "existing"))
    let highlight = Highlight(bookID: book.id, locator: locator)
    let collidingNote = Note(id: duplicateNoteID, bookID: book.id, highlightID: highlight.id, locator: locator, body: "collision")
    await #expect(throws: (any Error).self) { try await reading.save(highlight: highlight, note: collidingNote) }
    #expect(try await reading.highlights(for: book.id).isEmpty)
    #expect(try await reading.notes(for: book.id).count == 1)
}

@Test func readerPreferencesPersistAndDefaultPerBook() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reading = GRDBReadingRepository(database: database)
    let book = TestFixtures.book(); try await books.insert(book)
    #expect(try await reading.preferences(for: book.id) == .default)
    let preferences = ReaderPreferences(theme: .dark, fontSize: 1.25, lineHeight: 1.15, pageMargins: 0.75, readingMode: .scroll)
    try await reading.save(preferences: preferences, for: book.id)
    #expect(try await reading.preferences(for: book.id) == preferences)
}

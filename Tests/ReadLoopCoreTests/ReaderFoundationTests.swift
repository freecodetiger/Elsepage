import Foundation
import Testing
import AppInfrastructure
import LibraryCore
import Persistence
import ReaderCore

private func locator(_ value: Double = 0.25) throws -> BookLocator {
    let data = try JSONSerialization.data(withJSONObject: [
        "href": "chapter1.xhtml",
        "type": "application/xhtml+xml",
        "locations": ["progression": value, "totalProgression": value],
        "text": ["before": "before", "highlight": "chosen words", "after": "after"],
    ])
    return try BookLocator(json: data, href: "chapter1.xhtml", progression: value, totalProgression: value, textBefore: "before", textHighlight: "chosen words", textAfter: "after")
}

private func makeBook(fingerprint: String = "abc") -> Book {
    Book(fingerprint: .init(rawValue: fingerprint), title: "A Book", fileName: "book.epub", fileSize: 3)
}

@Test func migrationCreatesReaderFoundationSchemaAndEnablesForeignKeys() throws {
    let database = try AppDatabase.inMemory()
    let tables = try database.writer.read { db in try Set(String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")) }
    #expect(tables.isSuperset(of: ["books", "readingPositions", "highlights", "notes", "grdb_migrations"]))
    let foreignKeys = try database.writer.read { db in try Int.fetchOne(db, sql: "PRAGMA foreign_keys") }
    #expect(foreignKeys == 1)
}

@Test func bookIdentityIsStableAndFingerprintIsUnique() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let first = makeBook(fingerprint: "AABB")
    try await books.insert(first)
    let restored = try #require(try await books.book(id: first.id))
    #expect(restored.id == first.id)
    #expect(restored.fingerprint == first.fingerprint)
    #expect(restored.title == first.title)
    #expect(try await books.book(fingerprint: .init(rawValue: "aabb"))?.id == first.id)
    await #expect(throws: (any Error).self) { try await books.insert(makeBook(fingerprint: "aabb")) }
}

@Test func locatorRoundTripsAndNewPositionReplacesOldPosition() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reading = GRDBReadingRepository(database: database)
    let book = makeBook(); try await books.insert(book)
    try await reading.save(position: .init(bookID: book.id, locator: try locator(0.2)))
    let latestLocator = try locator(0.8)
    try await reading.save(position: .init(bookID: book.id, locator: latestLocator))
    let restored = try await reading.position(for: book.id)
    #expect(restored?.locator.progression == 0.8)
    #expect(restored?.locator.textHighlight == "chosen words")
    #expect(restored?.locator.json == latestLocator.json)
}

@Test func highlightDeletionKeepsNoteAnchorAndClearsOnlyRelationship() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reading = GRDBReadingRepository(database: database)
    let book = makeBook(); try await books.insert(book)
    let highlight = Highlight(bookID: book.id, locator: try locator())
    try await reading.save(highlight: highlight)
    let note = Note(bookID: book.id, highlightID: highlight.id, locator: highlight.locator, body: "My thought")
    try await reading.save(note: note)
    try await reading.deleteHighlight(id: highlight.id)
    let saved = try #require(try await reading.notes(for: book.id).first)
    #expect(saved.highlightID == nil)
    #expect(saved.locator == note.locator)
    #expect(saved.body == "My thought")
}

@Test func contentFingerprintIsStreamingStableAndImportDeduplicates() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let sourceA = root.appendingPathComponent("one.epub")
    let sourceB = root.appendingPathComponent("renamed.epub")
    let payload = Data([0x50, 0x4b, 0x03, 0x04]) + Data("mimetype application/epub+zip identity fixture".utf8)
    try payload.write(to: sourceA); try payload.write(to: sourceB)
    let database = try AppDatabase.inMemory()
    let repository = GRDBBookRepository(database: database)
    let store = try BookFileStore(directory: root.appendingPathComponent("Books"))
    #expect(try store.fingerprint(of: sourceA) == store.fingerprint(of: sourceB))
    let importer = BookImporter(repository: repository, files: store)
    let first = try await importer.importEPUB(at: sourceA)
    let second = try await importer.importEPUB(at: sourceB)
    guard case .imported(let imported) = first, case .duplicate(let duplicate) = second else {
        Issue.record("Expected imported then duplicate"); return
    }
    #expect(imported.id == duplicate.id)
    #expect(try await repository.allBooks().count == 1)
    #expect(FileManager.default.fileExists(atPath: store.url(for: imported.id).path))
}

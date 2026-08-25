import Foundation
import GRDB
import LibraryCore
import ModelProviders
import Persistence
import ReaderCore
import ReflectionCore
import Testing

@Test func providerConfigurationPersistsOnlyNonSecretFieldsAndCanBeDeleted() async throws {
    let database = try AppDatabase.inMemory()
    let repository = GRDBProviderConfigurationRepository(database: database)
    let reference = SecretReference(rawValue: "primary-provider-key")
    let configuration = ProviderConfiguration(
        provider: .openAICompatible,
        baseURL: URL(string: "https://api.example.com/v1")!,
        modelID: "example-chat",
        secretReference: reference,
        streamingEnabled: false
    )

    try await repository.save(configuration)
    #expect(try await repository.currentConfiguration() == configuration)

    let columns = try await database.writer.read { db in
        try Row.fetchAll(db, sql: "PRAGMA table_info(providerConfigurations)")
            .map { row in String.fromDatabaseValue(row["name"])! }
    }
    #expect(columns.sorted() == [
        "baseURL", "embeddingModelID", "id", "modelID", "provider", "secretReference", "streamingEnabled"
    ])
    #expect(!columns.contains("apiKey"))

    try await repository.deleteCurrentConfiguration()
    #expect(try await repository.currentConfiguration() == nil)
}

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
    #expect(migrations == [
        "v1_reader_foundation", "v2_reader_preferences", "v3_reflection_loop",
        "v4_reflection_provenance", "v5_model_provider_configuration", "v6_reflection_connections",
        "v7_local_book_retrieval", "v8_agent_citations", "v9_routing_trace", "v10_journal",
        "v11_polished_text", "v12_memory", "v13_embedding_config"
    ])
}

@Test func migratesV12DatabaseToV13WithoutLosingData() async throws {
    // A database created under v12 (Memory phase) must upgrade to v13 (embedding
    // config columns) without deletion, keeping the pre-existing provider config
    // and book index job rows intact.
    var configuration = Configuration(); configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try AppDatabase.migrator.migrate(queue, upTo: "v12_memory")

    let reference = SecretReference(rawValue: "legacy-provider-key")
    try await queue.write { db in
        try db.execute(
            sql: "INSERT INTO providerConfigurations (id, provider, baseURL, modelID, secretReference, streamingEnabled) VALUES (?,?,?,?,?,?)",
            arguments: ["00000000-0000-0000-0000-000000000001", "openAICompatible", "https://api.example.com/v1", "legacy-chat", reference.rawValue, 1]
        )
        try db.execute(
            sql: "INSERT INTO books (id, fingerprint, title, fileName, fileSize, importedAt) VALUES (?,?,?,?,?,?)",
            arguments: ["00000000-0000-0000-0000-000000000002", "legacy-book", "Legacy", "legacy.epub", 100, Date()]
        )
        try db.execute(
            sql: "INSERT INTO bookIndexJobs (bookID, indexVersion, state, nextResourceOrdinal, lastError, updatedAt) VALUES (?,?,?,?,?,?)",
            arguments: ["00000000-0000-0000-0000-000000000002", 1, "lexicalReady", 5, nil, Date()]
        )
    }

    try AppDatabase.migrator.migrate(queue)
    let repo = GRDBProviderConfigurationRepository(database: try AppDatabase(writer: queue))
    let config = try await repo.currentConfiguration()
    #expect(config?.modelID == "legacy-chat")
    #expect(config?.embeddingModelID == nil)

    let jobRow = try await queue.read { db in
        try Row.fetchOne(db, sql: "SELECT state, embeddingModel FROM bookIndexJobs WHERE bookID=?", arguments: ["00000000-0000-0000-0000-000000000002"])
    }
    #expect(jobRow.flatMap { String.fromDatabaseValue($0["state"]) } == "lexicalReady")
    #expect(jobRow.flatMap { String.fromDatabaseValue($0["embeddingModel"]) } == nil)
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

@Test func libraryPositionLookupReturnsOnlyRequestedBooks() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reading = GRDBReadingRepository(database: database)
    let included = TestFixtures.book(fingerprint: "included")
    let excluded = TestFixtures.book(fingerprint: "excluded")
    try await books.insert(included)
    try await books.insert(excluded)
    try await reading.save(position: .init(bookID: included.id, locator: try TestFixtures.realisticLocator()))
    try await reading.save(position: .init(bookID: excluded.id, locator: try TestFixtures.realisticLocator()))

    let positions = try await reading.positions(for: [included.id])
    #expect(positions[included.id]?.bookID == included.id)
    #expect(positions[excluded.id] == nil)
}

@Test func preRenumberedDevDatabaseUpgradesWithoutDeletion() async throws {
    // A dev database built during the v8_pending_* era already has the P0 tables and
    // recorded the old migration identifiers. Upgrading to the renumbered migrations
    // (v8_agent_citations/v9_routing_trace/v10_journal) must no-op on the existing
    // tables via ifNotExists and still reach v11_polished_text — no deletion needed.
    var configuration = Configuration(); configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try AppDatabase.migrator.migrate(queue, upTo: "v7_local_book_retrieval")

    try await queue.write { db in
        for name in ["v8_pending_citations", "v8_pending_router_trace", "v8_pending_journal"] {
            try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)", arguments: [name])
        }
    }

    try AppDatabase.migrator.migrate(queue)
    let identifiers = try await queue.read { db in
        try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid")
    }
    #expect(identifiers.contains("v8_agent_citations"))
    #expect(identifiers.contains("v9_routing_trace"))
    #expect(identifiers.contains("v10_journal"))
    #expect(identifiers.contains("v11_polished_text"))
}

@Test func v11DatabaseUpgradesToV12MemoryWithoutDeletion() async throws {
    // A database created before v12 (e.g. an installed v1–v11 build) must upgrade
    // to the memories table additively, preserving existing books/reflections and
    // the already-derived journalMemoryChanges rows.
    var configuration = Configuration(); configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try AppDatabase.migrator.migrate(queue, upTo: "v11_polished_text")

    let book = TestFixtures.book(fingerprint: "v11-upgrade")
    let reflectionID = UUID().uuidString.lowercased()
    try await queue.write { db in
        try db.execute(
            sql: "INSERT INTO books (id, fingerprint, title, fileName, fileSize, importedAt) VALUES (?, ?, ?, ?, ?, ?)",
            arguments: [book.id.description, book.fingerprint.rawValue, book.title, book.fileName, book.fileSize, book.importedAt]
        )
        try db.execute(
            sql: "INSERT INTO reflections (id, bookID, originalText, inputKind, createdAt) VALUES (?, ?, ?, 'text', ?)",
            arguments: [reflectionID, book.id.description, "升级前的旧想法", Date()]
        )
        try db.execute(
            sql: "INSERT INTO journalMemoryChanges (id, journalID, changeType, summary, createdAt) VALUES (?, ?, 'store', ?, ?)",
            arguments: [UUID().uuidString.lowercased(), reflectionID, "用户重视自由", Date()]
        )
    }

    // Upgrade to head (v12_memory).
    try AppDatabase.migrator.migrate(queue)
    let database = try AppDatabase(writer: queue)

    // v12 memories table exists (and starts empty — nothing has consumed proposals yet).
    let tables = try await database.writer.read { db in
        try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'memories'")
    }
    #expect(tables == ["memories"])
    #expect(try await GRDBMemoryRepository(database: database).memories().isEmpty)

    // Pre-existing data is intact.
    #expect(try await GRDBBookRepository(database: database).book(id: book.id) != nil)
    let reflections = try await GRDBReflectionRepository(database: database).reflections(for: book.id)
    #expect(reflections.count == 1)
    #expect(try await GRDBJournalRepository(database: database).memoryChanges(for: reflections[0].id).count == 1)
}

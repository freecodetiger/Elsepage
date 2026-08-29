import AppInfrastructure
import Foundation
import LibraryCore
import ModelProviders
import Persistence
import ReaderCore
import ReadingSessionCore
import ReflectionCore
import RetrievalCore
import Testing

@Test func exportIncludesUserDataAndExcludesProviderSecrets() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reading = GRDBReadingRepository(database: database)
    let sessions = GRDBReadingSessionRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let journal = GRDBJournalRepository(database: database)

    // A configured provider with a secret must NOT leak into the export.
    let configurations = GRDBProviderConfigurationRepository(database: database)
    try await configurations.save(ProviderConfiguration(
        provider: .openAICompatible,
        baseURL: URL(string: "https://api.example.com/v1")!,
        modelID: "example-chat",
        secretReference: SecretReference(rawValue: "primary-provider-key"),
    ))

    let book = TestFixtures.book(fingerprint: "export-book")
    try await books.insert(book)
    let locator = try TestFixtures.realisticLocator()
    try await reading.save(position: .init(bookID: book.id, locator: locator))
    let highlight = Highlight(bookID: book.id, locator: locator)
    try await reading.save(highlight: highlight)
    try await reading.save(note: .init(bookID: book.id, highlightID: highlight.id, locator: locator, body: "我的笔记"))
    try await reading.save(preferences: .init(theme: .sepia, fontSize: 1.1, lineHeight: 1.2, pageMargins: 1.0, readingMode: .scroll), for: book.id)

    let session = ReadingSession(bookID: book.id, startLocator: try TestFixtures.realisticLocator(progression: 0.1))
    try await sessions.insert(session)

    let first = Reflection(bookID: book.id, sessionID: session.id, originalText: "我的反思原文", inputKind: .text)
    let evidence = try ReflectionEvidence(reflectionID: first.id, sourceType: .bookLocator, locator: locator)
    try await reflections.insert(first, linkedHighlightIDs: [highlight.id], evidence: [evidence])
    try await reflections.appendMessage(try ReflectionMessage(reflectionID: first.id, author: .user, source: .userInput, content: "用户追问", createdAt: Date(timeIntervalSince1970: 100)))
    let agentMessage = try ReflectionMessage(reflectionID: first.id, author: .agent, source: .agentGenerated, content: "Agent 回应", createdAt: Date(timeIntervalSince1970: 200))
    try await reflections.appendMessage(agentMessage)
    let second = Reflection(bookID: book.id, originalText: "另一条想法", inputKind: .text)
    try await reflections.insert(second, linkedHighlightIDs: [], evidence: [])
    try await reflections.saveConnection(.init(reflectionID: first.id, sourceReflectionID: second.id, relevance: 0.8))
    try await journal.saveThought(.init(reflectionID: first.id, messageID: agentMessage.id, thought: "我想记住这句话"))

    let exporter = PersonalDataExporter(
        books: books, reading: reading, sessions: sessions, reflections: reflections,
        journal: journal, memories: GRDBMemoryRepository(database: database)
    )
    let data = try await exporter.export()

    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let archive = try decoder.decode(PersonalDataArchive.self, from: data)
    #expect(archive.books.count == 1)
    let entry = archive.books[0]
    #expect(entry.book.title == book.title)
    #expect(entry.readingPosition != nil)
    #expect(entry.highlights.map(\.id) == [highlight.id])
    #expect(entry.notes.map(\.body) == ["我的笔记"])
    #expect(entry.preferences.theme == .sepia)
    #expect(entry.preferences.readingMode == .scroll)
    #expect(entry.sessions.map(\.id) == [session.id])
    #expect(entry.reflections.count == 2)

    let firstEntry = try #require(entry.reflections.first { $0.reflection.id == first.id })
    #expect(firstEntry.reflection.originalText == "我的反思原文")
    #expect(firstEntry.messages.map(\.content) == ["用户追问", "Agent 回应"])
    #expect(firstEntry.evidence.count == 1)
    #expect(firstEntry.connections.count == 1)
    #expect(firstEntry.thoughts.map(\.thought) == ["我想记住这句话"])

    let text = String(decoding: data, as: UTF8.self)
    #expect(!text.contains("apiKey"))
    #expect(!text.contains("secretReference"))
    #expect(!text.contains("api_key"))
}

@Test func deletingBookRemovesDatabaseIndexJobAndSandboxFile() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let index = GRDBBookIndexRepository(database: database)
    let book = TestFixtures.book(fingerprint: "delete-with-index")
    try await books.insert(book)
    try await index.save(job: BookIndexJob(bookID: book.id, indexVersion: BookIndexPipeline.currentVersion, state: .ready))

    let tempDir = try TestFixtures.temporaryDirectory()
    let store = try BookFileStore(directory: tempDir.appendingPathComponent("Books"))
    try Data("dummy epub".utf8).write(to: store.url(for: book.id))
    #expect(FileManager.default.fileExists(atPath: store.url(for: book.id).path))

    // Same two-phase trash flow used by LibraryModel/deleteAllBooks.
    let trashed = try #require(try store.stageDeletion(bookID: book.id))
    try await books.delete(book.id)
    store.commitDeletion(trashed)

    #expect(try await books.book(id: book.id) == nil)
    #expect(try await index.job(for: book.id, version: BookIndexPipeline.currentVersion) == nil)
    #expect(!FileManager.default.fileExists(atPath: store.url(for: book.id).path))
}

@Test func exportIncludesMemoriesAndReaderProfileProjection() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reading = GRDBReadingRepository(database: database)
    let sessions = GRDBReadingSessionRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let journal = GRDBJournalRepository(database: database)
    let memories = GRDBMemoryRepository(database: database)

    let book = TestFixtures.book(fingerprint: "export-memories")
    try await books.insert(book)

    let now = Date(timeIntervalSince1970: 1_000_000)
    let trait = ReaderMemory(
        kind: .profileTrait, claim: "读者常在深夜阅读", confidence: 0.9, status: .active,
        evidenceIDs: ["refl:e1"], createdAt: now, updatedAt: now.addingTimeInterval(30)
    )
    let edited = ReaderMemory(
        kind: .semantic, claim: "用户自己修正过的理解", confidence: 0.7, status: .provisional,
        userEdited: true, evidenceIDs: ["refl:e1", "msg:e2"], createdAt: now, updatedAt: now.addingTimeInterval(20)
    )
    let superseded = ReaderMemory(
        kind: .preference, claim: "已被否定的偏好", confidence: 0.4, status: .superseded,
        createdAt: now, updatedAt: now.addingTimeInterval(10)
    )
    let episodic = ReaderMemory(
        kind: .episodic, claim: "正在读的一本书", confidence: 0.5,
        createdAt: now, updatedAt: now
    )
    for memory in [trait, edited, superseded, episodic] {
        try await memories.save(memory)
    }

    let exporter = PersonalDataExporter(
        books: books, reading: reading, sessions: sessions, reflections: reflections,
        journal: journal, memories: memories
    )
    let data = try await exporter.export()

    // Round-trip: every exported memory equals its stored value, all fields included.
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let archive = try decoder.decode(PersonalDataArchive.self, from: data)
    let stored = try await memories.memories()
    #expect(archive.books.count == 1)
    #expect(archive.memories.count == 4)
    #expect(archive.memories.sorted { $0.id.uuidString < $1.id.uuidString } == stored.sorted { $0.id.uuidString < $1.id.uuidString })

    // The Reader Profile section is exactly the projection My Mind renders.
    let projection = ReaderProfileProjection(memories: stored)
    #expect(archive.readerProfile.profileTraits.map(\.id) == projection.profileTraits.map(\.id))
    #expect(archive.readerProfile.activeMemories.map(\.id) == projection.activeMemories.map(\.id))
    #expect(archive.readerProfile.supersededMemories.map(\.id) == projection.supersededMemories.map(\.id))
    #expect(archive.readerProfile.profileTraits.map(\.claim).sorted() == ["读者常在深夜阅读", "用户自己修正过的理解"].sorted())
    #expect(archive.readerProfile.supersededMemories.map(\.claim) == ["已被否定的偏好"])

    // My Mind-visible fields appear in the JSON; secrets never do.
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("userEdited"))
    #expect(text.contains("evidenceIDs"))
    #expect(text.contains("confidence"))
    #expect(text.contains("readerProfile"))
    #expect(!text.contains("secretReference"))
    #expect(!text.contains("apiKey"))
}

@Test func wipedStoreExportsEmptyButValidArchive() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reading = GRDBReadingRepository(database: database)
    let sessions = GRDBReadingSessionRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let journal = GRDBJournalRepository(database: database)
    let memories = GRDBMemoryRepository(database: database)

    let book = TestFixtures.book(fingerprint: "wipe-then-export")
    try await books.insert(book)
    try await memories.save(ReaderMemory(kind: .semantic, claim: "擦除前的记忆", confidence: 0.5))

    try await database.wipeAllUserData()

    let exporter = PersonalDataExporter(
        books: books, reading: reading, sessions: sessions, reflections: reflections,
        journal: journal, memories: memories
    )
    let data = try await exporter.export()

    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let archive = try decoder.decode(PersonalDataArchive.self, from: data)
    #expect(archive.books.isEmpty)
    #expect(archive.memories.isEmpty)
    #expect(archive.readerProfile.profileTraits.isEmpty)
    #expect(archive.readerProfile.activeMemories.isEmpty)
    #expect(archive.readerProfile.supersededMemories.isEmpty)
    #expect(archive.exportedAt <= Date())
}

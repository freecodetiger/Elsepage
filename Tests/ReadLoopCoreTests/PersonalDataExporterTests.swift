import AppInfrastructure
import BrainCore
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
    let brain = GRDBBrainRepository(database: database)

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
    try await brain.save(.memory(BrainMemory(
        id: .init(rawValue: "export-memory"), content: "用户偏好晚间阅读",
        origin: .agentInferred, confidence: .high, state: .active,
        provenance: BrainProvenance(originEvidence: nil), createdAt: Date(), updatedAt: Date()
    )))

    let exporter = PersonalDataExporter(
        books: books, reading: reading, sessions: sessions, reflections: reflections,
        journal: journal, brain: brain
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

    // The brain section round-trips the seeded memory.
    #expect(archive.brain.memories.map(\.id) == ["export-memory"])
    #expect(archive.brain.memories.map(\.content) == ["用户偏好晚间阅读"])
    #expect(archive.brain.memories.map(\.origin) == ["agentInferred"])

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

@Test func exportIncludesBrainItemsAndRelations() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reading = GRDBReadingRepository(database: database)
    let sessions = GRDBReadingSessionRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let journal = GRDBJournalRepository(database: database)
    let brain = GRDBBrainRepository(database: database)

    let book = TestFixtures.book(fingerprint: "export-brain")
    try await books.insert(book)

    let now = Date(timeIntervalSince1970: 1_000_000)
    let thought = Thought(
        id: .init(rawValue: "thought-1"), title: "自由与责任", statement: "自由必须包含承担选择的责任",
        stage: .stable, provenance: BrainProvenance(originEvidence: nil),
        createdAt: now, updatedAt: now.addingTimeInterval(30)
    )
    let question = Question(
        id: .init(rawValue: "question-1"), question: "如何权衡自由的边界?",
        state: .open, provenance: BrainProvenance(originEvidence: nil), createdAt: now, updatedAt: now
    )
    let activeMemory = BrainMemory(
        id: .init(rawValue: "memory-active"), content: "读者常在深夜阅读",
        origin: .userExplicit, confidence: .high, state: .active,
        provenance: BrainProvenance(originEvidence: nil), createdAt: now, updatedAt: now.addingTimeInterval(20)
    )
    let forgottenMemory = BrainMemory(
        id: .init(rawValue: "memory-forgotten"), content: "已被否定的偏好",
        origin: .agentInferred, confidence: .low, state: .forgotten,
        provenance: BrainProvenance(originEvidence: nil), createdAt: now, updatedAt: now
    )
    try await brain.save(.thought(thought))
    try await brain.save(.question(question))
    try await brain.save(.memory(activeMemory))
    try await brain.save(.memory(forgottenMemory))
    // One item↔item relation (docs/brain.md §5).
    try await brain.relate(source: thought.id, target: activeMemory.id, relation: .derivedMemory, weight: 1)

    let exporter = PersonalDataExporter(
        books: books, reading: reading, sessions: sessions, reflections: reflections,
        journal: journal, brain: brain
    )
    let data = try await exporter.export()

    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let archive = try decoder.decode(PersonalDataArchive.self, from: data)
    #expect(archive.books.count == 1)
    // All three kinds, including the retired/forgotten memory (state preserved so
    // the consumer can reconstruct My Mind's active-vs-retired split).
    #expect(archive.brain.thoughts.map(\.id) == ["thought-1"])
    #expect(archive.brain.thoughts.map(\.title) == ["自由与责任"])
    #expect(archive.brain.questions.map(\.id) == ["question-1"])
    #expect(Set(archive.brain.memories.map(\.id)) == Set(["memory-active", "memory-forgotten"]))
    let active = try #require(archive.brain.memories.first { $0.id == "memory-active" })
    #expect(active.state == "active")
    #expect(active.origin == "userExplicit")
    #expect(active.confidence == "high")
    let forgotten = try #require(archive.brain.memories.first { $0.id == "memory-forgotten" })
    #expect(forgotten.state == "forgotten")
    // Relation appears exactly once.
    let relations = archive.brain.relations
    #expect(relations.count == 1)
    #expect(relations[0].sourceItemID == "thought-1")
    #expect(relations[0].targetItemID == "memory-active")
    #expect(relations[0].relation == "derivedMemory")
    #expect(relations[0].weight == 1)

    // My Mind-visible fields appear in the JSON; secrets never do.
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("userExplicit"))
    #expect(text.contains("derivedMemory"))
    #expect(text.contains("forgotten"))
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
    let brain = GRDBBrainRepository(database: database)

    let book = TestFixtures.book(fingerprint: "wipe-then-export")
    try await books.insert(book)
    try await brain.save(.memory(BrainMemory(
        id: .init(rawValue: "wipe-memory"), content: "擦除前的记忆",
        origin: .agentInferred, confidence: .medium, state: .active,
        provenance: BrainProvenance(originEvidence: nil), createdAt: Date(), updatedAt: Date()
    )))

    try await database.wipeAllUserData()

    let exporter = PersonalDataExporter(
        books: books, reading: reading, sessions: sessions, reflections: reflections,
        journal: journal, brain: brain
    )
    let data = try await exporter.export()

    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let archive = try decoder.decode(PersonalDataArchive.self, from: data)
    #expect(archive.books.isEmpty)
    #expect(archive.brain.thoughts.isEmpty)
    #expect(archive.brain.questions.isEmpty)
    #expect(archive.brain.memories.isEmpty)
    #expect(archive.brain.relations.isEmpty)
    #expect(archive.exportedAt <= Date())
}

@Test func exportEmbedsSavedReflectionAudio() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reading = GRDBReadingRepository(database: database)
    let sessions = GRDBReadingSessionRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let journal = GRDBJournalRepository(database: database)
    let brain = GRDBBrainRepository(database: database)

    let book = TestFixtures.book(fingerprint: "export-audio")
    try await books.insert(book)
    let voice = Reflection(
        bookID: book.id,
        originalText: "带录音的反思",
        inputKind: .voiceTranscript,
        audioFileName: "voice.m4a"
    )
    try await reflections.insert(voice, linkedHighlightIDs: [], evidence: [])

    let audioBytes = Data("test-audio".utf8)
    let exporter = PersonalDataExporter(
        books: books,
        reading: reading,
        sessions: sessions,
        reflections: reflections,
        journal: journal,
        brain: brain,
        audioData: { fileName in fileName == "voice.m4a" ? audioBytes : nil }
    )
    let data = try await exporter.export()
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let archive = try decoder.decode(PersonalDataArchive.self, from: data)
    let exportedVoice = try #require(archive.books.first?.reflections.first)
    #expect(exportedVoice.reflection.id == voice.id)

    #expect(exportedVoice.audioBase64 == audioBytes.base64EncodedString())
}

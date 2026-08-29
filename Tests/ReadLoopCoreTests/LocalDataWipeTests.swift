import AchievementCore
import AppInfrastructure
import ContextRouting
import Foundation
import GRDB
import LibraryCore
import ModelProviders
import Persistence
import ReaderAgent
import ReaderCore
import ReadingSessionCore
import ReflectionCore
import RetrievalCore
import Testing

/// Seeds every user-data table (books, index incl. FTS/embeddings and parent/
/// child chunks, positions, highlights, notes, preferences, sessions,
/// reflections with messages/evidence/connections/citations/journal rows,
/// memories, achievements, provider configuration, routing traces) so the wipe
/// tests can assert nothing survives.
private func seedFullUserData(database: AppDatabase) async throws {
    let books = GRDBBookRepository(database: database)
    let reading = GRDBReadingRepository(database: database)
    let sessions = GRDBReadingSessionRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let journal = GRDBJournalRepository(database: database)
    let memories = GRDBMemoryRepository(database: database)
    let index = GRDBBookIndexRepository(database: database)
    let traces = GRDBRoutingTraceRepository(database: database)
    let achievements = GRDBAchievementRepository(database: database)
    let configurations = GRDBProviderConfigurationRepository(database: database)

    let book = TestFixtures.book(fingerprint: "wipe-book")
    try await books.insert(book)
    let locator = try TestFixtures.realisticLocator()
    try await reading.save(position: .init(bookID: book.id, locator: locator))
    let highlight = Highlight(bookID: book.id, locator: locator)
    try await reading.save(highlight: highlight)
    try await reading.save(note: .init(bookID: book.id, highlightID: highlight.id, locator: locator, body: "擦除前存在的笔记"))
    try await reading.save(preferences: .init(theme: .sepia, fontSize: 1.1, lineHeight: 1.2, pageMargins: 1.0, readingMode: .scroll), for: book.id)

    let session = ReadingSession(bookID: book.id, startLocator: try TestFixtures.realisticLocator(progression: 0.1))
    try await sessions.insert(session)

    let reflection = Reflection(bookID: book.id, sessionID: session.id, originalText: "擦除前的反思", inputKind: .text)
    let evidence = try ReflectionEvidence(reflectionID: reflection.id, sourceType: .bookLocator, locator: locator)
    try await reflections.insert(reflection, linkedHighlightIDs: [highlight.id], evidence: [evidence])
    let second = Reflection(bookID: book.id, originalText: "另一条反思", inputKind: .text)
    try await reflections.insert(second, linkedHighlightIDs: [], evidence: [])
    try await reflections.saveConnection(.init(reflectionID: reflection.id, sourceReflectionID: second.id, relevance: 0.8))
    let agentMessage = try ReflectionMessage(
        reflectionID: reflection.id, author: .agent, source: .agentGenerated,
        content: "回应 [E1]", createdAt: Date(timeIntervalSince1970: 200)
    )
    try await reflections.appendAgentMessage(
        agentMessage,
        evidence: [AgentResponseEvidence(id: "E1", messageID: agentMessage.id, kind: .bookPassage, sourceID: "chunk-1", bookID: book.id, excerpt: "证据")],
        citations: [AgentCitation(messageID: agentMessage.id, evidenceID: "E1", marker: "E1")]
    )
    try await journal.saveThought(.init(reflectionID: reflection.id, messageID: agentMessage.id, thought: "想保留的句子"))
    try await journal.saveQuestion(.init(reflectionID: reflection.id, messageID: agentMessage.id, text: "还想继续吗？"))
    try await journal.saveCitation(.init(reflectionID: reflection.id, messageID: agentMessage.id, sourceType: .bookLocator, bookID: book.id, locator: locator, title: "第一章", excerpt: "引用"))
    try await journal.saveMemoryChange(.init(journalID: reflection.id, changeType: .store, summary: "一次记忆变化"))
    try await memories.save(ReaderMemory(
        sourceReflectionID: reflection.id, kind: .semantic, claim: "长期记忆",
        confidence: 0.6, evidenceIDs: ["refl:\(reflection.id)"]
    ))
    // Also a memory without a source reflection: cascade alone would not remove it.
    try await memories.save(ReaderMemory(kind: .profileTrait, claim: "无来源记忆", confidence: 0.5))

    let version = BookIndexPipeline.currentVersion
    try await index.save(job: BookIndexJob(bookID: book.id, indexVersion: version, state: .ready))
    let parent = try chunk(id: "wipe-parent", book: book, ordinal: 0, progression: 0.2)
    let child = try chunk(
        id: "wipe-child", book: book, ordinal: 1, progression: 0.3,
        role: .child, parentID: parent.id
    )
    try await index.replace(chunks: [parent, child], for: book.id, version: version)
    try await index.saveEmbeddings([parent.id: [0.1, 0.2]], model: "test-embedding", dimensions: 2)

    try await traces.save(makeTrace(reflectionID: reflection.id.description))
    try await achievements.insert(AchievementRecord(id: .firstReflection, unlockedAt: Date(), source: .init(reflectionID: reflection.id, bookID: book.id)))
    try await configurations.save(ProviderConfiguration(
        provider: .openAICompatible,
        baseURL: URL(string: "https://api.example.com/v1")!,
        modelID: "example-chat",
        secretReference: SecretReference(rawValue: "wipe-provider-key"),
    ))
}

private func chunk(
    id: String, book: Book, ordinal: Int, progression: Double,
    role: BookChunkRole = .parent, parentID: BookChunkID? = nil
) throws -> BookChunk {
    let start = try TestFixtures.realisticLocator(progression: progression)
    let end = try TestFixtures.realisticLocator(progression: min(1, progression + 0.02))
    return BookChunk(
        id: .init(rawValue: id), bookID: book.id, resourceHref: start.href,
        resourceOrdinal: 0, ordinal: ordinal, text: "正文内容", normalizedText: "正文内容",
        startLocator: start, endLocator: end, sourceBlockIDs: [],
        role: role, parentID: parentID
    )
}

private func makeTrace(reflectionID: String) -> ContextPlanTrace {
    let semantic = SemanticContextPlan(
        intent: .passageObservation, requests: [],
        response: SemanticResponsePlan(length: .short, posture: .respondOnly)
    )
    let input = ContextRoutingInput(
        interactionMode: .reflection,
        currentReflection: "擦除前的反思",
        recentConversation: [],
        currentReading: .init(bookID: BookID(), chapterTitle: nil, selectedText: nil, nearbyTextPreview: nil, hasCurrentLocator: false),
        availableSources: .init(hasNearbyPassage: false, hasBookIndex: false, hasPastThoughts: false),
        previousAgentAskedQuestion: false
    )
    let (validated, _) = SemanticPlanValidator().validate(semantic, input: input)
    let execution = ContextPolicyCompiler().compile(validated, input: input)
    return ContextPlanTrace(
        reflectionID: reflectionID,
        createdAt: Date(timeIntervalSince1970: 500),
        proposedPlan: execution.legacyProposal,
        validatedPlan: execution.legacyValidatedPlan,
        usedFallback: false,
        fallbackReason: nil,
        fallbackDetail: nil,
        routingDuration: .seconds(0.2),
        retrievalDuration: .seconds(0.3),
        replyDuration: .seconds(0.4),
        selectedBookEvidenceIDs: [],
        connectedReflectionID: nil,
        routingTokenUsage: nil,
        replyTokenUsage: nil
    )
}

@Test func wipeAllUserDataRemovesEveryRowAndKeepsSchemaUsable() async throws {
    let database = try AppDatabase.inMemory()
    try await seedFullUserData(database: database)

    try await database.wipeAllUserData()

    let counts = try await database.writer.read { db in
        var counts: [String: Int] = [:]
        for table in AppDatabase.userDataTableOrder {
            counts[table] = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)")
        }
        return counts
    }
    for (table, count) in counts {
        #expect(count == 0, "\(table) still holds \(count) row(s) after the wipe")
    }

    // Schema intact: every user table still exists and new data can be written.
    let tables = try await database.writer.read { db in
        try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
    }
    for table in AppDatabase.userDataTableOrder {
        #expect(tables.contains(table), "\(table) missing after the wipe")
    }
    let books = GRDBBookRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let freshBook = TestFixtures.book(fingerprint: "post-wipe-book")
    try await books.insert(freshBook)
    try await reflections.insert(
        Reflection(bookID: freshBook.id, originalText: "擦除后写下的反思", inputKind: .text),
        linkedHighlightIDs: [], evidence: []
    )
    let stored = try await reflections.reflections(for: freshBook.id)
    #expect(stored.map(\.originalText) == ["擦除后写下的反思"])
}

@Test func wipeAllUserDataIsIdempotent() async throws {
    let database = try AppDatabase.inMemory()
    try await seedFullUserData(database: database)

    try await database.wipeAllUserData()
    try await database.wipeAllUserData()

    let count = try await database.writer.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM books")
    }
    #expect(count == 0)
}

@Test func wipeServiceAlsoClearsKeychainCredentials() async throws {
    let database = try AppDatabase.inMemory()
    let secrets: any SecretStore = InMemorySecretStore()
    let chat = SecretReference(rawValue: "primary-model-provider")
    let embedding = SecretReference(rawValue: "embedding-model-provider")
    try await secrets.save("sk-chat", for: chat)
    try await secrets.save("sk-embedding", for: embedding)
    let service = LocalDataWipeService(database: database, secrets: secrets)

    try await service.wipeAllUserData()
    try await service.wipeAllUserData() // idempotent credential reset too

    #expect(try await secrets.secret(for: chat) == nil)
    #expect(try await secrets.secret(for: embedding) == nil)
}

@Test func removeAllBookFilesClearsArtifactsButKeepsStoreStructure() throws {
    let tempDir = try TestFixtures.temporaryDirectory()
    let store = try BookFileStore(directory: tempDir.appendingPathComponent("Books"))
    let bookID = BookID(rawValue: UUID())
    try Data("epub".utf8).write(to: store.url(for: bookID))
    try Data("partial".utf8).write(to: store.directory.appendingPathComponent(".staging").appendingPathComponent("\(bookID.description).epub.partial"))
    try Data("trashed".utf8).write(to: store.directory.appendingPathComponent(".trash").appendingPathComponent("\(bookID.description).epub"))

    store.removeAllBookFiles()

    #expect(!FileManager.default.fileExists(atPath: store.url(for: bookID).path))
    #expect(FileManager.default.fileExists(atPath: store.directory.path))
    #expect(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent(".staging").path))
    #expect(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent(".trash").path))
    let leftovers = try FileManager.default.contentsOfDirectory(at: store.directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "epub" || $0.pathExtension == "partial" }
    #expect(leftovers.isEmpty)
}

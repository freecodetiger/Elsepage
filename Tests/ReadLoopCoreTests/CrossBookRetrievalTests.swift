import AgentRuntime
import Foundation
import LibraryCore
import Persistence
import ReaderAgent
import ReadingSessionCore
import ReflectionCore
import Testing

// WS3 cross-book Personal Retrieval + long-term memory retrieval.
// Same-book connections stay preferred (同书 > 跨书 > 记忆); memories surface as
// evidence only and never create a ReflectionConnection.

@Test func agentConnectsToCrossBookReflectionWhenSameBookHasNone() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let bookA = TestFixtures.book(fingerprint: "cross-a")
    let bookB = TestFixtures.book(fingerprint: "cross-b")
    try await books.insert(bookA)
    try await books.insert(bookB)

    let crossBookThought = Reflection(bookID: bookB.id, originalText: "自由也意味着承担选择带来的责任", inputKind: .text)
    try await reflections.insert(crossBookThought, linkedHighlightIDs: [], evidence: [])
    let current = Reflection(bookID: bookA.id, originalText: "我现在觉得自由必须包含承担选择的责任", inputKind: .text)
    try await reflections.insert(current, linkedHighlightIDs: [], evidence: [])

    let response = ModelResponse(content: "你从另一本书里也留下过类似的想法。")
    let agent = ReaderAgent(
        reflections: reflections,
        models: CrossBookModelFactory(client: FakeModelClient(events: [.started, .completed(response)]))
    )
    let events = await collectCrossBook(agent.respond(to: current.id))
    guard case .completed? = events.last(where: { if case .completed = $0 { return true }; return false }) else {
        Issue.record("Expected a completed agent reply")
        return
    }
    let connection = try #require(try await reflections.connections(for: current.id).first)
    #expect(connection.sourceReflectionID == crossBookThought.id)
}

@Test func agentDoesNotConnectUnrelatedBooks() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let bookA = TestFixtures.book(fingerprint: "unrelated-a")
    let bookB = TestFixtures.book(fingerprint: "unrelated-b")
    try await books.insert(bookA)
    try await books.insert(bookB)

    let unrelated = Reflection(bookID: bookB.id, originalText: "今天我读的这部分讲的是厨房里的盐与火候", inputKind: .text)
    try await reflections.insert(unrelated, linkedHighlightIDs: [], evidence: [])
    let current = Reflection(bookID: bookA.id, originalText: "我现在觉得自由必须包含承担选择的责任", inputKind: .text)
    try await reflections.insert(current, linkedHighlightIDs: [], evidence: [])

    let response = ModelResponse(content: "这一轮没有需要连接的其他想法。")
    let agent = ReaderAgent(
        reflections: reflections,
        models: CrossBookModelFactory(client: FakeModelClient(events: [.started, .completed(response)]))
    )
    let events = await collectCrossBook(agent.respond(to: current.id))
    guard case .completed? = events.last(where: { if case .completed = $0 { return true }; return false }) else {
        Issue.record("Expected a completed agent reply")
        return
    }
    #expect(try await reflections.connections(for: current.id).isEmpty)
}

@Test func matchingActiveMemorySurfacesLongTermMemoryEvidenceWithoutConnection() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let memories = GRDBMemoryRepository(database: database)
    let book = TestFixtures.book(fingerprint: "memory-book")
    try await books.insert(book)

    let current = Reflection(bookID: book.id, originalText: "我在想，自由与责任或许是一体两面的关系。", inputKind: .text)
    try await reflections.insert(current, linkedHighlightIDs: [], evidence: [])
    let memory = ReaderMemory(
        kind: .semantic, claim: "读者反复思考自由与责任的关系。",
        confidence: 0.7, status: .active, evidenceIDs: []
    )
    try await memories.save(memory)

    let response = ModelResponse(content: "这呼应了你长期反复思考的自由与责任。")
    let agent = ReaderAgent(
        reflections: reflections,
        models: CrossBookModelFactory(client: FakeModelClient(events: [.started, .completed(response)])),
        memories: memories
    )
    let events = await collectCrossBook(agent.respond(to: current.id))
    guard case .completed? = events.last(where: { if case .completed = $0 { return true }; return false }) else {
        Issue.record("Expected a completed agent reply")
        return
    }
    let provenance = events.compactMap { if case .citationsValidated(let p) = $0 { return p }; return nil }.first
    let memoryEvidence = try #require(provenance?.evidence.first { $0.title == "长期记忆" })
    #expect(memoryEvidence.kind == .pastReflection)
    #expect(memoryEvidence.excerpt == memory.claim)
    #expect(try await reflections.connections(for: current.id).isEmpty)
}

@Test func supersededMemoryIsIgnored() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let memories = GRDBMemoryRepository(database: database)
    let book = TestFixtures.book(fingerprint: "memory-book-superseded")
    try await books.insert(book)

    let current = Reflection(bookID: book.id, originalText: "我在想，自由与责任或许是一体两面的关系。", inputKind: .text)
    try await reflections.insert(current, linkedHighlightIDs: [], evidence: [])
    let memory = ReaderMemory(
        kind: .semantic, claim: "读者反复思考自由与责任的关系。",
        confidence: 0.7, status: .superseded, evidenceIDs: []
    )
    try await memories.save(memory)

    let response = ModelResponse(content: "明白了。")
    let agent = ReaderAgent(
        reflections: reflections,
        models: CrossBookModelFactory(client: FakeModelClient(events: [.started, .completed(response)])),
        memories: memories
    )
    let events = await collectCrossBook(agent.respond(to: current.id))
    guard case .completed? = events.last(where: { if case .completed = $0 { return true }; return false }) else {
        Issue.record("Expected a completed agent reply")
        return
    }
    let provenance = events.compactMap { if case .citationsValidated(let p) = $0 { return p }; return nil }.first
    #expect(provenance?.evidence.contains { $0.title == "长期记忆" } != true)
    #expect(try await reflections.connections(for: current.id).isEmpty)
}

private struct CrossBookModelFactory: ModelClientFactory {
    let client: any ModelClient
    func makeClient() -> any ModelClient { client }
}

private func collectCrossBook(_ stream: AsyncStream<ReaderAgentEvent>) async -> [ReaderAgentEvent] {
    var events: [ReaderAgentEvent] = []
    for await event in stream { events.append(event) }
    return events
}

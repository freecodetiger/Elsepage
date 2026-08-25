import AgentRuntime
import Foundation
import LibraryCore
import Persistence
import ReaderAgent
import ReaderCore
import ReadingSessionCore
import ReflectionCore
import Testing

@Test func sessionContextBuilderScopesHighlightsAndNotesToSessionWindow() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let sessions = GRDBReadingSessionRepository(database: database)
    let reading = GRDBReadingRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let book = TestFixtures.book(fingerprint: "session-context-window")
    try await books.insert(book)

    let session = ReadingSession(
        bookID: book.id,
        startedAt: .init(timeIntervalSince1970: 100),
        startLocator: try TestFixtures.realisticLocator(progression: 0.2)
    )
    try await sessions.insert(session)

    let beforeHighlight = Highlight(
        bookID: book.id,
        locator: try TestFixtures.realisticLocator(progression: 0.1),
        createdAt: .init(timeIntervalSince1970: 50)
    )
    let inWindowHighlight = Highlight(
        bookID: book.id,
        locator: try TestFixtures.realisticLocator(progression: 0.3),
        createdAt: .init(timeIntervalSince1970: 150)
    )
    try await reading.save(highlight: beforeHighlight)
    try await reading.save(highlight: inWindowHighlight)

    let beforeNote = Note(
        bookID: book.id, locator: try TestFixtures.realisticLocator(progression: 0.05),
        body: "窗口之前的批注", createdAt: .init(timeIntervalSince1970: 60)
    )
    let inWindowNote = Note(
        bookID: book.id, locator: try TestFixtures.realisticLocator(progression: 0.35),
        body: "窗口内的批注", createdAt: .init(timeIntervalSince1970: 160)
    )
    try await reading.save(note: beforeNote)
    try await reading.save(note: inWindowNote)

    let prior = Reflection(
        bookID: book.id, originalText: "自由与责任是一体的", inputKind: .text,
        createdAt: .init(timeIntervalSince1970: 60)
    )
    let current = Reflection(
        bookID: book.id, originalText: "我现在开始思考责任", inputKind: .text,
        createdAt: .init(timeIntervalSince1970: 200)
    )
    try await reflections.insert(prior, linkedHighlightIDs: [], evidence: [])
    try await reflections.insert(current, linkedHighlightIDs: [], evidence: [])

    let builder = SessionContextBuilder(sessions: sessions, reading: reading, reflections: reflections)
    let context = await builder.build(bookID: book.id, sessionID: session.id, excluding: current.id)

    #expect(context.session?.id == session.id)
    #expect(!context.sessionHighlights.contains { $0.id == beforeHighlight.id })
    #expect(context.sessionHighlights.contains { $0.id == inWindowHighlight.id })
    #expect(!context.sessionNotes.contains { $0.id == beforeNote.id })
    #expect(context.sessionNotes.contains { $0.id == inWindowNote.id })
    #expect(context.bookReflections.map(\.id) == [prior.id])
}

@Test func sessionContextBuilderWithoutSessionKeepsOnlyBookReflections() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reading = GRDBReadingRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let book = TestFixtures.book(fingerprint: "session-context-no-session")
    try await books.insert(book)

    let orphanHighlight = Highlight(
        bookID: book.id,
        locator: try TestFixtures.realisticLocator(),
        createdAt: .init(timeIntervalSince1970: 300)
    )
    try await reading.save(highlight: orphanHighlight)
    let prior = Reflection(bookID: book.id, originalText: "没有会话也有思考", inputKind: .text)
    let current = Reflection(bookID: book.id, originalText: "当前的想法", inputKind: .text)
    try await reflections.insert(prior, linkedHighlightIDs: [], evidence: [])
    try await reflections.insert(current, linkedHighlightIDs: [], evidence: [])

    let builder = SessionContextBuilder(
        sessions: GRDBReadingSessionRepository(database: database),
        reading: reading,
        reflections: reflections
    )
    let context = await builder.build(bookID: book.id, sessionID: nil, excluding: current.id)

    #expect(context.session == nil)
    #expect(context.sessionHighlights.isEmpty)
    #expect(context.sessionNotes.isEmpty)
    #expect(context.bookReflections.map(\.id) == [prior.id])
}

@Test func readerAgentPolicyFormatsSessionContextSlots() throws {
    let reflection = Reflection(bookID: BookID(), originalText: "自由必须包含责任", inputKind: .text)
    let start = try TestFixtures.realisticLocator(progression: 0.2)
    let end = try TestFixtures.realisticLocator(progression: 0.4)
    let session = ReadingSession(
        bookID: reflection.bookID,
        startedAt: .init(timeIntervalSince1970: 100),
        startLocator: start,
        endLocator: end
    )
    let highlight = Highlight(bookID: reflection.bookID, locator: start, createdAt: .init(timeIntervalSince1970: 150))
    let note = Note(bookID: reflection.bookID, locator: end, body: "这个转折值得记住", createdAt: .init(timeIntervalSince1970: 160))
    let prior = Reflection(bookID: reflection.bookID, originalText: "责任是自由的代价", inputKind: .text)
    let context = SessionContext(
        session: session,
        sessionHighlights: [highlight],
        sessionNotes: [note],
        bookReflections: [prior]
    )

    let input = ReaderAgentPolicy().input(for: reflection, sessionContext: context)
    let contents = input.messages.map(\.content)
    #expect(contents.contains { $0.contains("本次阅读区间") })
    #expect(contents.contains { $0.contains("划线的部分") })
    #expect(contents.contains { $0.contains("写的批注") })
    #expect(contents.contains { $0.contains("这本书你之前留下的思考") })
    #expect(contents.contains { $0.contains("这个转折值得记住") })
    #expect(contents.contains { $0.contains("责任是自由的代价") })
}

@Test func readerAgentPrefersSameBookOverCrossBookPastReflections() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let bookA = TestFixtures.book(fingerprint: "agent-book-a")
    let bookB = TestFixtures.book(fingerprint: "agent-book-b")
    try await books.insert(bookA)
    try await books.insert(bookB)

    // Both a same-book and a lexically *stronger* cross-book reflection match;
    // same-book must win (WS3 ordering: 同书 > 跨书 > 记忆).
    let sameBookThought = Reflection(bookID: bookA.id, originalText: "自由也意味着承担选择带来的责任", inputKind: .text)
    try await reflections.insert(sameBookThought, linkedHighlightIDs: [], evidence: [])
    let otherBookThought = Reflection(bookID: bookB.id, originalText: "承担选择的责任也通向自由", inputKind: .text)
    try await reflections.insert(otherBookThought, linkedHighlightIDs: [], evidence: [])
    let current = Reflection(bookID: bookA.id, originalText: "我现在觉得自由必须包含承担选择的责任", inputKind: .text)
    try await reflections.insert(current, linkedHighlightIDs: [], evidence: [])

    let response = ModelResponse(content: "你再次把自由和责任放在一起思考。")
    let agent = ReaderAgent(
        reflections: reflections,
        models: SessionContextModelFactory(client: FakeModelClient(events: [.started, .completed(response)]))
    )
    let events = await collectSessionContext(agent.respond(to: current.id))
    guard case .completed? = events.last(where: { if case .completed = $0 { return true }; return false }) else {
        Issue.record("Expected a completed agent reply")
        return
    }
    let connection = try #require(try await reflections.connections(for: current.id).first)
    #expect(connection.sourceReflectionID == sameBookThought.id)
    #expect(connection.sourceReflectionID != otherBookThought.id)
}

private struct SessionContextModelFactory: ModelClientFactory {
    let client: any ModelClient
    func makeClient() -> any ModelClient { client }
}

private func collectSessionContext(_ stream: AsyncStream<ReaderAgentEvent>) async -> [ReaderAgentEvent] {
    var events: [ReaderAgentEvent] = []
    for await event in stream { events.append(event) }
    return events
}

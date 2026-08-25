import AgentRuntime
import Foundation
import LibraryCore
import Persistence
import ReaderAgent
import ReflectionCore
import ReadingSessionCore
import Testing

@Test func meaningfulSessionPolicyRejectsAccidentalOpenAndAcceptsRealSignals() throws {
    let locator = try TestFixtures.realisticLocator()
    let short = SessionEndingSummary(session: ReadingSession(
        bookID: BookID(),
        startedAt: .init(timeIntervalSince1970: 100),
        endedAt: .init(timeIntervalSince1970: 110),
        startLocator: locator,
        endLocator: locator
    ))
    #expect(!short.shouldOfferReflection)

    var annotated = short.session
    annotated.highlightCount = 1
    #expect(SessionEndingSummary(session: annotated).shouldOfferReflection)

    var long = short.session
    long.endedAt = .init(timeIntervalSince1970: 281)
    #expect(SessionEndingSummary(session: long).shouldOfferReflection)
}

@Test func readReflectAgentThoughtsAndSourceNavigationRemainOnePersistedFlow() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let sessions = GRDBReadingSessionRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let book = TestFixtures.book(fingerprint: "product-loop")
    try await books.insert(book)
    let locator = try TestFixtures.realisticLocator()

    let previous = Reflection(
        bookID: book.id,
        originalText: "自由也意味着承担选择带来的责任",
        inputKind: .text,
        createdAt: .init(timeIntervalSince1970: 50)
    )
    let previousEvidence = try ReflectionEvidence(
        reflectionID: previous.id,
        sourceType: .bookLocator,
        locator: locator
    )
    try await reflections.insert(previous, linkedHighlightIDs: [], evidence: [previousEvidence])

    let sessionService = ReadingSessionService(repository: sessions)
    let session = try await sessionService.start(
        bookID: book.id,
        at: locator,
        startedAt: .init(timeIntervalSince1970: 100)
    )
    let completed = try await sessionService.end(
        id: session.id,
        at: locator,
        endedAt: .init(timeIntervalSince1970: 400),
        highlightCount: 0,
        noteCount: 0
    )
    #expect(SessionEndingSummary(session: completed).shouldOfferReflection)
    #expect(TodayProductStateResolver.resolve(
        currentBook: book,
        sessions: [completed],
        reflections: [],
        now: .init(timeIntervalSince1970: 400),
        calendar: Calendar(identifier: .gregorian)
    ) == .offerReflection(book, completed))

    let current = try await TextReflectionSubmissionService(repository: reflections).submit(.init(
        bookID: book.id,
        sessionID: completed.id,
        locator: locator,
        originalText: "我现在觉得自由必须包含承担选择的责任"
    ))
    #expect(try await reflections.messages(for: current.id).isEmpty)

    let response = ModelResponse(content: "你把自由和责任放在了一起，这也回应了你过去留下的同一个问题。")
    let agent = ReaderAgent(
        reflections: reflections,
        models: ProductLoopModelFactory(client: FakeModelClient(events: [.started, .completed(response)]))
    )
    let events = await collectProductLoop(agent.respond(to: current.id))
    guard case .completed(let agentMessage) = events.last else {
        Issue.record("Expected a persisted Agent response")
        return
    }
    #expect(agentMessage.reflectionID == current.id)
    #expect(try await reflections.connections(for: current.id).first?.sourceReflectionID == previous.id)

    let archive = try await ReflectionArchiveService(books: books, reflections: reflections).recentEntries()
    let entry = try #require(archive.first(where: { $0.reflection.id == current.id }))
    #expect(entry.reflection.originalText == current.originalText)
    #expect(entry.derivedAgentResponse?.id == agentMessage.id)
    #expect(entry.connections.first?.sourceReflection.id == previous.id)
    #expect(entry.connections.first?.sourceLocator?.json == locator.json)
    #expect(entry.sourceLocator?.json == locator.json)

    let completedToday = TodayProductStateResolver.resolve(
        currentBook: book,
        sessions: [completed],
        reflections: [current],
        now: current.createdAt,
        calendar: Calendar(identifier: .gregorian)
    )
    #expect(completedToday == .reflectionComplete(book))

    try await reflections.delete(id: previous.id)
    #expect(try await reflections.connections(for: current.id).isEmpty)
    #expect(try await reflections.reflection(id: current.id) != nil)
}

@Test func providerAbsenceAndDiscussionRetryNeverLoseOrDuplicateUserThought() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let book = TestFixtures.book(fingerprint: "offline-loop")
    try await books.insert(book)
    let locator = try TestFixtures.realisticLocator()
    let reflection = try await TextReflectionSubmissionService(repository: reflections).submit(.init(
        bookID: book.id,
        sessionID: nil,
        locator: locator,
        originalText: "网络不应该决定这句话是否属于我"
    ))

    let offlineAgent = ReaderAgent(reflections: reflections, models: MissingProductLoopModelFactory())
    let offlineEvents = await collectProductLoop(offlineAgent.respond(to: reflection.id))
    #expect(offlineEvents.last == .failed(.providerNotConfigured))
    #expect(try await reflections.reflection(id: reflection.id)?.originalText == reflection.originalText)

    let reply = ModelResponse(content: "本地保存是这段思考的前提。")
    let onlineAgent = ReaderAgent(
        reflections: reflections,
        models: ProductLoopModelFactory(client: FakeModelClient(events: [.completed(reply)]))
    )
    let messageID = UUID()
    _ = await collectProductLoop(onlineAgent.continueDiscussion(
        on: reflection.id,
        messageID: messageID,
        text: "即使请求失败，我也想保留这一点。"
    ))
    _ = await collectProductLoop(onlineAgent.continueDiscussion(
        on: reflection.id,
        messageID: messageID,
        text: "即使请求失败，我也想保留这一点。"
    ))
    let messages = try await reflections.messages(for: reflection.id)
    #expect(messages.filter { $0.id == messageID }.count == 1)
    #expect(messages.filter { $0.author == .agent }.count == 1)
}

private struct ProductLoopModelFactory: ModelClientFactory {
    let client: any ModelClient
    func makeClient() -> any ModelClient { client }
}

private struct MissingProductLoopModelFactory: ModelClientFactory {
    func makeClient() throws -> any ModelClient { throw ModelFailure.invalidConfiguration }
}

private func collectProductLoop(_ stream: AsyncStream<ReaderAgentEvent>) async -> [ReaderAgentEvent] {
    var events: [ReaderAgentEvent] = []
    for await event in stream { events.append(event) }
    return events
}

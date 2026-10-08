import AgentRuntime
import Foundation
import LibraryCore
import Persistence
import ReaderAgent
import ReflectionCore
import Testing

/// `ReaderAgent` is one shared instance behind several independent surfaces (the
/// reading-end conversation and the Thoughts backfill both call
/// `respond(to:)`). These tests pin the slot that keeps them from each starting
/// their own model call for the same record.
@Test func concurrentFirstReplyRequestsShareOneModelCall() async throws {
    let (reflections, reflection) = try await makeStoredReflection(fingerprint: "inflight-shared")
    let response = ModelResponse(content: "你把它放在责任的角度来理解，这和上次是同一条线。")
    // The delay keeps the owning request in flight while the second arrives, so
    // the second is a genuine waiter rather than a later owner.
    let factory = CountingModelFactory { _ in
        FakeModelClient(events: [.started, .completed(response)], eventDelay: .milliseconds(40))
    }
    let agent = ReaderAgent(reflections: reflections, models: factory)

    let first = agent.respond(to: reflection.id)
    let waitingEvents = await collectInFlight(agent.respond(to: reflection.id))
    let owningEvents = await collectInFlight(first)

    #expect(factory.makeClientCount == 1)

    let messages = try await reflections.messages(for: reflection.id)
    let agentMessages = messages.filter { $0.author == .agent }
    #expect(agentMessages.count == 1)

    // The waiting caller still surfaces the reply the owner persisted — it must
    // not come back empty-handed, and must not persist a second reply.
    let surfaced = try #require(completedMessage(in: waitingEvents))
    #expect(surfaced.id == agentMessages.first?.id)
    #expect(completedMessage(in: owningEvents)?.id == surfaced.id)
}

@Test func waitingRequestTakesOverWhenTheFirstAttemptPersistsNothing() async throws {
    let (reflections, reflection) = try await makeStoredReflection(fingerprint: "inflight-takeover")
    let response = ModelResponse(content: "网络回来之后，这句话仍然值得被回应。")
    // Attempt 1 fails slowly (one event, so the delay is really awaited), which
    // keeps it in flight while the second request arrives. Attempt 2 succeeds —
    // a tapped retry must never be a silent no-op.
    let factory = CountingModelFactory { attempt in
        attempt == 1
            ? FakeModelClient(events: [.started], terminalFailure: .network, eventDelay: .milliseconds(40))
            : FakeModelClient(events: [.completed(response)])
    }
    let agent = ReaderAgent(reflections: reflections, models: factory)

    let first = agent.respond(to: reflection.id)
    let retryEvents = await collectInFlight(agent.respond(to: reflection.id))
    let failedEvents = await collectInFlight(first)

    // Two attempts were made: the original that failed, and the takeover.
    #expect(factory.makeClientCount == 2)
    #expect(failedEvents.last == .failed(.runtime(.network)))

    let agentMessages = try await reflections.messages(for: reflection.id)
        .filter { $0.author == .agent }
    #expect(agentMessages.count == 1)
    #expect(completedMessage(in: retryEvents)?.id == agentMessages.first?.id)
}

@Test func aLaterRequestAfterTheReplyLandedReusesItWithoutCallingTheModel() async throws {
    let (reflections, reflection) = try await makeStoredReflection(fingerprint: "inflight-reuse")
    let response = ModelResponse(content: "这一段已经回应过了。")
    let factory = CountingModelFactory { _ in FakeModelClient(events: [.completed(response)]) }
    let agent = ReaderAgent(reflections: reflections, models: factory)

    _ = await collectInFlight(agent.respond(to: reflection.id))
    let laterEvents = await collectInFlight(agent.respond(to: reflection.id))

    #expect(factory.makeClientCount == 1)
    #expect(try await reflections.messages(for: reflection.id).filter { $0.author == .agent }.count == 1)
    #expect(completedMessage(in: laterEvents) != nil)
}

// MARK: - Fixtures

private func makeStoredReflection(fingerprint: String) async throws -> (GRDBReflectionRepository, Reflection) {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let book = TestFixtures.book(fingerprint: fingerprint)
    try await books.insert(book)
    let reflection = try await TextReflectionSubmissionService(repository: reflections).submit(.init(
        bookID: book.id,
        sessionID: nil,
        locator: try TestFixtures.realisticLocator(),
        originalText: "自由必须包含承担选择的责任。"
    ))
    return (reflections, reflection)
}

/// Counts client constructions so a test can assert how many model calls were
/// actually attempted — the duplicate this guards against shows up here first,
/// before it reaches the database.
private final class CountingModelFactory: ModelClientFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let make: @Sendable (Int) -> any ModelClient

    init(make: @escaping @Sendable (Int) -> any ModelClient) {
        self.make = make
    }

    func makeClient() -> any ModelClient {
        lock.lock()
        count += 1
        let attempt = count
        lock.unlock()
        return make(attempt)
    }

    var makeClientCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private func collectInFlight(_ stream: AsyncStream<ReaderAgentEvent>) async -> [ReaderAgentEvent] {
    var events: [ReaderAgentEvent] = []
    for await event in stream { events.append(event) }
    return events
}

private func completedMessage(in events: [ReaderAgentEvent]) -> ReflectionMessage? {
    events.compactMap { if case .completed(let message) = $0 { return message } else { return nil } }.last
}

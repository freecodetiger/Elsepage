import Foundation
import LibraryCore
import Persistence
import ReaderCore
import ReadingSessionCore
import Testing

/// FIX-01 (PRD §21.5): agentDiscussionCount is really accumulated — one count per
/// user-initiated agent discussion (a Reflection submission opening the Agent
/// conversation, and each follow-up the user sends in it). The App layer calls
/// `recordAgentDiscussion` at exactly those moments; these tests pin the
/// service/persistence semantics the call sites rely on.
@Test func recordAgentDiscussionIncrementsAndPersistsImmediately() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book()
    try await GRDBBookRepository(database: database).insert(book)
    let repository = GRDBReadingSessionRepository(database: database)
    let service = ReadingSessionService(repository: repository)

    let session = try await service.start(bookID: book.id, at: TestFixtures.realisticLocator(progression: 0.1))
    #expect(try await repository.session(id: session.id)?.agentDiscussionCount == 0)

    // Two user-initiated discussions (e.g. the reflection submission plus one follow-up).
    try await service.recordAgentDiscussion(id: session.id)
    let afterFirst = try #require(try await repository.session(id: session.id))
    #expect(afterFirst.agentDiscussionCount == 1)

    try await service.recordAgentDiscussion(id: session.id)
    let afterSecond = try #require(try await repository.session(id: session.id))
    #expect(afterSecond.agentDiscussionCount == 2)
}

@Test func sessionEndPreservesThePersistedDiscussionCount() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book()
    try await GRDBBookRepository(database: database).insert(book)
    let service = ReadingSessionService(repository: GRDBReadingSessionRepository(database: database))
    let session = try await service.start(bookID: book.id, at: TestFixtures.realisticLocator(progression: 0.2))

    try await service.recordAgentDiscussion(id: session.id)
    try await service.recordAgentDiscussion(id: session.id)

    // Ending without an explicit count (the app's only production path) must keep
    // the discussions already recorded — never reset them to zero.
    let completed = try await service.end(
        id: session.id, at: TestFixtures.realisticLocator(progression: 0.4),
        highlightCount: 1, noteCount: 0
    )
    #expect(completed.agentDiscussionCount == 2)

    // A repeated end request stays idempotent and keeps the counter.
    let retried = try await service.end(
        id: session.id, at: TestFixtures.realisticLocator(progression: 0.9),
        highlightCount: 9, noteCount: 9
    )
    #expect(retried.agentDiscussionCount == 2)
}

@Test func explicitEndCountNeverLowersPersistedDiscussionCount() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book()
    try await GRDBBookRepository(database: database).insert(book)
    let service = ReadingSessionService(repository: GRDBReadingSessionRepository(database: database))
    let session = try await service.start(bookID: book.id, at: TestFixtures.realisticLocator(progression: 0.2))

    try await service.recordAgentDiscussion(id: session.id)
    // Legacy caller passing an explicit (smaller) value must not erase the record.
    let completed = try await service.end(
        id: session.id, at: TestFixtures.realisticLocator(progression: 0.4),
        highlightCount: 0, noteCount: 0, agentDiscussionCount: 0
    )
    #expect(completed.agentDiscussionCount == 1)

    let second = try await service.start(bookID: book.id, at: TestFixtures.realisticLocator(progression: 0.5))
    let bigger = try await service.end(
        id: second.id, at: TestFixtures.realisticLocator(progression: 0.6),
        highlightCount: 0, noteCount: 0, agentDiscussionCount: 5
    )
    #expect(bigger.agentDiscussionCount == 5)
}

@Test func endedSessionStillAcceptsFollowUpDiscussionCounts() async throws {
    // 补写 Reflection: the user writes after the session ended. The discussion is
    // still anchored to that session, so the counter keeps accumulating.
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book()
    try await GRDBBookRepository(database: database).insert(book)
    let repository = GRDBReadingSessionRepository(database: database)
    let service = ReadingSessionService(repository: repository)
    let session = try await service.start(bookID: book.id, at: TestFixtures.realisticLocator(progression: 0.2))
    _ = try await service.end(
        id: session.id, at: TestFixtures.realisticLocator(progression: 0.4),
        highlightCount: 0, noteCount: 0
    )

    try await service.recordAgentDiscussion(id: session.id)
    let updated = try #require(try await repository.session(id: session.id))
    #expect(updated.agentDiscussionCount == 1)
}

@Test func recordAgentDiscussionOnUnknownSessionReturnsNil() async throws {
    let database = try AppDatabase.inMemory()
    let service = ReadingSessionService(repository: GRDBReadingSessionRepository(database: database))
    let missing = ReadingSessionID()
    let result = try await service.recordAgentDiscussion(id: missing)
    #expect(result == nil)
}

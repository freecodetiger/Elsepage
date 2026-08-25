import Foundation
import LibraryCore
import Persistence
import ReaderCore
import ReadingSessionCore
import ReflectionCore
import Testing

@Test func sessionServiceStartsOnlyOneActiveSessionAndEndsIdempotently() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book()
    try await GRDBBookRepository(database: database).insert(book)
    let locator = try TestFixtures.realisticLocator(progression: 0.2)
    let service = ReadingSessionService(repository: GRDBReadingSessionRepository(database: database))

    let first = try await service.start(bookID: book.id, at: locator, startedAt: .init(timeIntervalSince1970: 100))
    let retriedStart = try await service.start(bookID: book.id, at: try TestFixtures.realisticLocator(progression: 0.3), startedAt: .init(timeIntervalSince1970: 200))
    #expect(retriedStart.id == first.id)

    let end = try TestFixtures.realisticLocator(progression: 0.45)
    let completed = try await service.end(id: first.id, at: end, endedAt: .init(timeIntervalSince1970: 400), highlightCount: 2, noteCount: 1)
    let retriedEnd = try await service.end(id: first.id, at: try TestFixtures.realisticLocator(progression: 0.8), endedAt: .init(timeIntervalSince1970: 500), highlightCount: 9, noteCount: 9)

    #expect(completed == retriedEnd)
    #expect(retriedEnd.endLocator == end)
    #expect(retriedEnd.highlightCount == 2)
    #expect(retriedEnd.noteCount == 1)
}

@Test func sessionEndingSummaryUsesHonestWallClockDurationAndProgress() throws {
    let start = try TestFixtures.realisticLocator(progression: 0.5)
    let end = try TestFixtures.realisticLocator(progression: 0.25)
    let session = ReadingSession(
        bookID: BookID(),
        startedAt: .init(timeIntervalSince1970: 100),
        endedAt: .init(timeIntervalSince1970: 50),
        startLocator: start,
        endLocator: end
    )
    let summary = SessionEndingSummary(session: session)

    #expect(summary.wallClockDuration == 0)
    #expect(summary.progressDelta == 0)
    #expect(!summary.shouldOfferReflection)
}

@Test func textReflectionSavesRawTextBeforeAnyDerivedContentAndRetriesIdempotently() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book()
    try await GRDBBookRepository(database: database).insert(book)
    let locator = try TestFixtures.realisticLocator(progression: 0.4)
    let sessionService = ReadingSessionService(repository: GRDBReadingSessionRepository(database: database))
    let session = try await sessionService.start(bookID: book.id, at: locator)
    _ = try await sessionService.end(id: session.id, at: locator, highlightCount: 0, noteCount: 0)

    let draft = TextReflectionDraft(
        bookID: book.id,
        sessionID: session.id,
        locator: locator,
        originalText: "  我不同意作者把选择说得太轻松。  "
    )
    let service = TextReflectionSubmissionService(repository: GRDBReflectionRepository(database: database))
    let first = try await service.submit(draft)
    let retried = try await service.submit(draft)

    #expect(first.id == retried.id)
    #expect(first.bookID == retried.bookID)
    #expect(first.sessionID == retried.sessionID)
    #expect(first.originalText == retried.originalText)
    #expect(first.originalText == draft.originalText)
    let repository = GRDBReflectionRepository(database: database)
    #expect(try await repository.messages(for: first.id).isEmpty)
    let evidence = try await repository.evidence(for: first.id)
    #expect(evidence.map(\.sourceType).sorted { $0.rawValue < $1.rawValue } == [.bookLocator, .readingSession])
}

@Test func textReflectionRejectsBlankTextAndConflictingDraftRetry() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book()
    try await GRDBBookRepository(database: database).insert(book)
    let locator = try TestFixtures.realisticLocator()
    let service = TextReflectionSubmissionService(repository: GRDBReflectionRepository(database: database))
    let id = ReflectionID()

    await #expect(throws: TextReflectionSubmissionError.emptyText) {
        try await service.submit(.init(id: id, bookID: book.id, sessionID: nil, locator: locator, originalText: " \n "))
    }
    _ = try await service.submit(.init(id: id, bookID: book.id, sessionID: nil, locator: locator, originalText: "原始想法"))
    await #expect(throws: TextReflectionSubmissionError.conflictingRetry) {
        try await service.submit(.init(id: id, bookID: book.id, sessionID: nil, locator: locator, originalText: "被替换的想法"))
    }
}

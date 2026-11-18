import Foundation
import LibraryCore
import Persistence
import ReaderCore
import ReadingSessionCore
import Testing

/// A session's duration is reading time, not the wall clock between opening a
/// book and leaving it. Before activity tracking, a book left open overnight
/// was recorded as 624 minutes; the shelf printed it as "读过 10 小时".
@Test func backgroundTimeIsNotCountedAsReading() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book()
    try await GRDBBookRepository(database: database).insert(book)
    let service = ReadingSessionService(repository: GRDBReadingSessionRepository(database: database))
    let t0 = Date(timeIntervalSince1970: 1_000)

    let session = try await service.start(bookID: book.id, at: TestFixtures.realisticLocator(), startedAt: t0)
    try await service.pause(id: session.id, at: t0.addingTimeInterval(60))
    // An hour in the background. None of it is reading.
    try await service.resume(id: session.id, at: t0.addingTimeInterval(3_600))
    let completed = try await service.end(
        id: session.id,
        at: TestFixtures.realisticLocator(progression: 0.5),
        endedAt: t0.addingTimeInterval(3_660),
        highlightCount: 0,
        noteCount: 0
    )

    #expect(completed.duration == 120)
}

/// The shelf card ("读过 24 分钟") reads the same number.
@Test func libraryStatsCountBankedReadingTimeNotTheSpan() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let book = TestFixtures.book()
    try await books.insert(book)
    let locator = try TestFixtures.realisticLocator()
    try await GRDBReadingSessionRepository(database: database).insert(
        ReadingSession(
            bookID: book.id,
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 8_200),
            startLocator: locator,
            endLocator: locator,
            activeDuration: 90
        ))

    let stats = try await books.libraryStats(for: [book.id])
    #expect(stats[book.id]?.readingSeconds == 90)
}

@Test func endingAnActiveSessionBanksTheOpenSegment() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book()
    try await GRDBBookRepository(database: database).insert(book)
    let service = ReadingSessionService(repository: GRDBReadingSessionRepository(database: database))
    let t0 = Date(timeIntervalSince1970: 1_000)

    let session = try await service.start(bookID: book.id, at: TestFixtures.realisticLocator(), startedAt: t0)
    let completed = try await service.end(
        id: session.id,
        at: TestFixtures.realisticLocator(progression: 0.5),
        endedAt: t0.addingTimeInterval(90),
        highlightCount: 0,
        noteCount: 0
    )

    #expect(completed.duration == 90)
    #expect(completed.activeSince == nil)
}

/// A session left open by a killed app used to be picked up by the next short
/// read, so its start time became the baseline: opening a book for five
/// seconds and closing it reported the whole gap. Past the resume window it is
/// closed where it stopped and a new one begins.
@Test func aStaleOpenSessionIsClosedInsteadOfContinued() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book()
    try await GRDBBookRepository(database: database).insert(book)
    let repository = GRDBReadingSessionRepository(database: database)
    let service = ReadingSessionService(repository: repository)
    let t0 = Date(timeIntervalSince1970: 1_000)

    let leftover = try await service.start(bookID: book.id, at: TestFixtures.realisticLocator(progression: 0.1), startedAt: t0)
    try await service.pause(id: leftover.id, at: t0.addingTimeInterval(30))

    let dayLater = t0.addingTimeInterval(24 * 3_600)
    let fresh = try await service.start(bookID: book.id, at: TestFixtures.realisticLocator(progression: 0.6), startedAt: dayLater)

    #expect(fresh.id != leftover.id)
    let closed = try #require(try await repository.session(id: leftover.id))
    #expect(closed.endedAt == t0.addingTimeInterval(30))
    #expect(closed.duration == 30)
}

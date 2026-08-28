import Foundation
import LibraryCore
import ReadingSessionCore
import ReflectionCore
import Testing

/// TODAY-01: Today 状态机对未完成 Reflection 的处理——上次有意义的会话没有
/// 留下 Reflection 时提供补写入口；完成后、明确「今天先不了」后不再打扰。
private func meaningfulSession(_ book: Book, startedAt: TimeInterval, endedAt: TimeInterval) throws -> ReadingSession {
    let locator = try TestFixtures.realisticLocator()
    return ReadingSession(
        bookID: book.id,
        startedAt: .init(timeIntervalSince1970: startedAt),
        endedAt: .init(timeIntervalSince1970: endedAt),
        startLocator: locator,
        endLocator: locator
    )
}

@Test func todayOffersReflectionWhenLastMeaningfulSessionHasNoReflection() throws {
    let book = TestFixtures.book(fingerprint: "today-offer")
    let session = try meaningfulSession(book, startedAt: 100, endedAt: 400)
    #expect(TodayProductStateResolver.resolve(
        currentBook: book,
        sessions: [session],
        reflections: [],
        now: .init(timeIntervalSince1970: 500),
        calendar: Calendar(identifier: .gregorian)
    ) == .offerReflection(book, session))
}

@Test func todayIgnoresAccidentalShortSessionWithoutReflection() throws {
    let book = TestFixtures.book(fingerprint: "today-accidental")
    let locator = try TestFixtures.realisticLocator()
    let brief = ReadingSession(
        bookID: book.id,
        startedAt: .init(timeIntervalSince1970: 100),
        endedAt: .init(timeIntervalSince1970: 110),
        startLocator: locator,
        endLocator: locator
    )
    #expect(TodayProductStateResolver.resolve(
        currentBook: book,
        sessions: [brief],
        reflections: [],
        now: .init(timeIntervalSince1970: 500),
        calendar: Calendar(identifier: .gregorian)
    ) == .continueReading(book))
}

@Test func todayDoesNotOfferAgainOnceSessionHasReflection() throws {
    let book = TestFixtures.book(fingerprint: "today-complete")
    let session = try meaningfulSession(book, startedAt: 100, endedAt: 400)
    let reflection = Reflection(
        bookID: book.id,
        sessionID: session.id,
        originalText: "这一段留下的想法",
        inputKind: .text,
        createdAt: .init(timeIntervalSince1970: 500)
    )
    #expect(TodayProductStateResolver.resolve(
        currentBook: book,
        sessions: [session],
        reflections: [reflection],
        now: .init(timeIntervalSince1970: 500),
        calendar: Calendar(identifier: .gregorian)
    ) == .reflectionComplete(book))
}

@Test func todayStaysQuietAfterExplicitDismissal() throws {
    let book = TestFixtures.book(fingerprint: "today-dismissed")
    let session = try meaningfulSession(book, startedAt: 100, endedAt: 400)
    #expect(TodayProductStateResolver.resolve(
        currentBook: book,
        sessions: [session],
        reflections: [],
        dismissedSessionIDs: [session.id],
        now: .init(timeIntervalSince1970: 500),
        calendar: Calendar(identifier: .gregorian)
    ) == .continueReading(book))
}

@Test func todayDismissalOnlyCoversItsOwnSession() throws {
    let book = TestFixtures.book(fingerprint: "today-dismissal-scope")
    let older = try meaningfulSession(book, startedAt: 100, endedAt: 400)
    let newer = try meaningfulSession(book, startedAt: 1000, endedAt: 1300)
    #expect(TodayProductStateResolver.resolve(
        currentBook: book,
        sessions: [older, newer],
        reflections: [],
        dismissedSessionIDs: [older.id],
        now: .init(timeIntervalSince1970: 1400),
        calendar: Calendar(identifier: .gregorian)
    ) == .offerReflection(book, newer))
}

@Test func todayCompletionOutranksDismissal() throws {
    let book = TestFixtures.book(fingerprint: "today-complete-after-dismissal")
    let session = try meaningfulSession(book, startedAt: 100, endedAt: 400)
    let reflection = Reflection(
        bookID: book.id,
        sessionID: session.id,
        originalText: "后来还是写下了",
        inputKind: .text,
        createdAt: .init(timeIntervalSince1970: 500)
    )
    #expect(TodayProductStateResolver.resolve(
        currentBook: book,
        sessions: [session],
        reflections: [reflection],
        dismissedSessionIDs: [session.id],
        now: .init(timeIntervalSince1970: 500),
        calendar: Calendar(identifier: .gregorian)
    ) == .reflectionComplete(book))
}

@Test func todayStillResolvesWithoutABook() {
    #expect(TodayProductStateResolver.resolve(
        currentBook: nil,
        sessions: [],
        reflections: [],
        dismissedSessionIDs: [ReadingSessionID()]
    ) == .noCurrentBook)
}

/// 明确的「今天先不了」需要本地标记（完成与否本来就由 reflections 表派生）。
/// 标记按会话去重、有界，纯 UserDefaults 本地存储，离线可用。
@Test func reflectionDismissalStoreRoundTripsDeduplicatesAndPrunes() throws {
    let suiteName = "today.reflectionDismissedSessionIDs.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = ReflectionPromptDismissalStore(defaults: defaults, capacity: 2)
    #expect(store.dismissedSessionIDs().isEmpty)

    let first = ReadingSessionID()
    let second = ReadingSessionID()
    let third = ReadingSessionID()
    store.dismiss(first)
    store.dismiss(first) // 同一会话重复 dismissal 只记一次
    store.dismiss(second)
    #expect(store.dismissedSessionIDs() == [first, second])

    store.dismiss(third) // 超出容量时淘汰最早的记录
    #expect(store.dismissedSessionIDs() == [second, third])
}

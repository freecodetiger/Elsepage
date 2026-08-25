import Foundation
import LibraryCore
import Persistence
import ReadingSessionCore
import ReflectionCore
import Testing

private let utc = TimeZone(secondsFromGMT: 0)!

private func fixedCalendarAndNow() -> (Calendar, Date) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 12))!
    return (calendar, now)
}

private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int, calendar: Calendar) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

@Test func emptyHistoryIsZero() {
    let (calendar, now) = fixedCalendarAndNow()
    #expect(StreakCalculator.readingStreak(sessionStartDates: [], now: now, calendar: calendar).days == 0)
    #expect(StreakCalculator.thinkingStreak(reflectionDates: [], now: now, calendar: calendar).days == 0)
}

@Test func sameDayMultipleEntriesCountOnce() {
    let (calendar, now) = fixedCalendarAndNow()
    let morning = day(2026, 8, 25, hour: 9, calendar: calendar)
    let noon = day(2026, 8, 25, hour: 13, calendar: calendar)
    let night = day(2026, 8, 25, hour: 22, calendar: calendar)
    #expect(StreakCalculator.readingStreak(
        sessionStartDates: [morning, noon, night], now: now, calendar: calendar
    ).days == 1)
}

@Test func fiveConsecutiveDaysCountFive() {
    let (calendar, now) = fixedCalendarAndNow()
    let dates = (0..<5).compactMap { calendar.date(byAdding: .day, value: -$0, to: now) }
    #expect(StreakCalculator.readingStreak(sessionStartDates: dates, now: now, calendar: calendar).days == 5)
}

@Test func aGapBreaksTheStreak() {
    let (calendar, now) = fixedCalendarAndNow()
    let today = now
    let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
    let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now)!
    let fourDaysAgo = calendar.date(byAdding: .day, value: -4, to: now)!
    let fiveDaysAgo = calendar.date(byAdding: .day, value: -5, to: now)!
    // today…twoDaysAgo present, threeDaysAgo missing → streak is 3.
    #expect(StreakCalculator.readingStreak(
        sessionStartDates: [today, yesterday, twoDaysAgo, fourDaysAgo, fiveDaysAgo],
        now: now, calendar: calendar
    ).days == 3)
}

@Test func crossMonthBoundaryCountsConsecutive() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 3, hour: 12))!
    let feb28 = day(2026, 2, 28, hour: 10, calendar: calendar)
    let mar1 = day(2026, 3, 1, hour: 10, calendar: calendar)
    let mar2 = day(2026, 3, 2, hour: 10, calendar: calendar)
    let mar3 = day(2026, 3, 3, hour: 8, calendar: calendar)
    #expect(StreakCalculator.readingStreak(
        sessionStartDates: [feb28, mar1, mar2, mar3], now: now, calendar: calendar
    ).days == 4)
}

@Test func yesterdayGraceKeepsStreakAlive() {
    let (calendar, now) = fixedCalendarAndNow()
    let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
    #expect(StreakCalculator.thinkingStreak(reflectionDates: [yesterday], now: now, calendar: calendar).days == 1)
}

@Test func earlyMorningTodayDoesNotBreakYesterdayAnchoredStreak() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 0, minute: 30))!
    let yesterday = day(2026, 8, 24, hour: 23, calendar: calendar)
    let twoDaysAgo = day(2026, 8, 23, hour: 20, calendar: calendar)
    #expect(StreakCalculator.thinkingStreak(
        reflectionDates: [yesterday, twoDaysAgo], now: now, calendar: calendar
    ).days == 2)
}

@Test func streakNotAnchoredWithoutTodayOrYesterdayIsZero() {
    let (calendar, now) = fixedCalendarAndNow()
    let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now)!
    #expect(StreakCalculator.readingStreak(sessionStartDates: [twoDaysAgo], now: now, calendar: calendar).days == 0)
}

@Test func allReflectionsAndAllSessionsFetchAcrossBooks() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let first = TestFixtures.book(fingerprint: "streak-a")
    let second = TestFixtures.book(fingerprint: "streak-b")
    try await books.insert(first)
    try await books.insert(second)

    let reflections = GRDBReflectionRepository(database: database)
    try await reflections.insert(
        Reflection(bookID: first.id, originalText: "A thought", inputKind: .text),
        linkedHighlightIDs: [], evidence: []
    )
    try await reflections.insert(
        Reflection(bookID: second.id, originalText: "Another thought", inputKind: .text),
        linkedHighlightIDs: [], evidence: []
    )

    let sessions = GRDBReadingSessionRepository(database: database)
    let locator = try TestFixtures.realisticLocator()
    try await sessions.insert(ReadingSession(bookID: first.id, startLocator: locator))
    try await sessions.insert(ReadingSession(bookID: second.id, startLocator: locator))

    let allReflections = try await reflections.allReflections()
    #expect(allReflections.count == 2)
    #expect(allReflections.allSatisfy { $0.bookID == first.id || $0.bookID == second.id })
    #expect(try await sessions.allSessions().count == 2)
}

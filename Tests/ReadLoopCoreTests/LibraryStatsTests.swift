import Foundation
import LibraryCore
import Persistence
import ReaderCore
import ReadingSessionCore
import ReflectionCore
import Testing

/// LIB-01: 书架卡片统计来自现有表（readingSessions / highlights / reflections），
/// 一次分组查询完成，不允许每本书单独查询。
@Test func libraryStatsAggregateSessionsHighlightsAndReflectionsInOneQuery() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let sessions = GRDBReadingSessionRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let reading = GRDBReadingRepository(database: database)

    let annotated = TestFixtures.book(fingerprint: "stats-annotated")
    let untouched = TestFixtures.book(fingerprint: "stats-untouched")
    try await books.insert(annotated)
    try await books.insert(untouched)
    let locator = try TestFixtures.realisticLocator()

    // 30 分钟 + 5 分钟的已结束会话；未结束的会话不计入阅读时长。
    try await sessions.insert(ReadingSession(
        bookID: annotated.id,
        startedAt: .init(timeIntervalSince1970: 0),
        endedAt: .init(timeIntervalSince1970: 1800),
        startLocator: locator,
        endLocator: locator
    ))
    try await sessions.insert(ReadingSession(
        bookID: annotated.id,
        startedAt: .init(timeIntervalSince1970: 3600),
        endedAt: .init(timeIntervalSince1970: 3900),
        startLocator: locator,
        endLocator: locator
    ))
    try await sessions.insert(ReadingSession(
        bookID: annotated.id,
        startedAt: .init(timeIntervalSince1970: 7200),
        startLocator: locator
    ))

    for index in 0..<3 {
        try await reading.save(highlight: Highlight(
            bookID: annotated.id,
            locator: locator,
            color: .yellow,
            createdAt: .init(timeIntervalSince1970: TimeInterval(100 + index))
        ))
    }
    // 批注（notes）不属于 Highlight 数，也不属于 Reflection 数。
    try await reading.save(note: Note(bookID: annotated.id, locator: locator, body: "批注"))

    try await reflections.insert(Reflection(bookID: annotated.id, originalText: "第一次想法", inputKind: .text))
    try await reflections.insert(Reflection(bookID: annotated.id, originalText: "第二次想法", inputKind: .text))

    let stats = try await books.libraryStats(for: [annotated.id, untouched.id])
    #expect(stats[annotated.id] == BookLibraryStats(readingSeconds: 2100, highlightCount: 3, reflectionCount: 2))
    // 没有任何积累的书不出现在结果里，卡片据此省略整行元数据。
    #expect(stats[untouched.id] == nil)
}

@Test func libraryStatsStayConsistentAfterDerivedDataDeletes() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let sessions = GRDBReadingSessionRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let reading = GRDBReadingRepository(database: database)

    let book = TestFixtures.book(fingerprint: "stats-delete")
    try await books.insert(book)
    let locator = try TestFixtures.realisticLocator()
    let session = ReadingSession(
        bookID: book.id,
        startedAt: .init(timeIntervalSince1970: 0),
        endedAt: .init(timeIntervalSince1970: 60),
        startLocator: locator,
        endLocator: locator
    )
    try await sessions.insert(session)
    let highlight = Highlight(bookID: book.id, locator: locator, color: .blue)
    try await reading.save(highlight: highlight)
    let reflection = Reflection(bookID: book.id, sessionID: session.id, originalText: "留下的一条想法", inputKind: .text)
    try await reflections.insert(reflection)

    var stats = try await books.libraryStats(for: [book.id])
    #expect(stats[book.id] == BookLibraryStats(readingSeconds: 60, highlightCount: 1, reflectionCount: 1))

    // 删除 Reflection 后计数归零，但书籍仍有阅读时长，不会从结果中消失。
    try await reflections.delete(id: reflection.id)
    stats = try await books.libraryStats(for: [book.id])
    #expect(stats[book.id]?.reflectionCount == 0)
    #expect(stats[book.id]?.highlightCount == 1)
    #expect(stats[book.id]?.readingSeconds == 60)
}

@Test func libraryStatsHandleEmptyAndUnknownRequests() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    #expect(try await books.libraryStats(for: []) == [:])
    #expect(try await books.libraryStats(for: [BookID()]) == [:])
}

/// LIB-01 展示层约定：零值保持安静，不出现「0 分钟」。
@Test func bookStatsMetadataLineOmitsZeroesAndStaysQuiet() {
    #expect(BookLibraryStats().metadataDescription == nil)
    #expect(BookLibraryStats(readingSeconds: 45).metadataDescription == nil)
    #expect(BookLibraryStats(readingSeconds: 24 * 60).metadataDescription == "读过 24 分钟")
    #expect(BookLibraryStats(readingSeconds: 3 * 3600 + 12 * 60).metadataDescription == "读过 3 小时 12 分")
    #expect(BookLibraryStats(readingSeconds: 3 * 3600).metadataDescription == "读过 3 小时")
    #expect(BookLibraryStats(highlightCount: 3).metadataDescription == "划线 3")
    #expect(BookLibraryStats(reflectionCount: 2).metadataDescription == "想法 2")
    #expect(BookLibraryStats(readingSeconds: 24 * 60, highlightCount: 3, reflectionCount: 2).metadataDescription == "读过 24 分钟 · 划线 3 · 想法 2")
}

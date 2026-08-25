import Foundation
import LibraryCore
import Persistence
import ReflectionCore
import Testing

@Test func reflectionArchiveShowsRawSourceWithBookAndOnlyDerivedAgentResponse() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let firstBook = TestFixtures.book(fingerprint: "archive-first")
    let secondBook = TestFixtures.book(fingerprint: "archive-second")
    try await books.insert(firstBook)
    try await books.insert(secondBook)

    let earlier = Reflection(
        bookID: firstBook.id,
        originalText: "早一点的原始想法",
        inputKind: .text,
        createdAt: .init(timeIntervalSince1970: 100)
    )
    let later = Reflection(
        bookID: secondBook.id,
        originalText: "后来真正留下来的想法",
        inputKind: .text,
        createdAt: .init(timeIntervalSince1970: 200)
    )
    try await reflections.insert(earlier, linkedHighlightIDs: [], evidence: [])
    try await reflections.insert(later, linkedHighlightIDs: [], evidence: [])
    try await reflections.appendMessage(.init(
        reflectionID: later.id,
        author: .user,
        source: .userInput,
        content: "不能作为派生回应"
    ))
    try await reflections.appendMessage(.init(
        reflectionID: later.id,
        author: .agent,
        source: .agentGenerated,
        content: "这是可选的派生回应"
    ))

    let archive = ReflectionArchiveService(books: books, reflections: reflections)
    let entries = try await archive.recentEntries()

    #expect(entries.map(\.reflection.id) == [later.id, earlier.id])
    #expect(entries[0].book.id == secondBook.id)
    #expect(entries[0].reflection.originalText == "后来真正留下来的想法")
    #expect(entries[0].derivedAgentResponse?.content == "这是可选的派生回应")
    #expect(entries[1].derivedAgentResponse == nil)
}

@Test func thoughtsArchiveProjectionSearchesSourceBookAndConversationAndAppliesFilters() throws {
    let firstBook = Book(
        fingerprint: .init(rawValue: "projection-first"), title: "局外人",
        fileName: "first.epub", fileSize: 1
    )
    let secondBook = Book(
        fingerprint: .init(rawValue: "projection-second"), title: "置身事内",
        fileName: "second.epub", fileSize: 1
    )
    let firstReflection = Reflection(
        bookID: firstBook.id, originalText: "今天想到自由与责任", inputKind: .text
    )
    let secondReflection = Reflection(
        bookID: secondBook.id, originalText: "制度塑造局部选择", inputKind: .text
    )
    let response = try ReflectionMessage(
        reflectionID: firstReflection.id, author: .agent, source: .agentGenerated,
        content: "这里保留了一处张力"
    )
    let connection = ReflectionArchiveConnection(
        connection: .init(reflectionID: secondReflection.id, sourceReflectionID: firstReflection.id, relevance: 0.8),
        sourceReflection: firstReflection,
        sourceBook: firstBook,
        sourceLocator: nil
    )
    let entries = [
        ReflectionArchiveEntry(reflection: firstReflection, book: firstBook, messages: [response]),
        ReflectionArchiveEntry(reflection: secondReflection, book: secondBook, connections: [connection]),
    ]

    #expect(ThoughtsArchiveProjection.entries(entries, matching: "局外人", filter: .all).map(\.id) == [firstReflection.id])
    #expect(ThoughtsArchiveProjection.entries(entries, matching: "张力", filter: .all).map(\.id) == [firstReflection.id])
    #expect(ThoughtsArchiveProjection.entries(entries, matching: "", filter: .hasAgentResponse).map(\.id) == [firstReflection.id])
    #expect(ThoughtsArchiveProjection.entries(entries, matching: "", filter: .hasConnection).map(\.id) == [secondReflection.id])
}

@Test func thoughtsArchiveProjectionGroupsNewestFirstByMonthAndBook() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let firstBook = Book(
        fingerprint: .init(rawValue: "group-first"), title: "第一本",
        fileName: "first.epub", fileSize: 1
    )
    let secondBook = Book(
        fingerprint: .init(rawValue: "group-second"), title: "第二本",
        fileName: "second.epub", fileSize: 1
    )
    let january = ReflectionArchiveEntry(
        reflection: Reflection(
            bookID: firstBook.id, originalText: "一月", inputKind: .text,
            createdAt: calendar.date(from: DateComponents(year: 2025, month: 1, day: 10))!
        ),
        book: firstBook
    )
    let februaryFirst = ReflectionArchiveEntry(
        reflection: Reflection(
            bookID: firstBook.id, originalText: "二月较早", inputKind: .text,
            createdAt: calendar.date(from: DateComponents(year: 2025, month: 2, day: 5))!
        ),
        book: firstBook
    )
    let februaryLatest = ReflectionArchiveEntry(
        reflection: Reflection(
            bookID: secondBook.id, originalText: "二月最新", inputKind: .text,
            createdAt: calendar.date(from: DateComponents(year: 2025, month: 2, day: 12))!
        ),
        book: secondBook
    )
    let entries = [january, februaryFirst, februaryLatest]

    let months = ThoughtsArchiveProjection.monthSections(entries, calendar: calendar)
    try #require(months.count == 2)
    #expect(months[0].entries.map(\.reflection.originalText) == ["二月最新", "二月较早"])
    #expect(months[1].entries.map(\.reflection.originalText) == ["一月"])

    let books = ThoughtsArchiveProjection.bookSections(entries)
    #expect(books.map(\.book.title) == ["第二本", "第一本"])
    #expect(books[1].entries.map(\.reflection.originalText) == ["二月较早", "一月"])
}

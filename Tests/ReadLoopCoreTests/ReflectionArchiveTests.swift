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

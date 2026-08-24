import Foundation
import LibraryCore
import Persistence
import ReaderCore
import Testing

@Test func realisticLocatorPreservesExactJSONIncludingUnknownFields() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reading = GRDBReadingRepository(database: database)
    let book = TestFixtures.book(); try await books.insert(book)
    let locator = try TestFixtures.realisticLocator()
    try await reading.save(position: .init(bookID: book.id, locator: locator))
    let restored = try #require(try await reading.position(for: book.id)?.locator)
    #expect(restored.json == locator.json)
    let object = try #require(try JSONSerialization.jsonObject(with: restored.json) as? [String: Any])
    #expect((object["futureExtension"] as? [String: Any])?["version"] as? Int == 99)
    #expect(restored.textHighlight == "a page")
}

@Test func locatorOptionalTextContextRoundTripsAsNil() async throws {
    let locator = try TestFixtures.realisticLocator(includeText: false)
    let encoded = try JSONEncoder().encode(locator)
    let decoded = try JSONDecoder().decode(BookLocator.self, from: encoded)
    #expect(decoded == locator)
    #expect(decoded.textBefore == nil)
    #expect(decoded.textHighlight == nil)
    #expect(decoded.textAfter == nil)
}

@Test func highlightRestorationPlanIsStableAndReadiumIndependent() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reading = GRDBReadingRepository(database: database)
    let book = TestFixtures.book(); try await books.insert(book)
    let first = Highlight(bookID: book.id, locator: try TestFixtures.realisticLocator(), color: .yellow)
    let second = Highlight(bookID: book.id, locator: try TestFixtures.realisticLocator(progression: 0.8), color: .blue)
    try await reading.save(highlight: first); try await reading.save(highlight: second)
    let decorations = try await HighlightRestorationService(repository: reading).decorations(for: book.id)
    #expect(decorations.map(\.id) == [first.id.uuidString.lowercased(), second.id.uuidString.lowercased()])
    #expect(decorations.map(\.locator.json) == [first.locator.json, second.locator.json])
    #expect(decorations.map(\.color) == [.yellow, .blue])
}

@Test func searchResultKeepsStableLocatorAndIdentity() throws {
    let locator = try TestFixtures.realisticLocator()
    let first = ReaderSearchResult(locator: locator, excerpt: "a page")
    let second = ReaderSearchResult(locator: locator, excerpt: "different presentation")
    #expect(first.locator.json == locator.json)
    #expect(first.id == second.id)
    #expect(first.excerpt == "a page")
}

import Foundation
import LibraryCore
import ReaderCore
import RetrievalCore
import Testing

@Test func chunkerPreservesStructureLocatorAndStableIdentity() throws {
    let book = BookID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    let a = try locator("a.xhtml", 0.1), b = try locator("a.xhtml", 0.2), c = try locator("b.xhtml", 0.1)
    let blocks = [
        BookTextBlock(id: .init(rawValue: "a0"), bookID: book, resourceHref: "a.xhtml", chapterID: "c1", chapterTitle: "一", sectionID: "s1", resourceOrdinal: 0, ordinal: 0, text: "第一段", startLocator: a, endLocator: a),
        BookTextBlock(id: .init(rawValue: "a1"), bookID: book, resourceHref: "a.xhtml", chapterID: "c1", chapterTitle: "一", sectionID: "s1", resourceOrdinal: 0, ordinal: 1, text: "第二段", startLocator: b, endLocator: b),
        BookTextBlock(id: .init(rawValue: "b0"), bookID: book, resourceHref: "b.xhtml", chapterID: "c2", chapterTitle: "二", resourceOrdinal: 1, ordinal: 0, text: "第三段", startLocator: c, endLocator: c),
    ]
    let chunker = StructureAwareChunker(targetCharacters: 100, maximumCharacters: 200)
    let first = chunker.chunks(from: blocks, indexVersion: 1)
    let second = chunker.chunks(from: blocks, indexVersion: 1)
    #expect(first == second)
    #expect(first.count == 2)
    #expect(first[0].text == "第一段\n\n第二段")
    #expect(first[0].startLocator.json == a.json)
    #expect(first[0].endLocator.json == b.json)
}

@Test func chunkerSplitsOversizedBlocksAndReadBoundaryExcludesFutureContent() throws {
    let book = BookID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    let start = try locator("a.xhtml", 0.2)
    let block = BookTextBlock(id: .init(rawValue: "long"), bookID: book, resourceHref: "a.xhtml", resourceOrdinal: 0, ordinal: 0, text: String(repeating: "字", count: 25), startLocator: start, endLocator: start)
    let chunks = StructureAwareChunker(targetCharacters: 8, maximumCharacters: 10).chunks(from: [block], indexVersion: 1)
    #expect(chunks.map { $0.text.count } == [10, 10, 5])
    #expect(ReadingBoundary(resourceOrdinal: 0, progression: 0.1).contains(chunks[0]) == false)
    #expect(ReadingBoundary(resourceOrdinal: 1).contains(chunks[0]))
}

private func locator(_ href: String, _ progression: Double) throws -> BookLocator {
    let data = try JSONSerialization.data(withJSONObject: ["href": href, "locations": ["progression": progression], "future": ["x": 1]])
    return try BookLocator(json: data, href: href, progression: progression)
}

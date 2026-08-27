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
    #expect(first == second) // parents AND children are content-addressed & deterministic
    let parents = first.filter { $0.role == .parent }
    #expect(parents.count == 2)
    #expect(parents[0].text == "第一段\n\n第二段")
    #expect(parents[0].startLocator.json == a.json)
    #expect(parents[0].endLocator.json == b.json)
}

@Test func chunkerSplitsOversizedBlocksAndReadBoundaryExcludesFutureContent() throws {
    let book = BookID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    let start = try locator("a.xhtml", 0.2)
    let block = BookTextBlock(id: .init(rawValue: "long"), bookID: book, resourceHref: "a.xhtml", resourceOrdinal: 0, ordinal: 0, text: String(repeating: "字", count: 25), startLocator: start, endLocator: start)
    // overlapCharacters: 0 keeps this test about hard-boundary splitting + boundary filter, not overlap.
    let all = StructureAwareChunker(targetCharacters: 8, maximumCharacters: 10, overlapCharacters: 0).chunks(from: [block], indexVersion: 1)
    let parents = all.filter { $0.role == .parent }
    #expect(parents.map { $0.text.count } == [10, 10, 5])
    #expect(ReadingBoundary(resourceOrdinal: 0, progression: 0.1).contains(parents[0]) == false)
    #expect(ReadingBoundary(resourceOrdinal: 1).contains(parents[0]))
}

@Test func chunkerSplitPartsShareOverlapAcrossBoundaries() throws {
    let book = BookID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    let start = try locator("a.xhtml", 0.2)
    let block = BookTextBlock(id: .init(rawValue: "overlap"), bookID: book, resourceHref: "a.xhtml", resourceOrdinal: 0, ordinal: 0, text: "abcdefghijklmnopqrstuvwxyz", startLocator: start, endLocator: start)
    // max=10, overlap=4 → parts advance by 6: [0,10) [6,16) [12,22) [18,26) [24,26);
    // consecutive parts share 4 chars (last part is the 2-char tail).
    let all = StructureAwareChunker(targetCharacters: 8, maximumCharacters: 10, overlapCharacters: 4).chunks(from: [block], indexVersion: 1)
    let parents = all.filter { $0.role == .parent }
    #expect(parents.map { $0.text.count } == [10, 10, 10, 8, 2])
    #expect(parents[0].text == "abcdefghij")
    #expect(parents[1].text == "ghijklmnop")
    #expect(parents[2].text == "mnopqrstuv")
    #expect(parents[3].text == "stuvwxyz")
}

@Test func chunkerProducesRetrievalChildrenLinkedUnderParents() throws {
    let book = BookID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    let blocks = try (0..<4).map { i -> BookTextBlock in
        let loc = try locator("a.xhtml", Double(i) * 0.1 + 0.05)
        return BookTextBlock(id: .init(rawValue: "p\(i)"), bookID: book, resourceHref: "a.xhtml", resourceOrdinal: 0, ordinal: i,
            text: "第\(i)段:这是一段足够长的检索内容文本", startLocator: loc, endLocator: loc)
    }
    // One parent (all 4 blocks under target) → children group blocks until ~childTarget.
    let chunker = StructureAwareChunker(targetCharacters: 1_000, maximumCharacters: 2_000, childTargetCharacters: 30, childMaximumCharacters: 60)
    let chunks = chunker.chunks(from: blocks, indexVersion: 1)
    let parents = chunks.filter { $0.role == .parent }
    let children = chunks.filter { $0.role == .child }
    #expect(parents.count == 1)
    #expect(children.count == 2)
    // Children are linked to the parent and never cross its structure/boundary.
    #expect(children.allSatisfy { $0.parentID == parents[0].id })
    #expect(children.allSatisfy { $0.resourceOrdinal == parents[0].resourceOrdinal && $0.resourceHref == parents[0].resourceHref })
    // Children cover every source block of the parent, and their joined text
    // reproduces the parent exactly (small-to-big reconstruction).
    #expect(children.flatMap(\.sourceBlockIDs).count == 4)
    #expect(children.map(\.text).joined(separator: "\n\n") == parents[0].text)
    // Child ordinals are disjoint from parent ordinals (schema UNIQUE safety).
    #expect(children.allSatisfy { $0.ordinal >= 10_000 })
    // Deterministic across runs.
    #expect(chunks == chunker.chunks(from: blocks, indexVersion: 1))
}

private func locator(_ href: String, _ progression: Double) throws -> BookLocator {
    let data = try JSONSerialization.data(withJSONObject: ["href": href, "locations": ["progression": progression], "future": ["x": 1]])
    return try BookLocator(json: data, href: href, progression: progression)
}

import Foundation
import GRDB
import LibraryCore
import Persistence
import ReaderCore
import RetrievalCore
import Testing

@Test func expanderBuildsParentWindowFromHitChildAndSiblings() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "s2b"), title: "S2B", fileName: "s2b.epub", fileSize: 1)
    try await books.insert(book)
    let (parent, children) = try makeFamily(book: book.id, texts: ["甲段落", "乙段落", "丙段落", "丁段落"])
    try await index.replace(chunks: [parent] + children, for: book.id, version: BookIndexPipeline.currentVersion)

    let expander = SmallToBigExpander(windowCharacterBudget: 1_200, maxSiblingsPerSide: 3)
    let windows = try await expander.expand([(children[1], 0.9)], boundary: nil, using: index, bookID: book.id, version: BookIndexPipeline.currentVersion)

    #expect(windows.count == 1)
    let window = windows[0].0
    // Parent-anchored: the window carries the parent's id and reconstructs its text.
    #expect(window.id == parent.id)
    #expect(window.role == .parent)
    #expect(window.text == "甲段落\n\n乙段落\n\n丙段落\n\n丁段落")
    #expect(window.startLocator.href == parent.startLocator.href)
    #expect(window.startLocator.progression == parent.startLocator.progression)
}

@Test func expanderClampsParentWindowAcrossReadingBoundary() async throws {
    // Spec case: a legal child (36.5→36.9) sits in a parent that crosses the user's
    // reading position (37.2). The window must end within the boundary: the child
    // after the boundary is excluded and the straddling tail is trimmed.
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "spoiler"), title: "Spoiler", fileName: "spoiler.epub", fileSize: 1)
    try await books.insert(book)
    let (parent, children) = try makeStraddlingFamily(book: book.id)
    try await index.replace(chunks: [parent] + children, for: book.id, version: BookIndexPipeline.currentVersion)

    let boundary = ReadingBoundary(resourceOrdinal: 0, progression: 0.372)
    let expander = SmallToBigExpander(windowCharacterBudget: 1_200, maxSiblingsPerSide: 3)
    let windows = try await expander.expand([(children[0], 0.9)], boundary: boundary, using: index, bookID: book.id, version: BookIndexPipeline.currentVersion)

    let window = try #require(windows.first?.0)
    #expect(window.id == parent.id)
    // In-boundary sibling + the straddler trimmed to the boundary fraction.
    #expect(window.text == "事件发生在雨天\n\n但之后的情节")
    // The window's end stays at or before the boundary.
    #expect(window.endLocator.progression ?? 1 <= (boundary.progression ?? 1))
}

@Test func expanderPassesThroughParentlessChildren() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "orphan"), title: "Orphan", fileName: "orphan.epub", fileSize: 1)
    try await books.insert(book)
    let standalone = try chunk(book: book.id, id: "child", resource: 0, ordinal: 0, progression: 0.1, text: "无父段落的检索单元", role: .child)
    try await index.replace(chunks: [standalone], for: book.id, version: BookIndexPipeline.currentVersion)

    let expander = SmallToBigExpander()
    let windows = try await expander.expand([(standalone, 0.8)], boundary: nil, using: index, bookID: book.id, version: BookIndexPipeline.currentVersion)
    #expect(windows.count == 1)
    #expect(windows[0].0.id == standalone.id) // tolerant pass-through, no parent to expand to
}

@Test func localBookRetrieverExpandsToParentAnchoredEvidence() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "retr"), title: "Retr", fileName: "retr.epub", fileSize: 1)
    try await books.insert(book)
    let (parent, children) = try makeFamily(book: book.id, texts: ["制度结构的意义", "个人选择与制度", "自由的边界"])
    try await index.replace(chunks: [parent] + children, for: book.id, version: BookIndexPipeline.currentVersion)

    let retriever = LocalBookRetriever(repository: index, expander: .init(windowCharacterBudget: 1_200, maxSiblingsPerSide: 3))
    let results = try await retriever.retrieve(.init(bookID: book.id, text: "制度", boundary: nil, limit: 1))
    #expect(results.count == 1)
    #expect(results[0].id == parent.id)          // parent-anchored evidence
    #expect(results[0].excerpt == "制度结构的意义\n\n个人选择与制度\n\n自由的边界") // expanded window
    #expect(results[0].locator.href == parent.startLocator.href)
}

// MARK: - Fixtures

private func makeFamily(book: BookID, texts: [String]) throws -> (BookChunk, [BookChunk]) {
    let parent = try chunk(book: book, id: "parent", resource: 0, ordinal: 0, progression: 0.1, text: texts.joined(separator: "\n\n"), role: .parent)
    // Children use the real schema's ordinal offset (>=10_000) so they never
    // collide with parent ordinals in UNIQUE(book,version,resource,ordinal).
    let children = try texts.enumerated().map { i, text in
        try chunk(book: book, id: "c\(i)", resource: 0, ordinal: 10_000 + i, progression: 0.1 + Double(i) * 0.02, text: text, role: .child, parentID: parent.id)
    }
    return (parent, children)
}

/// parent 35%→39% with children 36.5→36.9 / 36.9→37.5 / 37.5→39.0; user at 37.2%.
private func makeStraddlingFamily(book: BookID) throws -> (BookChunk, [BookChunk]) {
    let parent = try chunk(book: book, id: "parent", resource: 0, ordinal: 0, progression: 0.35, text: "事件发生在雨天\n\n但之后的情节走向尚未读到\n\n结局反转", role: .parent)
    let c1 = try chunk(book: book, id: "c1", resource: 0, ordinal: 10_000, progression: 0.365, endProgression: 0.369, text: "事件发生在雨天", role: .child, parentID: parent.id)
    let c2 = try chunk(book: book, id: "c2", resource: 0, ordinal: 10_001, progression: 0.369, endProgression: 0.375, text: "但之后的情节走向尚未读到", role: .child, parentID: parent.id)
    let c3 = try chunk(book: book, id: "c3", resource: 0, ordinal: 10_002, progression: 0.375, endProgression: 0.390, text: "结局反转", role: .child, parentID: parent.id)
    return (parent, [c1, c2, c3])
}

private func chunk(book: BookID, id: String, resource: Int, ordinal: Int, progression: Double, endProgression: Double? = nil, text: String, role: BookChunkRole, parentID: BookChunkID? = nil) throws -> BookChunk {
    let end = endProgression ?? progression
    let startLocator = try locator(resource, progression)
    let endLocator = try locator(resource, end)
    return BookChunk(id: .init(rawValue: id), bookID: book, resourceHref: "\(resource).xhtml",
        resourceOrdinal: resource, ordinal: ordinal, text: text, normalizedText: text,
        startLocator: startLocator, endLocator: endLocator, sourceBlockIDs: [.init(rawValue: "b-\(id)")],
        role: role, parentID: parentID)
}

private func locator(_ resource: Int, _ progression: Double) throws -> BookLocator {
    let data = try JSONSerialization.data(withJSONObject: ["href": "\(resource).xhtml", "locations": ["progression": progression]])
    return try BookLocator(json: data, href: "\(resource).xhtml", progression: progression)
}

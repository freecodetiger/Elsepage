import Foundation
import GRDB
import LibraryCore
import Persistence
import ReaderCore
import RetrievalCore
import Testing

@Test func v7IndexIsSearchableIdempotentAndCascadesWithBook() async throws {
    let db = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: db)
    let index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "abc"), title: "Test", fileName: "test.epub", fileSize: 10)
    try await books.insert(book)
    let chunks = [
        try chunk(book: book.id, id: "read", resource: 0, progression: 0.2, text: "制度结构会影响每个人的局部选择"),
        try chunk(book: book.id, id: "future", resource: 2, progression: 0.8, text: "制度结构的未来结局尚未读到"),
    ]
    try await index.replace(chunks: chunks, for: book.id, version: BookIndexPipeline.currentVersion)
    try await index.replace(chunks: chunks, for: book.id, version: BookIndexPipeline.currentVersion)
    #expect(try await index.chunks(for: book.id, version: BookIndexPipeline.currentVersion).count == 2)
    let found = try await index.lexicalSearch(bookID: book.id, query: "制度结构", boundary: .init(resourceOrdinal: 0, progression: 0.5), limit: 10)
    #expect(found.map { $0.0.id.rawValue } == ["read"])
    let currentResource = try await index.lexicalSearch(bookID: book.id, query: "制度结构",
        boundary: .init(resourceOrdinal: 2, progression: 0.9), limit: 10, scope: .currentResource)
    #expect(currentResource.map { $0.0.id.rawValue } == ["future"])
    try await index.saveEmbeddings([.init(rawValue: "read"): [1, 0]], model: "fake", dimensions: 2)
    #expect(try await index.embeddings(bookID: book.id, model: "fake").count == 1)
    try await books.delete(book.id)
    #expect(try await index.chunks(for: book.id, version: BookIndexPipeline.currentVersion).isEmpty)
    let counts = try await db.writer.read { db in
        (try Int.fetchOne(db, sql: "SELECT count(*) FROM bookChunksFTS")!,
         try Int.fetchOne(db, sql: "SELECT count(*) FROM bookChunkEmbeddings")!)
    }
    #expect(counts.0 == 0)
    #expect(counts.1 == 0)
}

@Test func indexJobRoundTripsFailureAndResumeCursor() async throws {
    let db = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: db)
    let index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "job"), title: "Job", fileName: "job.epub", fileSize: 1)
    try await books.insert(book)
    let expected = BookIndexJob(bookID: book.id, indexVersion: 1, state: .failed, nextResourceOrdinal: 7, lastError: "interrupted", updatedAt: Date(timeIntervalSince1970: 1))
    try await index.save(job: expected)
    #expect(try await index.job(for: book.id, version: 1) == expected)
}

@Test func interruptedPipelineRestartsIdempotentlyAndReachesLexicalReady() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "resume"), title: "Resume", fileName: "resume.epub", fileSize: 1)
    try await books.insert(book)
    let locator = try locator(href: "0.xhtml", progression: 0.1)
    let block = BookTextBlock(id: .init(rawValue: "block"), bookID: book.id, resourceHref: "0.xhtml", resourceOrdinal: 0, ordinal: 0, text: "可以恢复的本地索引文本", startLocator: locator, endLocator: locator)
    let extractor = InterruptibleExtractor(blocks: [block], shouldFail: true)
    let pipeline = BookIndexPipeline(extractor: extractor, repository: index, chunker: .init(targetCharacters: 20, maximumCharacters: 40))
    await #expect(throws: TestExtractionError.self) { try await pipeline.index(bookID: book.id) }
    #expect(try await index.job(for: book.id, version: BookIndexPipeline.currentVersion)?.state == .failed)
    #expect(try await index.chunks(for: book.id, version: BookIndexPipeline.currentVersion).isEmpty)
    await extractor.setShouldFail(false)
    try await pipeline.index(bookID: book.id)
    #expect(try await index.job(for: book.id, version: BookIndexPipeline.currentVersion)?.state == .lexicalReady)
    // Small-to-big: one parent chunk + its single retrieval child.
    #expect(try await index.chunks(for: book.id, version: BookIndexPipeline.currentVersion).count == 2)
    try await pipeline.index(bookID: book.id)
    #expect(try await index.chunks(for: book.id, version: BookIndexPipeline.currentVersion).count == 2)
}

@Test func versionBumpClearsStaleIndexBeforeRebuildingWithoutConstraintError() async throws {
    // Regression: a v2 index leaves bookTextBlocks rows whose ids ("v1|book|N|M")
    // are format-tagged, not versioned. Indexing at currentVersion (3) must clear
    // the stale v2 rows first, or re-inserting the same ids hits the PRIMARY KEY
    // → SQLITE_CONSTRAINT (error 19) on every upgraded book.
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "stale"), title: "Stale", fileName: "stale.epub", fileSize: 1)
    try await books.insert(book)
    let locator = try locator(href: "0.xhtml", progression: 0.1)
    let staleBlock = BookTextBlock(id: .init(rawValue: "v1|\(book.id)|0|0"), bookID: book.id, resourceHref: "0.xhtml",
        resourceOrdinal: 0, ordinal: 0, text: "旧版本的块", startLocator: locator, endLocator: locator)
    try await index.replace(blocks: [staleBlock], inResource: "0.xhtml", for: book.id, version: 2)
    try await index.save(job: BookIndexJob(bookID: book.id, indexVersion: 2, state: .lexicalReady))
    #expect(try await index.chunks(for: book.id, version: 2).isEmpty) // stale version present

    let block = BookTextBlock(id: .init(rawValue: "v1|\(book.id)|0|0"), bookID: book.id, resourceHref: "0.xhtml",
        resourceOrdinal: 0, ordinal: 0, text: "可恢复的本地索引文本", startLocator: locator, endLocator: locator)
    let extractor = InterruptibleExtractor(blocks: [block], shouldFail: false)
    let pipeline = BookIndexPipeline(extractor: extractor, repository: index, chunker: .init(targetCharacters: 20, maximumCharacters: 40))
    try await pipeline.index(bookID: book.id) // must NOT throw SQLITE_CONSTRAINT

    #expect(try await index.job(for: book.id, version: BookIndexPipeline.currentVersion)?.state == .lexicalReady)
    #expect(try await index.job(for: book.id, version: 2) == nil)          // stale job cleared
    #expect(try await index.chunks(for: book.id, version: 2).isEmpty)      // stale chunks cleared
    #expect(try await index.chunks(for: book.id, version: BookIndexPipeline.currentVersion).count == 2) // parent + child
}

@Test func contextBuilderNeverSearchesBeyondCurrentLocatorAndHonorsBudget() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "context"), title: "Context", fileName: "context.epub", fileSize: 1)
    try await books.insert(book)
    let chunks = [
        try chunk(book: book.id, id: "past", resource: 0, progression: 0.2, text: "个人选择与制度结构之间的张力"),
        try chunk(book: book.id, id: "future", resource: 2, progression: 0.2, text: "制度结构在结尾发生反转"),
    ]
    try await index.replace(chunks: chunks, for: book.id, version: BookIndexPipeline.currentVersion)
    let builder = ReaderAgentContextBuilder(retriever: LocalBookRetriever(repository: index), repository: index, characterBudget: 8)
    let context = try await builder.build(bookID: book.id, reflection: "制度结构", currentLocator: chunks[0].startLocator)
    #expect(context.evidence.map(\.id.rawValue) == ["past"])
    #expect(context.evidence[0].excerpt.count == 8)
}

private func chunk(
    book: BookID,
    id: String,
    resource: Int,
    progression: Double,
    endProgression: Double? = nil,
    text: String
) throws -> BookChunk {
    let start = try locator(href: "\(resource).xhtml", progression: progression)
    let end = try locator(href: "\(resource).xhtml", progression: endProgression ?? progression)
    // Retrieval targets children; fixtures insert retrieval units as .child.
    return BookChunk(id: .init(rawValue: id), bookID: book, resourceHref: start.href,
        resourceOrdinal: resource, ordinal: Int(progression * 100_000), text: text, normalizedText: text,
        startLocator: start, endLocator: end, sourceBlockIDs: [.init(rawValue: "block-\(id)")],
        role: .child)
}

private func locator(href: String, progression: Double?) throws -> BookLocator {
    guard let progression else {
        return try BookLocator(json: Data("{\"href\":\"\(href)\"}".utf8), href: href)
    }
    let json = try JSONSerialization.data(withJSONObject: ["href": href, "locations": ["progression": progression]])
    return try BookLocator(json: json, href: href, progression: progression)
}

private enum TestExtractionError: Error { case interrupted }
private actor InterruptibleExtractor: BookContentExtractor {
    let source: [BookTextBlock]
    var shouldFail: Bool
    init(blocks: [BookTextBlock], shouldFail: Bool) { source = blocks; self.shouldFail = shouldFail }
    func setShouldFail(_ value: Bool) { shouldFail = value }
    func blocks(for bookID: BookID, startingAtResource ordinal: Int) async throws -> AsyncThrowingStream<BookTextBlock, Error> {
        let selected = source.filter { $0.bookID == bookID && $0.resourceOrdinal >= ordinal }
        let fail = shouldFail
        return AsyncThrowingStream(BookTextBlock.self, bufferingPolicy: .unbounded) { continuation in
            for block in selected { continuation.yield(block) }
            if fail { continuation.finish(throwing: TestExtractionError.interrupted) } else { continuation.finish() }
        }
    }
}


@Test func readingBoundaryResolvesActiveChildAndCompleteActiveChunkPolicy() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "carc"), title: "CARC", fileName: "carc.epub", fileSize: 1)
    try await books.insert(book)
    let children = [
        try chunk(book: book.id, id: "c1", resource: 0, progression: 0.1, endProgression: 0.2, text: "结构一"),
        try chunk(book: book.id, id: "c2", resource: 0, progression: 0.2, endProgression: 0.4, text: "结构二"),
        try chunk(book: book.id, id: "c3", resource: 0, progression: 0.4, endProgression: 0.6, text: "结构三"),
    ]
    try await index.replace(chunks: children, for: book.id, version: BookIndexPipeline.currentVersion)
    let cursor = try locator(href: "0.xhtml", progression: 0.3)

    let boundary = try #require(try await index.readingBoundary(bookID: book.id, locator: cursor))
    #expect(boundary.activeChunkID == children[1].id)
    #expect(boundary.decision(for: children[0]) == .allowCompletedChunk)
    #expect(boundary.decision(for: children[1]) == .allowActiveChunk)
    #expect(boundary.decision(for: children[2]) == .denyFutureChunk)

    let results = try await index.lexicalSearch(
        bookID: book.id,
        query: "结构",
        boundary: boundary,
        limit: 10
    )
    #expect(results.map(\.0.id) == [children[0].id, children[1].id])
}

@Test func exactBoundaryDoesNotUnlockNextChildAndMissingProgressionFailsClosed() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "carc-exact"), title: "CARC", fileName: "carc.epub", fileSize: 1)
    try await books.insert(book)
    let children = [
        try chunk(book: book.id, id: "c1", resource: 0, progression: 0.1, endProgression: 0.2, text: "结构一"),
        try chunk(book: book.id, id: "c2", resource: 0, progression: 0.2, endProgression: 0.4, text: "结构二"),
    ]
    try await index.replace(chunks: children, for: book.id, version: BookIndexPipeline.currentVersion)

    let exact = try locator(href: "0.xhtml", progression: 0.2)
    let boundary = try #require(try await index.readingBoundary(bookID: book.id, locator: exact))
    #expect(boundary.activeChunkID == nil)
    #expect(boundary.decision(for: children[0]) == .allowCompletedChunk)
    #expect(boundary.decision(for: children[1]) == .denyFutureChunk)

    let missing = try BookLocator(json: Data("{\"href\":\"0.xhtml\"}".utf8), href: "0.xhtml")
    #expect(try await index.readingBoundary(bookID: book.id, locator: missing) == nil)
}

@Test func nearbyTextUsesCompleteActiveChildWithoutLocatorTextAfter() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "nearby-carc"), title: "Nearby", fileName: "nearby.epub", fileSize: 1)
    try await books.insert(book)
    let active = try chunk(book: book.id, id: "active", resource: 0, progression: 0.2, endProgression: 0.4, text: "当前段落完整内容")
    try await index.replace(chunks: [active], for: book.id, version: BookIndexPipeline.currentVersion)
    let cursor = try BookLocator(
        json: Data("{\"href\":\"0.xhtml\",\"locations\":{\"progression\":0.3}}".utf8),
        href: "0.xhtml",
        progression: 0.3,
        textBefore: "已读前缀",
        textHighlight: "当前",
        textAfter: "尚未读到的下一段"
    )
    let builder = ReaderAgentContextBuilder(retriever: LocalBookRetriever(repository: index), repository: index)
    let boundary = try #require(try await index.readingBoundary(bookID: book.id, locator: cursor))

    let text = try #require(await builder.nearbyText(for: book.id, locator: cursor, boundary: boundary))
    #expect(text.contains("当前段落完整内容"))
    #expect(!text.contains("尚未读到的下一段"))
}

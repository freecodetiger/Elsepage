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
    try await index.replace(chunks: chunks, for: book.id, version: 1)
    try await index.replace(chunks: chunks, for: book.id, version: 1)
    #expect(try await index.chunks(for: book.id, version: 1).count == 2)
    let found = try await index.lexicalSearch(bookID: book.id, query: "制度结构", boundary: .init(resourceOrdinal: 0, progression: 0.5), limit: 10)
    #expect(found.map { $0.0.id.rawValue } == ["read"])
    let currentResource = try await index.lexicalSearch(bookID: book.id, query: "制度结构",
        boundary: .init(resourceOrdinal: 2, progression: 0.9), limit: 10, scope: .currentResource)
    #expect(currentResource.map { $0.0.id.rawValue } == ["future"])
    try await index.saveEmbeddings([.init(rawValue: "read"): [1, 0]], model: "fake", dimensions: 2)
    #expect(try await index.embeddings(bookID: book.id, model: "fake").count == 1)
    try await books.delete(book.id)
    #expect(try await index.chunks(for: book.id, version: 1).isEmpty)
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
    #expect(try await index.chunks(for: book.id, version: BookIndexPipeline.currentVersion).count == 1)
    try await pipeline.index(bookID: book.id)
    #expect(try await index.chunks(for: book.id, version: BookIndexPipeline.currentVersion).count == 1)
}

@Test func contextBuilderNeverSearchesBeyondCurrentLocatorAndHonorsBudget() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "context"), title: "Context", fileName: "context.epub", fileSize: 1)
    try await books.insert(book)
    let chunks = [
        try chunk(book: book.id, id: "past", resource: 0, progression: 0.2, text: "个人选择与制度结构之间的张力"),
        try chunk(book: book.id, id: "future", resource: 2, progression: 0.2, text: "制度结构在结尾发生反转"),
    ]
    try await index.replace(chunks: chunks, for: book.id, version: 1)
    let builder = ReaderAgentContextBuilder(retriever: LocalBookRetriever(repository: index), repository: index, characterBudget: 8)
    let context = try await builder.build(bookID: book.id, reflection: "制度结构", currentLocator: chunks[0].startLocator)
    #expect(context.evidence.map(\.id.rawValue) == ["past"])
    #expect(context.evidence[0].excerpt.count == 8)
}

private func chunk(book: BookID, id: String, resource: Int, progression: Double, text: String) throws -> BookChunk {
    let json = try JSONSerialization.data(withJSONObject: ["href": "\(resource).xhtml", "locations": ["progression": progression], "unknownFutureField": ["kept": true]])
    let locator = try BookLocator(json: json, href: "\(resource).xhtml", progression: progression)
    return BookChunk(id: .init(rawValue: id), bookID: book, resourceHref: locator.href,
        resourceOrdinal: resource, ordinal: resource, text: text, normalizedText: text,
        startLocator: locator, endLocator: locator, sourceBlockIDs: [.init(rawValue: "block-\(id)")])
}

private func locator(href: String, progression: Double) throws -> BookLocator {
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

import Foundation
import GRDB
import LibraryCore
import Persistence
import ReaderCore
import RetrievalCore
import Testing

private actor EmbeddingCallRecorder {
    private(set) var batches: [[String]] = []
    func record(_ batch: [String]) { batches.append(batch) }
}

private struct RecordingEmbeddingProvider: EmbeddingProvider {
    let modelIdentifier: String
    let dimensions: Int
    let recorder: EmbeddingCallRecorder
    func embed(_ texts: [String]) async throws -> [[Float]] {
        await recorder.record(texts)
        return texts.map { _ in (0..<dimensions).map { Float($0) } }
    }
}

private struct SimpleExtractor: BookContentExtractor {
    let blocks: [BookTextBlock]
    func blocks(for bookID: BookID, startingAtResource ordinal: Int) async throws -> AsyncThrowingStream<BookTextBlock, Error> {
        AsyncThrowingStream(BookTextBlock.self, bufferingPolicy: .unbounded) { continuation in
            for block in blocks where block.bookID == bookID && block.resourceOrdinal >= ordinal {
                continuation.yield(block)
            }
            continuation.finish()
        }
    }
}

private func chunk(book: BookID, id: String, resource: Int, ordinal: Int, text: String) throws -> BookChunk {
    let locator = try BookLocator(json: JSONSerialization.data(withJSONObject: ["href": "\(resource).xhtml", "locations": ["progression": 0.5]]), href: "\(resource).xhtml", progression: 0.5)
    return BookChunk(id: .init(rawValue: id), bookID: book, resourceHref: locator.href,
        resourceOrdinal: resource, ordinal: ordinal, text: text, normalizedText: text,
        startLocator: locator, endLocator: locator, sourceBlockIDs: [.init(rawValue: "b-\(id)")],
        role: .child)
}

private func block(book: BookID, href: String, resource: Int, ordinal: Int, text: String) throws -> BookTextBlock {
    let locator = try BookLocator(json: JSONSerialization.data(withJSONObject: ["href": href, "locations": ["progression": 0.5]]), href: href, progression: 0.5)
    return BookTextBlock(id: .init(rawValue: "blk-\(resource)-\(ordinal)"), bookID: book, resourceHref: href,
        resourceOrdinal: resource, ordinal: ordinal, text: text, startLocator: locator, endLocator: locator)
}

@Test func embedPopulatesSemanticIndexFromLexicalReadyInBatches() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "embed"), title: "Embed", fileName: "embed.epub", fileSize: 1)
    try await books.insert(book)
    let chunks = try (0..<120).map { try chunk(book: book.id, id: "c\($0)", resource: $0 % 3, ordinal: $0, text: "第 \($0) 段内容") }
    try await index.replace(chunks: chunks, for: book.id, version: BookIndexPipeline.currentVersion)
    try await index.save(job: BookIndexJob(bookID: book.id, indexVersion: BookIndexPipeline.currentVersion, state: .lexicalReady, nextResourceOrdinal: 3))

    let recorder = EmbeddingCallRecorder()
    let provider = RecordingEmbeddingProvider(modelIdentifier: "embed-model", dimensions: 4, recorder: recorder)
    let factory: @Sendable () async -> (any EmbeddingProvider)? = { provider }
    try await BookIndexPipeline(repository: index, embeddings: factory).embed(bookID: book.id)

    let job = try #require(try await index.job(for: book.id, version: BookIndexPipeline.currentVersion))
    #expect(job.state == .ready)
    #expect(job.embeddingModel == "embed-model")
    #expect(try await index.embeddings(bookID: book.id, model: "embed-model").count == 120)
    let batches = await recorder.batches
    #expect(batches.count == 2) // 120 chunks / batchSize 100 → 2 batches
    #expect(batches.allSatisfy { $0.count <= 100 })
}

@Test func embedSkipsAlreadyEmbeddedWithSameModelUnlessForced() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "skip"), title: "Skip", fileName: "skip.epub", fileSize: 1)
    try await books.insert(book)
    let chunks = try (0..<3).map { try chunk(book: book.id, id: "c\($0)", resource: 0, ordinal: $0, text: "文本 \($0)") }
    try await index.replace(chunks: chunks, for: book.id, version: BookIndexPipeline.currentVersion)
    try await index.save(job: BookIndexJob(bookID: book.id, indexVersion: BookIndexPipeline.currentVersion, state: .lexicalReady))

    let recorder = EmbeddingCallRecorder()
    let provider = RecordingEmbeddingProvider(modelIdentifier: "m", dimensions: 2, recorder: recorder)
    let factory: @Sendable () async -> (any EmbeddingProvider)? = { provider }
    let pipeline = BookIndexPipeline(repository: index, embeddings: factory)

    try await pipeline.embed(bookID: book.id)
    let afterFirst = await recorder.batches.count
    #expect(afterFirst == 1)

    // Same model, not forced → skip (no new calls).
    try await pipeline.embed(bookID: book.id)
    #expect(await recorder.batches.count == afterFirst)

    // Forced → re-embeds.
    try await pipeline.embed(bookID: book.id, force: true)
    #expect(await recorder.batches.count == afterFirst + 1)
    let job = try #require(try await index.job(for: book.id, version: BookIndexPipeline.currentVersion))
    #expect(job.state == .ready)
    #expect(job.embeddingModel == "m")
}

@Test func embedReEmbedsWhenConfiguredModelChanges() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "switch"), title: "Switch", fileName: "switch.epub", fileSize: 1)
    try await books.insert(book)
    let chunks = try (0..<2).map { try chunk(book: book.id, id: "c\($0)", resource: 0, ordinal: $0, text: "文本 \($0)") }
    try await index.replace(chunks: chunks, for: book.id, version: BookIndexPipeline.currentVersion)
    try await index.save(job: BookIndexJob(bookID: book.id, indexVersion: BookIndexPipeline.currentVersion, state: .lexicalReady))

    let recorderA = EmbeddingCallRecorder()
    let factoryA: @Sendable () async -> (any EmbeddingProvider)? = {
        RecordingEmbeddingProvider(modelIdentifier: "model-a", dimensions: 2, recorder: recorderA)
    }
    try await BookIndexPipeline(repository: index, embeddings: factoryA).embed(bookID: book.id)
    #expect(try await index.embeddings(bookID: book.id, model: "model-a").count == 2)

    // Switch to model B → re-embed under B.
    let recorderB = EmbeddingCallRecorder()
    let factoryB: @Sendable () async -> (any EmbeddingProvider)? = {
        RecordingEmbeddingProvider(modelIdentifier: "model-b", dimensions: 3, recorder: recorderB)
    }
    try await BookIndexPipeline(repository: index, embeddings: factoryB).embed(bookID: book.id)

    let job = try #require(try await index.job(for: book.id, version: BookIndexPipeline.currentVersion))
    #expect(job.state == .ready)
    #expect(job.embeddingModel == "model-b")
    #expect(try await index.embeddings(bookID: book.id, model: "model-b").count == 2)
    #expect(try await index.embeddings(bookID: book.id, model: "model-a").count == 2) // old vectors kept per model key
}

@Test func embedNoOpsWhenFactoryUnavailable() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "noop"), title: "Noop", fileName: "noop.epub", fileSize: 1)
    try await books.insert(book)
    let chunks = try (0..<2).map { try chunk(book: book.id, id: "c\($0)", resource: 0, ordinal: $0, text: "文本 \($0)") }
    try await index.replace(chunks: chunks, for: book.id, version: BookIndexPipeline.currentVersion)
    try await index.save(job: BookIndexJob(bookID: book.id, indexVersion: BookIndexPipeline.currentVersion, state: .lexicalReady))

    try await BookIndexPipeline(repository: index).embed(bookID: book.id)
    #expect(try await index.job(for: book.id, version: BookIndexPipeline.currentVersion)?.state == .lexicalReady)
}

@Test func indexReachesReadyWithEmbeddingsWhenFactoryProvided() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "full"), title: "Full", fileName: "full.epub", fileSize: 1)
    try await books.insert(book)
    let blocks = [
        try block(book: book.id, href: "0.xhtml", resource: 0, ordinal: 0, text: "第一部分内容"),
        try block(book: book.id, href: "1.xhtml", resource: 1, ordinal: 0, text: "第二部分内容"),
    ]
    let recorder = EmbeddingCallRecorder()
    let factory: @Sendable () async -> (any EmbeddingProvider)? = {
        RecordingEmbeddingProvider(modelIdentifier: "full-model", dimensions: 2, recorder: recorder)
    }
    let pipeline = BookIndexPipeline(
        extractor: SimpleExtractor(blocks: blocks), repository: index,
        chunker: .init(targetCharacters: 20, maximumCharacters: 40),
        embeddings: factory
    )
    try await pipeline.index(bookID: book.id)

    let job = try #require(try await index.job(for: book.id, version: BookIndexPipeline.currentVersion))
    #expect(job.state == .ready)
    #expect(job.embeddingModel == "full-model")
    // Embedding counts retrieval children only, not parents (small-to-big).
    let embedded = try await index.embeddings(bookID: book.id, model: "full-model")
    let childrenCount = try await index.chunks(for: book.id, version: BookIndexPipeline.currentVersion).filter { $0.role == .child }.count
    #expect(embedded.count == childrenCount)
    #expect(childrenCount > 0)
}

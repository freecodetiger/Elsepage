import Foundation
import GRDB
import LibraryCore
import Persistence
import ReaderCore
import RetrievalCore
import Testing

@Test func bookIndexStatusAssemblesProgressAcrossStates() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let embedding = Book(fingerprint: .init(rawValue: "embedding"), title: "嵌入中", fileName: "embedding.epub", fileSize: 1)
    let stale = Book(fingerprint: .init(rawValue: "stale"), title: "旧模型", fileName: "stale.epub", fileSize: 1)
    let fresh = Book(fingerprint: .init(rawValue: "fresh"), title: "未建", fileName: "fresh.epub", fileSize: 1)
    try await books.insert(embedding)
    try await books.insert(stale)
    try await books.insert(fresh)

    // Book A: 2 resources, 3 chunks, mid-embedding, 2 of 3 embedded under "m".
    let chunksA = [
        try chunk(book: embedding.id, id: "a0", resource: 0, ordinal: 0, text: "文本一"),
        try chunk(book: embedding.id, id: "a1", resource: 1, ordinal: 0, text: "文本二"),
        try chunk(book: embedding.id, id: "a2", resource: 1, ordinal: 1, text: "文本三"),
    ]
    try await index.replace(chunks: chunksA, for: embedding.id, version: BookIndexPipeline.currentVersion)
    try await index.save(job: BookIndexJob(bookID: embedding.id, indexVersion: BookIndexPipeline.currentVersion, state: .embedding, nextResourceOrdinal: 2, embeddingModel: "m"))
    try await index.saveEmbeddings([.init(rawValue: "a0"): [1, 2], .init(rawValue: "a1"): [1, 2]], model: "m", dimensions: 2)

    // Book B: ready but embedded with an old model → semantic progress is 0 for "m".
    let chunksB = [try chunk(book: stale.id, id: "b0", resource: 0, ordinal: 0, text: "旧模型内容")]
    try await index.replace(chunks: chunksB, for: stale.id, version: BookIndexPipeline.currentVersion)
    try await index.save(job: BookIndexJob(bookID: stale.id, indexVersion: BookIndexPipeline.currentVersion, state: .ready, embeddingModel: "old-model"))

    // Book C: no job → pending.
    let service = BookIndexStatusService(books: books, repository: index, currentEmbeddingModel: { "m" })
    let statuses = try await service.status()

    let byID = Dictionary(uniqueKeysWithValues: statuses.map { ($0.bookID, $0) })
    #expect(statuses.count == 3)

    let a = try #require(byID[embedding.id])
    #expect(a.title == "嵌入中")
    #expect(a.state == .embedding)
    #expect(a.totalResources == 2)
    #expect(a.totalChunks == 3)
    #expect(a.embeddedCount == 2)
    #expect(abs(a.semanticFraction - (2.0 / 3.0)) < 0.001)
    #expect(a.embeddingModel == "m")

    let b = try #require(byID[stale.id])
    #expect(b.state == .ready)
    #expect(b.embeddedCount == 0) // vectors under "old-model" don't count toward "m"
    #expect(b.embeddingModel == "old-model")

    let c = try #require(byID[fresh.id])
    #expect(c.state == .pending)
    #expect(c.totalChunks == 0)
    #expect(c.totalResources == 0)
    #expect(c.embeddedCount == 0)
}

@Test func bookIndexStatusCountsNothingWhenEmbeddingDisabled() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "disabled"), title: "禁用", fileName: "disabled.epub", fileSize: 1)
    try await books.insert(book)
    let chunks = [try chunk(book: book.id, id: "d0", resource: 0, ordinal: 0, text: "内容")]
    try await index.replace(chunks: chunks, for: book.id, version: BookIndexPipeline.currentVersion)
    try await index.save(job: BookIndexJob(bookID: book.id, indexVersion: BookIndexPipeline.currentVersion, state: .ready, embeddingModel: "m"))
    try await index.saveEmbeddings([.init(rawValue: "d0"): [1]], model: "m", dimensions: 1)

    // currentEmbeddingModel == nil → no semantic indexing is active → 0 embedded.
    let service = BookIndexStatusService(books: books, repository: index, currentEmbeddingModel: { nil })
    let statuses = try await service.status()
    let status = try #require(statuses.first)
    #expect(status.embeddedCount == 0)
    #expect(status.totalChunks == 1)
}

private func chunk(book: BookID, id: String, resource: Int, ordinal: Int, text: String) throws -> BookChunk {
    let locator = try BookLocator(json: JSONSerialization.data(withJSONObject: ["href": "\(resource).xhtml", "locations": ["progression": 0.5]]), href: "\(resource).xhtml", progression: 0.5)
    return BookChunk(id: .init(rawValue: id), bookID: book, resourceHref: locator.href,
        resourceOrdinal: resource, ordinal: ordinal, text: text, normalizedText: text,
        startLocator: locator, endLocator: locator, sourceBlockIDs: [.init(rawValue: "b-\(id)")])
}

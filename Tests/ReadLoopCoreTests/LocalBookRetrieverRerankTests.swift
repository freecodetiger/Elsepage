import Foundation
import GRDB
import LibraryCore
import Persistence
import ReaderCore
import RetrievalCore
import Testing

@Test func localBookRetrieverAppliesRerankGateAndDropsBelowFloor() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "rr"), title: "Rerank", fileName: "rr.epub", fileSize: 1)
    try await books.insert(book)
    let chunks = [
        try chunk(book: book.id, id: "c0", text: "自由与制度"),
        try chunk(book: book.id, id: "c1", text: "自由市场"),
        try chunk(book: book.id, id: "c2", text: "完全无关的内容"),
    ]
    try await index.replace(chunks: chunks, for: book.id, version: 1)

    let reranker = FakeReranker { query, candidates in
        candidates.map { c in
            let score: Double = c.id == "c1" ? 0.9 : (c.id == "c0" ? 0.5 : 0.1)
            return RerankedPassage(id: c.id, score: score)
        }
    }
    let retriever = LocalBookRetriever(repository: index, reranker: { reranker }, minimumRelevance: 0.2)
    let results = try await retriever.retrieve(.init(bookID: book.id, text: "自由", boundary: nil, limit: 2))

    // c1 highest, c0 second; c2 (0.1) is below the 0.2 floor -> gated out.
    #expect(results.map(\.id.rawValue) == ["c1", "c0"])
}

@Test func localBookRetrieverFallsBackToFusedWhenRerankerFails() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "rr2"), title: "Rerank", fileName: "rr2.epub", fileSize: 1)
    try await books.insert(book)
    let chunks = [
        try chunk(book: book.id, id: "a", text: "制度结构"),
        try chunk(book: book.id, id: "b", text: "制度与市场"),
    ]
    try await index.replace(chunks: chunks, for: book.id, version: 1)

    // Throwing reranker must not break retrieval — results fall back to lexical order.
    let retriever = LocalBookRetriever(repository: index, reranker: { ThrowingReranker() })
    let results = try await retriever.retrieve(.init(bookID: book.id, text: "制度", boundary: nil, limit: 2))
    #expect(results.count == 2)
    #expect(results.map(\.id.rawValue).sorted() == ["a", "b"])
}

@Test func localBookRetrieverWithoutRerankerReturnsLexicalAsBefore() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "rr3"), title: "Rerank", fileName: "rr3.epub", fileSize: 1)
    try await books.insert(book)
    let chunks = [
        try chunk(book: book.id, id: "hit", text: "制度结构会影响选择"),
        try chunk(book: book.id, id: "miss", text: "完全无关的内容"),
    ]
    try await index.replace(chunks: chunks, for: book.id, version: 1)

    let retriever = LocalBookRetriever(repository: index) // no reranker
    let results = try await retriever.retrieve(.init(bookID: book.id, text: "制度结构", boundary: nil, limit: 2))
    #expect(results.map(\.id.rawValue).contains("hit"))
}

@Test func localBookRetrieverDefaultThresholdGatesIrrelevantPassages() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "default-gate"), title: "默认", fileName: "default.epub", fileSize: 1)
    try await books.insert(book)
    let chunks = [
        try chunk(book: book.id, id: "hit", text: "自由与制度"),
        try chunk(book: book.id, id: "noise", text: "自由市场"),
    ]
    try await index.replace(chunks: chunks, for: book.id, version: 1)

    let reranker = FakeReranker { _, candidates in
        candidates.map { RerankedPassage(id: $0.id, score: $0.id == "hit" ? 0.9 : 0.1) }
    }
    // Default minimumRelevance must gate: noise (0.1) is dropped without any explicit threshold.
    let retriever = LocalBookRetriever(repository: index, reranker: { reranker })
    let results = try await retriever.retrieve(.init(bookID: book.id, text: "自由", boundary: nil, limit: 2))
    #expect(results.map(\.id.rawValue) == ["hit"])
}

// MARK: - Fakes

private struct FakeReranker: Reranker {
    let modelIdentifier = "fake-reranker"
    let handler: @Sendable (String, [RerankCandidate]) -> [RerankedPassage]
    func rerank(query: String, candidates: [RerankCandidate], limit: Int?) async throws -> [RerankedPassage] {
        let scored = handler(query, candidates).sorted { $0.score > $1.score }
        return limit.map { Array(scored.prefix($0)) } ?? scored
    }
}

private struct ThrowingReranker: Reranker {
    let modelIdentifier = "throwing-reranker"
    func rerank(query: String, candidates: [RerankCandidate], limit: Int?) async throws -> [RerankedPassage] {
        throw TestRerankError.failed
    }
}

private enum TestRerankError: Error { case failed }

private func chunk(book: BookID, id: String, text: String) throws -> BookChunk {
    let locator = try BookLocator(json: JSONSerialization.data(withJSONObject: ["href": "0.xhtml", "locations": ["progression": 0.5]]), href: "0.xhtml", progression: 0.5)
    return BookChunk(id: .init(rawValue: id), bookID: book, resourceHref: locator.href,
        resourceOrdinal: 0, ordinal: id.hashValue & 0x7fff, text: text, normalizedText: text,
        startLocator: locator, endLocator: locator, sourceBlockIDs: [.init(rawValue: "b-\(id)")])
}

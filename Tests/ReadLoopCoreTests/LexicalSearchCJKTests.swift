import Foundation
import GRDB
import LibraryCore
import Persistence
import ReaderCore
import RetrievalCore
import Testing

@Test func longCJKQueryMatchesChunksSharingTrigramsNotJustExactPhrase() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "cjk1"), title: "CJK", fileName: "cjk1.epub", fileSize: 1)
    try await books.insert(book)
    let chunks = [
        try chunk(book: book.id, id: "full", resource: 0, ordinal: 0, text: "为什么作者在这里提到时间这个概念"),
        try chunk(book: book.id, id: "subset", resource: 0, ordinal: 1, text: "作者在这里提到时间"),
        try chunk(book: book.id, id: "unrelated", resource: 0, ordinal: 2, text: "完全无关的另一种内容"),
    ]
    try await index.replace(chunks: chunks, for: book.id, version: 1)

    // Under the old giant-phrase query this only matched "full"; the trigram-OR
    // form also recalls "subset" (shares contiguous 3-grams with the query).
    let found = try await index.lexicalSearch(bookID: book.id, query: "为什么作者在这里提到时间", boundary: nil, limit: 10)
    let ids = found.map { $0.0.id.rawValue }
    #expect(ids.contains("full"))
    #expect(ids.contains("subset"))
    #expect(!ids.contains("unrelated"))
}

@Test func twoCharacterCJKWordUsesSubstringFallback() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "cjk2"), title: "CJK", fileName: "cjk2.epub", fileSize: 1)
    try await books.insert(book)
    let chunks = [
        try chunk(book: book.id, id: "hasTime", resource: 0, ordinal: 0, text: "这里讨论了时间管理"),
        try chunk(book: book.id, id: "other", resource: 0, ordinal: 1, text: "这里没有相关内容"),
    ]
    try await index.replace(chunks: chunks, for: book.id, version: 1)

    let found = try await index.lexicalSearch(bookID: book.id, query: "时间", boundary: nil, limit: 10)
    #expect(found.map { $0.0.id.rawValue } == ["hasTime"])
}

@Test func queryPunctuationDoesNotBreakCJKTrigrams() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "cjk3"), title: "CJK", fileName: "cjk3.epub", fileSize: 1)
    try await books.insert(book)
    let chunks = [
        try chunk(book: book.id, id: "a", resource: 0, ordinal: 0, text: "作者在这里提出了观点"),
        try chunk(book: book.id, id: "b", resource: 0, ordinal: 1, text: "另一处不相关"),
    ]
    try await index.replace(chunks: chunks, for: book.id, version: 1)

    let found = try await index.lexicalSearch(bookID: book.id, query: "作者,在这里", boundary: nil, limit: 10)
    #expect(found.map { $0.0.id.rawValue } == ["a"])
}

@Test func mixedLatinCJKQueryMatchesQualifyingTerms() async throws {
    let db = try AppDatabase.inMemory(), books = GRDBBookRepository(database: db), index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "cjk4"), title: "CJK", fileName: "cjk4.epub", fileSize: 1)
    try await books.insert(book)
    let chunks = [
        try chunk(book: book.id, id: "mixed", resource: 0, ordinal: 0, text: "自由 freedom 与制度结构"),
        try chunk(book: book.id, id: "plain", resource: 0, ordinal: 1, text: "自由与制度"),
    ]
    try await index.replace(chunks: chunks, for: book.id, version: 1)

    let found = try await index.lexicalSearch(bookID: book.id, query: "自由 freedom", boundary: nil, limit: 10)
    #expect(found.map { $0.0.id.rawValue } == ["mixed"])
}

private func chunk(book: BookID, id: String, resource: Int, ordinal: Int, text: String) throws -> BookChunk {
    let locator = try BookLocator(json: JSONSerialization.data(withJSONObject: ["href": "\(resource).xhtml", "locations": ["progression": 0.5]]), href: "\(resource).xhtml", progression: 0.5)
    return BookChunk(id: .init(rawValue: id), bookID: book, resourceHref: locator.href,
        resourceOrdinal: resource, ordinal: ordinal, text: text, normalizedText: text,
        startLocator: locator, endLocator: locator, sourceBlockIDs: [.init(rawValue: "b-\(id)")])
}

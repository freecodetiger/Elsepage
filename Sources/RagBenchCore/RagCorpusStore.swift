import Foundation
import LibraryCore
import Persistence
import RetrievalCore

/// Reads `chunks.jsonl` and loads it back into the *production* repository.
///
/// Deliberately a load and never a rebuild. The geometry in the file is what
/// `BookIndexPipeline` + `StructureAwareChunker` produced on device; re-deriving
/// it here is precisely the drift this corpus exists to prevent.
public struct RagCorpus {
    public let records: [RagChunkRecord]

    public init(records: [RagChunkRecord]) { self.records = records }

    public static func load(from url: URL) throws -> RagCorpus {
        RagCorpus(records: try RagCorpusIO.decodeLines(RagChunkRecord.self, from: Data(contentsOf: url)))
    }

    /// Corpus book keys in file order.
    public var bookKeys: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for record in records where seen.insert(record.bookKey).inserted { ordered.append(record.bookKey) }
        return ordered
    }

    public func records(forBook key: String) -> [RagChunkRecord] {
        records.filter { $0.bookKey == key }
    }

    public func bookID(forBook key: String) -> BookID? {
        records.first { $0.bookKey == key }.map { BookID(rawValue: $0.bookID) }
    }

    public func chunks(forBook key: String) -> [BookChunk] {
        records(forBook: key).map { $0.chunk() }
    }

    /// Seeds one corpus book into a database and returns the production
    /// repository, so the ablation queries the same code path the app does.
    @discardableResult
    public func seed(bookKey: String, database: AppDatabase) async throws -> GRDBBookIndexRepository {
        guard let bookID = bookID(forBook: bookKey) else { throw RagCorpusError.unknownBook(bookKey) }
        let books = GRDBBookRepository(database: database)
        try await books.insert(Book(
            id: bookID,
            fingerprint: .init(rawValue: "ragcorpus-\(bookKey)"),
            title: bookKey,
            fileName: "\(bookKey).epub",
            fileSize: 0
        ))
        let index = GRDBBookIndexRepository(database: database)
        try await index.replace(
            chunks: chunks(forBook: bookKey),
            for: bookID,
            version: BookIndexPipeline.currentVersion
        )
        return index
    }
}

public enum RagCorpusError: Error {
    case unknownBook(String)
    case unknownChunk(String)
}

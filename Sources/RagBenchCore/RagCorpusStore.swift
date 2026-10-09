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
        // Idempotent: the builder and the ablation both seed, and a corpus book
        // is identified by its key, so a second call must be a no-op rather
        // than a UNIQUE(fileName) violation.
        if try await books.book(id: bookID) == nil {
            try await books.insert(Book(
                id: bookID,
                fingerprint: .init(rawValue: "ragcorpus-\(bookKey)"),
                title: bookKey,
                fileName: "\(bookKey).epub",
                fileSize: 0
            ))
        }
        let index = GRDBBookIndexRepository(database: database)
        let chunks = chunks(forBook: bookKey)
        // Seeding is idempotent, and not merely for tidiness: `replace(chunks:)`
        // deletes the book's chunk rows, and `bookChunkEmbeddings` cascades off
        // them. Re-seeding after an embedding pass would silently discard every
        // vector, leaving the semantic arm measuring the lexical one.
        if try await index.chunks(for: bookID, version: BookIndexPipeline.currentVersion).isEmpty {
            try await index.replace(
                chunks: chunks,
                for: bookID,
                version: BookIndexPipeline.currentVersion
            )
            // The state production leaves behind once the lexical phase is done.
            // Without it `BookIndexPipeline.embed` no-ops on its state guard.
            try await index.save(job: BookIndexJob(
                bookID: bookID,
                indexVersion: BookIndexPipeline.currentVersion,
                state: .lexicalReady,
                nextResourceOrdinal: (chunks.map(\.resourceOrdinal).max() ?? 0) + 1
            ))
        }
        return index
    }
}

public enum RagCorpusError: Error, CustomStringConvertible {
    case unknownBook(String)
    case unknownChunk(String)
    case embeddingEmpty(String, stored: Int)

    public var description: String {
        switch self {
        case let .unknownBook(key): "no corpus book named \(key)"
        case let .unknownChunk(id): "no corpus chunk with id \(id)"
        case let .embeddingEmpty(key, stored):
            "\(key): embedding pass left \(stored) vectors; the semantic arm would have measured the lexical one"
        }
    }
}

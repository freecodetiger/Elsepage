import AppInfrastructure
import LibraryCore
import Persistence
import RagBenchCore
import RetrievalCore
import XCTest
@testable import ReadLoop

/// Produces `Fixtures/RagCorpus/chunks.jsonl` — the geometry the *production*
/// pipeline actually builds from the corpus EPUBs.
///
/// This step has to run in the Xcode/iOS test bundle, because Readium only
/// builds for iOS. The SPM-side ablation consumes the file instead of
/// re-deriving chunk geometry, which is the whole point: a second
/// implementation of the geometry would drift from the real one silently.
///
/// Nothing here may compute geometry. It persists through `BookIndexPipeline`
/// and reads the rows back out.
@MainActor
final class RagCorpusSnapshotTests: XCTestCase {
    private var corpusRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ReadiumIntegrationTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Fixtures/RagCorpus", isDirectory: true)
    }

    func testSnapshotCorpusGeometry() async throws {
        let epubDirectory = corpusRoot.appendingPathComponent("epub", isDirectory: true)
        let epubs = try FileManager.default
            .contentsOfDirectory(at: epubDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "epub" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(
            epubs.isEmpty,
            "no corpus EPUBs in \(epubDirectory.path) — run Scripts/build-corpus-epub.sh first"
        )

        var records: [RagChunkRecord] = []
        for epub in epubs {
            let bookKey = epub.deletingPathExtension().lastPathComponent
            let size = (try FileManager.default.attributesOfItem(atPath: epub.path)[.size] as? NSNumber)?.int64Value ?? 0
            let database = try AppDatabase.inMemory()
            let books = GRDBBookRepository(database: database)
            let index = GRDBBookIndexRepository(database: database)
            let bookID = RagCorpusBook.bookID(for: bookKey)
            try await books.insert(Book(
                id: bookID,
                fingerprint: .init(rawValue: "ragcorpus-\(bookKey)"),
                title: bookKey,
                fileName: epub.lastPathComponent,
                fileSize: size
            ))

            let publication = try await ReadiumServices().open(epub, allowUserInteraction: false)
            let extractor = ReadiumBookContentExtractor(bookID: bookID, publication: publication)
            try await BookIndexPipeline(extractor: extractor, repository: index).index(bookID: bookID)

            let chunks = try await index.chunks(for: bookID, version: BookIndexPipeline.currentVersion)
            XCTAssertFalse(chunks.isEmpty, "\(bookKey) produced no chunks")
            records.append(contentsOf: chunks
                .sorted { ($0.resourceOrdinal, $0.ordinal) < ($1.resourceOrdinal, $1.ordinal) }
                .map { RagChunkRecord($0, bookKey: bookKey) })
        }

        let destination = corpusRoot.appendingPathComponent("chunks.jsonl")
        try RagCorpusIO.encodeLines(records).write(to: destination, options: .atomic)
        print("RAGCORPUS_SNAPSHOT chunks=\(records.count) path=\(destination.path)")
    }
}

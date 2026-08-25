import AppInfrastructure
import LibraryCore
import Persistence
import RetrievalCore
import XCTest
@testable import ReadLoop

@MainActor
final class ReadiumPublicationIntegrationTests: XCTestCase {
    private var fixture: URL {
        try! XCTUnwrap(Bundle(for: Self.self).url(forResource: "minimal", withExtension: "epub"))
    }

    func testReadiumOpensRealEPUBAndExtractsMetadata() async throws {
        let publication = try await ReadiumServices().open(fixture, allowUserInteraction: false)
        XCTAssertFalse(publication.isRestricted)
        XCTAssertEqual(publication.metadata.title, "ReadLoop Foundation Fixture")
        XCTAssertEqual(publication.metadata.authors.first?.name, "ReadLoop Contributors")
        XCTAssertEqual(publication.readingOrder.count, 1)
    }

    func testReadiumMetadataFeedsFingerprintAndIdempotentImport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = try AppDatabase.inMemory()
        let repository = GRDBBookRepository(database: database)
        let store = try BookFileStore(directory: root.appendingPathComponent("Books", isDirectory: true))
        let readium = ReadiumServices()
        let metadata = try await ReadiumMetadataReader(readium: readium).metadata(at: fixture)
        let importer = BookImporter(repository: repository, files: store)

        guard case .imported(let book) = try await importer.importEPUB(at: fixture, metadata: metadata),
              case .duplicate(let duplicate) = try await importer.importEPUB(at: fixture, metadata: metadata) else {
            XCTFail("Expected imported then duplicate"); return
        }
        XCTAssertEqual(book.id, duplicate.id)
        XCTAssertEqual(book.title, "ReadLoop Foundation Fixture")
        XCTAssertEqual(book.author, "ReadLoop Contributors")
    }

    func testReadiumContentBuildsNavigableLocalFTSIndex() async throws {
        let database = try AppDatabase.inMemory()
        let books = GRDBBookRepository(database: database)
        let index = GRDBBookIndexRepository(database: database)
        let book = Book(fingerprint: .init(rawValue: "readium-index"), title: "Fixture", fileName: "fixture.epub", fileSize: 1)
        try await books.insert(book)
        let publication = try await ReadiumServices().open(fixture, allowUserInteraction: false)
        let extractor = ReadiumBookContentExtractor(bookID: book.id, publication: publication)
        try await BookIndexPipeline(extractor: extractor, repository: index, chunker: .init(targetCharacters: 120, maximumCharacters: 240)).index(bookID: book.id)

        let chunks = try await index.chunks(for: book.id, version: BookIndexPipeline.currentVersion)
        XCTAssertFalse(chunks.isEmpty)
        XCTAssertTrue(chunks.allSatisfy { !$0.startLocator.json.isEmpty && !$0.resourceHref.isEmpty })
        let results = try await index.lexicalSearch(bookID: book.id, query: "reader begins", boundary: .init(resourceOrdinal: .max), limit: 5)
        XCTAssertFalse(results.isEmpty)
    }
}

import AppInfrastructure
import LibraryCore
import Persistence
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
}

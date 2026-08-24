import AppInfrastructure
import Foundation
import LibraryCore
import Observation
import ReaderCore

@MainActor @Observable
final class LibraryModel {
    private let booksRepository: any BookRepository
    let readingRepository: any ReadingRepository
    let files: BookFileStore
    private let importer: BookImporter
    private let metadataReader: ReadiumMetadataReader
    private let readium: ReadiumServices

    private(set) var books: [Book] = []
    private(set) var isImporting = false
    var errorMessage: String?
    var duplicateTitle: String?

    init(books: any BookRepository, reading: any ReadingRepository, files: BookFileStore, metadataReader: ReadiumMetadataReader, readium: ReadiumServices) {
        booksRepository = books; readingRepository = reading; self.files = files
        importer = BookImporter(repository: books, files: files)
        self.metadataReader = metadataReader
        self.readium = readium
    }

    func reload() async {
        do { books = try await booksRepository.allBooks() }
        catch { errorMessage = error.localizedDescription }
    }

    func importBook(_ url: URL) async {
        isImporting = true; defer { isImporting = false }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let stagedURL = try stageCoordinatedCopy(of: url)
            defer { try? FileManager.default.removeItem(at: stagedURL.deletingLastPathComponent()) }
            let metadata = try await metadataReader.metadata(at: stagedURL)
            switch try await importer.importEPUB(at: stagedURL, metadata: metadata) {
            case .imported: await reload()
            case .duplicate(let book): duplicateTitle = book.title
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func readerModel(for book: Book) -> ReaderModel {
        ReaderModel(book: book, fileURL: files.url(for: book.id), repository: readingRepository, books: booksRepository, readium: readium)
    }

    private func stageCoordinatedCopy(of url: URL) throws -> URL {
        var coordinationError: NSError?
        var result: Result<URL, Error>!
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
            do {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let staged = directory.appendingPathComponent(coordinated.lastPathComponent)
                try FileManager.default.copyItem(at: coordinated, to: staged)
                result = .success(staged)
            } catch { result = .failure(error) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }
}

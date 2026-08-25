import AppInfrastructure
import Foundation
import LibraryCore
import Observation
import ReaderCore
import ReaderAgent
import ReadingSessionCore
import ReflectionCore
import UIKit

@MainActor @Observable
final class LibraryModel {
    private let booksRepository: any BookRepository
    let readingRepository: any ReadingRepository
    let reflectionRepository: any ReflectionRepository
    let sessionRepository: any ReadingSessionRepository
    let sessionService: ReadingSessionService
    let files: BookFileStore
    private let importer: BookImporter
    private let metadataReader: ReadiumMetadataReader
    private let readium: ReadiumServices
    let readerAgent: ReaderAgent

    private(set) var books: [Book] = []
    private(set) var readingProgress: [BookID: Double] = [:]
    private(set) var covers: [BookID: UIImage] = [:]
    private(set) var isImporting = false
    private(set) var deletingBookID: BookID?
    var errorMessage: String?
    var duplicateTitle: String?
    var searchQuery = ""
    var sortOrder: LibrarySortOrder = .recentlyOpened

    init(
        books: any BookRepository,
        reading: any ReadingRepository,
        sessions: any ReadingSessionRepository,
        reflections: any ReflectionRepository,
        readerAgent: ReaderAgent,
        files: BookFileStore,
        metadataReader: ReadiumMetadataReader,
        readium: ReadiumServices
    ) {
        booksRepository = books; readingRepository = reading; self.files = files
        reflectionRepository = reflections
        sessionRepository = sessions
        sessionService = ReadingSessionService(repository: sessions)
        self.readerAgent = readerAgent
        importer = BookImporter(repository: books, files: files)
        self.metadataReader = metadataReader
        self.readium = readium
    }

    func reload() async {
        do {
            books = try await booksRepository.allBooks()
            try files.reconcilePendingDeletions(existingBookIDs: books.map(\.id))
            let positions = try await readingRepository.positions(for: books.map(\.id))
            readingProgress = positions.reduce(into: [:]) { result, entry in
                result[entry.key] = entry.value.locator.totalProgression ?? 0
            }
        }
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

    func readerModel(for book: Book, locator: BookLocator? = nil) -> ReaderModel {
        ReaderModel(
            book: book,
            fileURL: files.url(for: book.id),
            repository: readingRepository,
            books: booksRepository,
            sessions: sessionService,
            reflections: reflectionRepository,
            readerAgent: readerAgent,
            requestedLocator: locator,
            readium: readium
        )
    }

    var visibleBooks: [Book] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = books.filter { book in
            guard !query.isEmpty else { return true }
            return book.title.localizedCaseInsensitiveContains(query)
                || (book.author?.localizedCaseInsensitiveContains(query) ?? false)
        }
        return matches.sorted { lhs, rhs in
            switch sortOrder {
            case .recentlyOpened:
                return recentDate(for: lhs) > recentDate(for: rhs)
            case .title:
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            case .author:
                return (lhs.author ?? "").localizedStandardCompare(rhs.author ?? "") == .orderedAscending
            }
        }
    }

    func progress(for book: Book) -> Double? {
        readingProgress[book.id]
    }

    func cover(for book: Book) -> UIImage? {
        covers[book.id]
    }

    func loadCover(for book: Book) async {
        guard covers[book.id] == nil else { return }
        do {
            if let cover = try await metadataReader.cover(at: files.url(for: book.id), fitting: .init(width: 480, height: 720)) {
                covers[book.id] = cover
            }
        } catch is CancellationError {
            return
        } catch {
            // A cover is optional presentation data. Reading/import remains
            // usable when an EPUB omits one or exposes an unreadable image.
        }
    }

    func delete(_ book: Book) async {
        guard deletingBookID == nil else { return }
        deletingBookID = book.id
        defer { deletingBookID = nil }
        do {
            let trashed = try files.stageDeletion(bookID: book.id)
            do {
                try await booksRepository.delete(book.id)
            } catch {
                if let trashed {
                    do { try files.restore(trashed, for: book.id) }
                    catch { errorMessage = "无法恢复 EPUB 文件：\(error.localizedDescription)" }
                }
                throw error
            }
            files.commitDeletion(trashed)
            books.removeAll { $0.id == book.id }
            readingProgress[book.id] = nil
            covers[book.id] = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
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

enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case recentlyOpened
    case title
    case author

    var id: String { rawValue }
    var title: String {
        switch self {
        case .recentlyOpened: "最近阅读"
        case .title: "书名"
        case .author: "作者"
        }
    }
}

private extension LibraryModel {
    func recentDate(for book: Book) -> Date {
        book.lastOpenedAt ?? book.importedAt
    }
}

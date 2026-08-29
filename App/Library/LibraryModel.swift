import AgentRuntime
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
    private let indexCoordinator: BookIndexCoordinator
    let readerAgent: ReaderAgent
    let makePolishService: (@MainActor () async -> TranscriptPolishService?)?

    private(set) var books: [Book] = []
    private(set) var readingProgress: [BookID: Double] = [:]
    /// Card statistics (阅读时长 / 划线 / 想法), loaded once per reload in a
    /// single grouped query — never re-queried while search filters the grid.
    private(set) var bookStats: [BookID: BookLibraryStats] = [:]
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
        makePolishService: (@MainActor () async -> TranscriptPolishService?)? = nil,
        files: BookFileStore,
        metadataReader: ReadiumMetadataReader,
        readium: ReadiumServices,
        indexCoordinator: BookIndexCoordinator
    ) {
        booksRepository = books; readingRepository = reading; self.files = files
        reflectionRepository = reflections
        sessionRepository = sessions
        sessionService = ReadingSessionService(repository: sessions)
        self.readerAgent = readerAgent
        self.makePolishService = makePolishService
        importer = BookImporter(repository: books, files: files)
        self.metadataReader = metadataReader
        self.readium = readium
        self.indexCoordinator = indexCoordinator
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
        // Card statistics are optional presentation data (like covers): a
        // failed stats load keeps the previous values instead of failing the
        // whole reload.
        if let stats = try? await booksRepository.libraryStats(for: books.map(\.id)) {
            bookStats = stats
        }
    }

    /// Imports an EPUB through the full pipeline (staging, metadata, dedupe,
    /// indexing). Returns the book that is now in the library — the freshly
    /// imported one, or the duplicate already stored (with `duplicateTitle`
    /// set); nil when the import failed (`errorMessage` set). Onboarding reuses
    /// this to confirm the first import by title.
    @discardableResult
    func importBook(_ url: URL) async -> Book? {
        isImporting = true; defer { isImporting = false }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let stagedURL = try stageCoordinatedCopy(of: url)
            defer { try? FileManager.default.removeItem(at: stagedURL.deletingLastPathComponent()) }
            let metadata = try await metadataReader.metadata(at: stagedURL)
            switch try await importer.importEPUB(at: stagedURL, metadata: metadata) {
            case .imported(let book):
                await reload()
                indexCoordinator.enqueue(book)
                // 导入完成 (PRD §10.4) — only for a genuinely new book, never for
                // the duplicate path.
                Haptics.importCompleted()
                return book
            case .duplicate(let book):
                duplicateTitle = book.title
                return book
            }
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func resumeBookIndexing() async { await indexCoordinator.resume(books) }

    func readerModel(for book: Book, locator: BookLocator? = nil) -> ReaderModel {
        ReaderModel(
            book: book,
            fileURL: files.url(for: book.id),
            repository: readingRepository,
            books: booksRepository,
            sessions: sessionService,
            reflections: reflectionRepository,
            readerAgent: readerAgent,
            makePolishService: makePolishService,
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

    /// Quiet per-card metadata line ("读过 24 分钟 · 划线 3 · 想法 2"), or nil
    /// when nothing has accumulated yet so fresh books stay uncluttered.
    func statsLine(for book: Book) -> String? {
        bookStats[book.id]?.metadataDescription
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
            bookStats[book.id] = nil
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

import AgentRuntime
import AppInfrastructure
import Foundation
import LibraryCore
import Observation
import ReaderCore
import ReaderAgent
import ReadingSessionCore
import ReflectionCore
import RetrievalCore
import UIKit

@MainActor @Observable
final class LibraryModel {
    private let booksRepository: any BookRepository
    let readingRepository: any ReadingRepository
    let reflectionRepository: any ReflectionRepository
    let sessionRepository: any ReadingSessionRepository
    let sessionService: ReadingSessionService
    let files: BookFileStore
    private let audioStore: AudioFileStore
    private let importer: BookImporter
    private let metadataReader: ReadiumMetadataReader
    private let readium: ReadiumServices
    private let indexCoordinator: BookIndexCoordinator
    private let bookIndex: any BookIndexRepository
    let readerAgent: ReaderAgent
    let readerHelpService: ReaderHelpService
    let textAnnotations: any TextAnnotationRepository
    let makePolishService: (@MainActor () async -> TranscriptPolishService?)?

    private(set) var books: [Book] = []
    private(set) var readingProgress: [BookID: Double] = [:]
    /// Card statistics (阅读时长 / 划线 / 想法), loaded once per reload in a
    /// single grouped query — never re-queried while search filters the grid.
    private(set) var bookStats: [BookID: BookLibraryStats] = [:]
    private(set) var covers: [BookID: UIImage] = [:]
    /// Current chapter title per book, resolved lazily from the persisted
    /// index. Presentation data like covers: absent until asked for.
    private(set) var chapterTitles: [BookID: String] = [:]
    private(set) var isImporting = false
    private(set) var deletingBookID: BookID?
    var errorMessage: String?
    var duplicateTitle: String?
    var searchQuery = ""
    var sortOrder: LibrarySortOrder = .recentlyOpened {
        didSet {
            UserDefaults.standard.set(sortOrder.rawValue, forKey: Self.sortOrderDefaultsKey)
            guard sortOrder == .manual, oldValue != .manual else { return }
            adoptCurrentOrderAsManual(previousSort: oldValue)
        }
    }
    /// Manual order is only meaningful if the shelf reopens in the manual
    /// sort; otherwise the persisted order would be invisible after relaunch.
    private static let sortOrderDefaultsKey = "library.sortOrder"
    /// Book waiting for the removal confirmation. Dropping a dragged cover on
    /// the shell's delete target sets it; the shelf presents the alert.
    var pendingDeletion: Book?
    /// True while a cover is lifted for reordering. The shell watches it to
    /// turn the compose button into the delete target.
    var isDraggingBook = false
    /// Where the shell draws that target, in window coordinates (the same
    /// space as SwiftUI's `.global`). `.zero` until the bar lays out.
    var trashZoneFrame: CGRect = .zero

    init(
        books: any BookRepository,
        reading: any ReadingRepository,
        sessions: any ReadingSessionRepository,
        reflections: any ReflectionRepository,
        readerAgent: ReaderAgent,
        readerHelpService: ReaderHelpService,
        textAnnotations: any TextAnnotationRepository,
        makePolishService: (@MainActor () async -> TranscriptPolishService?)? = nil,
        files: BookFileStore,
        metadataReader: ReadiumMetadataReader,
        readium: ReadiumServices,
        indexCoordinator: BookIndexCoordinator,
        bookIndex: any BookIndexRepository,
        audioStore: AudioFileStore = .live()
    ) {
        booksRepository = books; readingRepository = reading; self.files = files
        self.audioStore = audioStore
        reflectionRepository = reflections
        sessionRepository = sessions
        sessionService = ReadingSessionService(repository: sessions)
        self.readerAgent = readerAgent
        self.readerHelpService = readerHelpService
        self.textAnnotations = textAnnotations
        self.makePolishService = makePolishService
        importer = BookImporter(repository: books, files: files)
        self.metadataReader = metadataReader
        self.readium = readium
        self.indexCoordinator = indexCoordinator
        self.bookIndex = bookIndex
        if let raw = UserDefaults.standard.string(forKey: Self.sortOrderDefaultsKey),
           let stored = LibrarySortOrder(rawValue: raw) {
            sortOrder = stored
        }
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
        appendBooksMissingManualOrder()
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
            readerHelpService: readerHelpService,
            textAnnotations: textAnnotations,
            makePolishService: makePolishService,
            requestedLocator: locator,
            readium: readium
        )
    }

    var currentBook: Book? {
        books.max { lhs, rhs in
            let lhsDate = lhs.lastOpenedAt ?? lhs.importedAt
            let rhsDate = rhs.lastOpenedAt ?? rhs.importedAt
            return lhsDate < rhsDate
        }
    }

    var visibleBooks: [Book] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = books.filter { book in
            guard !query.isEmpty else { return true }
            return book.title.localizedCaseInsensitiveContains(query)
                || (book.author?.localizedCaseInsensitiveContains(query) ?? false)
        }
        return sorted(matches, by: sortOrder)
    }

    private func sorted(_ books: [Book], by order: LibrarySortOrder) -> [Book] {
        books.sorted { lhs, rhs in
            switch order {
            case .recentlyOpened:
                return recentDate(for: lhs) > recentDate(for: rhs)
            case .title:
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            case .author:
                return (lhs.author ?? "").localizedStandardCompare(rhs.author ?? "") == .orderedAscending
            case .manual:
                let lhsOrder = lhs.manualOrder ?? Int.max
                let rhsOrder = rhs.manualOrder ?? Int.max
                if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                return recentDate(for: lhs) > recentDate(for: rhs)
            }
        }
    }

    /// Swaps two shelf positions. The rest of the grid does not shift: the
    /// reader asked for an exchange, not an insert-and-reflow.
    func swapBooks(_ draggedID: BookID, with targetID: BookID) {
        guard draggedID != targetID else { return }
        if sortOrder != .manual { sortOrder = .manual }

        guard let draggedIndex = books.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = books.firstIndex(where: { $0.id == targetID }),
              let draggedOrder = books[draggedIndex].manualOrder,
              let targetOrder = books[targetIndex].manualOrder,
              draggedOrder != targetOrder
        else { return }

        books[draggedIndex].manualOrder = targetOrder
        books[targetIndex].manualOrder = draggedOrder
        Haptics.bookPulled()

        let orders = [draggedID: targetOrder, targetID: draggedOrder]
        Task {
            do {
                try await booksRepository.updateManualOrder(orders)
            } catch {
                errorMessage = error.localizedDescription
                await reload()
            }
        }
    }

    /// One-step move behind the cover's accessibility actions. Dragging is not
    /// available to VoiceOver, so this is the only reorder path there.
    func moveBook(_ id: BookID, by offset: Int) {
        let ordered = sorted(books, by: sortOrder)
        guard let index = ordered.firstIndex(where: { $0.id == id }),
              ordered.indices.contains(index + offset) else { return }
        swapBooks(id, with: ordered[index + offset].id)
    }

    /// Switching to the manual sort keeps exactly what the reader is looking
    /// at, then freezes it: every visible book gets an index in that order.
    private func adoptCurrentOrderAsManual(previousSort: LibrarySortOrder) {
        let ordered = sorted(books, by: previousSort)
        var orders: [BookID: Int] = [:]
        for (index, book) in ordered.enumerated() {
            guard let position = books.firstIndex(where: { $0.id == book.id }) else { continue }
            books[position].manualOrder = index
            orders[book.id] = index
        }
        persistManualOrder(orders)
    }

    /// A book imported while the manual sort is active has no index yet; put
    /// it at the end instead of letting it jump into the middle.
    private func appendBooksMissingManualOrder() {
        guard sortOrder == .manual else { return }
        var next = (books.compactMap(\.manualOrder).max() ?? -1) + 1
        var orders: [BookID: Int] = [:]
        for index in books.indices where books[index].manualOrder == nil {
            books[index].manualOrder = next
            orders[books[index].id] = next
            next += 1
        }
        persistManualOrder(orders)
    }

    private func persistManualOrder(_ orders: [BookID: Int]) {
        guard !orders.isEmpty else { return }
        Task {
            do {
                try await booksRepository.updateManualOrder(orders)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func progress(for book: Book) -> Double? {
        readingProgress[book.id]
    }

    #if DEBUG
    /// QA fixture, opt-in with `-seed-library`: imports the bundled sample
    /// EPUBs so the grid has enough books to exercise drag-swap. Skips when
    /// the shelf already has books, so it never duplicates on relaunch.
    func importDebugBooksIfNeeded() async {
        guard books.count < 3 else { return }
        for index in 1...5 {
            guard let url = Bundle.main.url(forResource: "debug-book-\(index)", withExtension: "epub") else { continue }
            _ = await importBook(url)
        }
    }
    #endif

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

    /// The chapter the saved position sits in, read from the persisted index —
    /// the shelf never opens the EPUB for this. Books that are not indexed yet
    /// (or have no usable TOC) leave the shelf's chapter line empty.
    func loadChapterTitle(for book: Book) async {
        guard chapterTitles[book.id] == nil else { return }
        do {
            guard let position = try await readingRepository.positions(for: [book.id])[book.id] else { return }
            let chapters = try await bookIndex.chapters(for: book.id, from: position.locator, to: nil)
            chapterTitles[book.id] = ChapterTitle.readingChapter(in: chapters.map(\.title))
        } catch {
            // Optional presentation data; a missing chapter must not surface an
            // error over the shelf. Same policy as `loadCover`.
        }
    }

    func delete(_ book: Book) async {
        guard deletingBookID == nil else { return }
        deletingBookID = book.id
        defer { deletingBookID = nil }
        do {
            let audioNames = try await reflectionRepository.audioFileNames(for: book.id)
            for audioName in audioNames {
                if let metadata = try? await audioStore.metadata(for: audioName) {
                    try? await AudioWaveformStore.shared.remove(cacheKey: metadata.checksum)
                }
            }
            let stagedAudio = try audioStore.stageDeletion(fileNames: audioNames)
            let trashed: TrashedBookFile?
            do {
                trashed = try files.stageDeletion(bookID: book.id)
            } catch {
                audioStore.restoreDeletion(stagedAudio)
                throw error
            }
            do {
                try await booksRepository.delete(book.id)
            } catch {
                if let trashed {
                    do { try files.restore(trashed, for: book.id) }
                    catch { errorMessage = "无法恢复 EPUB 文件：\(error.localizedDescription)" }
                }
                audioStore.restoreDeletion(stagedAudio)
                throw error
            }
            files.commitDeletion(trashed)
            audioStore.commitDeletion(stagedAudio)
            readium.invalidate(files.url(for: book.id))
            books.removeAll { $0.id == book.id }
            readingProgress[book.id] = nil
            bookStats[book.id] = nil
            covers[book.id] = nil
            chapterTitles[book.id] = nil
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
    case manual

    var id: String { rawValue }
    var title: String {
        switch self {
        case .recentlyOpened: "最近阅读"
        case .title: "书名"
        case .author: "作者"
        case .manual: "自定义"
        }
    }
}

private extension LibraryModel {
    func recentDate(for book: Book) -> Date {
        book.lastOpenedAt ?? book.importedAt
    }
}

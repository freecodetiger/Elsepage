import Foundation
import LibraryCore
import Observation
import ReaderCore

@MainActor @Observable
final class ReaderModel {
    let book: Book
    let fileURL: URL
    let repository: any ReadingRepository
    private let books: any BookRepository
    let readium: ReadiumServices
    var initialLocatorJSON: Data?
    var errorMessage: String?
    var preferences: ReaderPreferences = .default
    var highlights: [Highlight] = []
    var notes: [Note] = []
    var searchResults: [ReaderSearchResult] = []
    var isSearching = false
    var chapters: [ReaderChapter] = []
    var currentChapterTitle: String?
    var currentChapterID: String?
    var progress: Double = 0
    var showsControls = true
    var jumpTargetJSON: Data?
    var selectedHighlightID: UUID?
    private(set) var isPrepared = false
    @ObservationIgnored var searchHandler: (@MainActor (String) async throws -> [ReaderSearchResult])?
    @ObservationIgnored private var positionSaveTask: Task<Void, Never>?
    @ObservationIgnored private var pendingPosition: ReadingPosition?
    @ObservationIgnored private var searchGeneration = UUID()

    init(book: Book, fileURL: URL, repository: any ReadingRepository, books: any BookRepository, readium: ReadiumServices) {
        self.book = book; self.fileURL = fileURL; self.repository = repository; self.books = books
        self.readium = readium
    }
    func prepare() async {
        defer { isPrepared = true }
        do {
            let position = try await repository.position(for: book.id)
            initialLocatorJSON = position?.locator.json
            progress = position?.locator.totalProgression ?? 0
            preferences = try await repository.preferences(for: book.id)
            highlights = try await repository.highlights(for: book.id)
            notes = try await repository.notes(for: book.id)
            try await books.markOpened(book.id, at: Date())
        } catch { errorMessage = error.localizedDescription }
    }
    func save(locator: BookLocator) {
        progress = locator.totalProgression ?? progress
        let resource = locator.href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? locator.href
        let currentChapter = chapters.last { chapter in
            (chapter.href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? chapter.href) == resource
        }
        currentChapterTitle = currentChapter?.title ?? currentChapterTitle
        currentChapterID = currentChapter?.id ?? currentChapterID
        pendingPosition = .init(bookID: book.id, locator: locator)
        positionSaveTask?.cancel()
        positionSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
            await self?.flushPosition()
        }
    }
    func saveHighlight(locator: BookLocator) {
        let highlight = Highlight(bookID: book.id, locator: locator)
        highlights.append(highlight)
        Task {
            do { try await repository.save(highlight: highlight) }
            catch {
                highlights.removeAll { $0.id == highlight.id }
                errorMessage = error.localizedDescription
            }
        }
    }
    func saveNote(locator: BookLocator, body: String) {
        let highlight = Highlight(bookID: book.id, locator: locator)
        let note = Note(bookID: book.id, highlightID: highlight.id, locator: locator, body: body)
        highlights.append(highlight)
        notes.append(note)
        Task {
            do { try await repository.save(highlight: highlight, note: note) }
            catch {
                highlights.removeAll { $0.id == highlight.id }
                notes.removeAll { $0.id == note.id }
                errorMessage = error.localizedDescription
            }
        }
    }
    func update(note: Note, body: String) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let original = notes[index]
        var updated = original
        updated.body = body
        updated.updatedAt = Date()
        notes[index] = updated
        Task {
            do { try await repository.save(note: updated) }
            catch {
                if let current = notes.firstIndex(where: { $0.id == original.id }) { notes[current] = original }
                errorMessage = error.localizedDescription
            }
        }
    }
    func delete(note: Note) {
        notes.removeAll { $0.id == note.id }
        Task {
            do { try await repository.deleteNote(id: note.id) }
            catch { notes.append(note); notes.sort { $0.createdAt < $1.createdAt }; errorMessage = error.localizedDescription }
        }
    }
    func delete(highlight: Highlight) {
        highlights.removeAll { $0.id == highlight.id }
        for index in notes.indices where notes[index].highlightID == highlight.id {
            let note = notes[index]
            notes[index] = Note(id: note.id, bookID: note.bookID, locator: note.locator, body: note.body, createdAt: note.createdAt, updatedAt: note.updatedAt)
        }
        Task {
            do { try await repository.deleteHighlight(id: highlight.id) }
            catch { await reloadAnnotations(after: error) }
        }
    }
    func jump(to locator: BookLocator) { jumpTargetJSON = locator.json }
    func search(_ query: String) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let searchHandler else { searchResults = []; return }
        let generation = UUID()
        searchGeneration = generation
        isSearching = true
        do {
            let results = try await searchHandler(query)
            guard searchGeneration == generation else { return }
            searchResults = results
            isSearching = false
        } catch {
            guard searchGeneration == generation else { return }
            isSearching = false
            errorMessage = error.localizedDescription
        }
    }
    func flushPosition() async {
        positionSaveTask?.cancel()
        positionSaveTask = nil
        guard let position = pendingPosition else { return }
        pendingPosition = nil
        do { try await repository.save(position: position) }
        catch { pendingPosition = position; errorMessage = error.localizedDescription }
    }
    func savePreferences() {
        let value = preferences
        Task { await reportPersistenceError { try await self.repository.save(preferences: value, for: self.book.id) } }
    }
    func jump(to chapter: ReaderChapter) {
        jumpTargetJSON = chapter.locatorJSON
        currentChapterTitle = chapter.title
        currentChapterID = chapter.id
    }
    func toggleControls() {
        showsControls.toggle()
    }
    private func reportPersistenceError(_ operation: @escaping @Sendable () async throws -> Void) async {
        do { try await operation() }
        catch { errorMessage = error.localizedDescription }
    }
    private func reloadAnnotations(after error: Error) async {
        do {
            highlights = try await repository.highlights(for: book.id)
            notes = try await repository.notes(for: book.id)
        } catch {}
        errorMessage = error.localizedDescription
    }
}

struct ReaderChapter: Identifiable, Hashable {
    let id: String
    let title: String
    let depth: Int
    let href: String
    let locatorJSON: Data
}

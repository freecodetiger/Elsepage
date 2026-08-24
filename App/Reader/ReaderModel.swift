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
    @ObservationIgnored private var positionState = LatestValueState<ReadingPosition>()
    @ObservationIgnored private var searchState = LatestRequestState()
    @ObservationIgnored private var noteSaveTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var noteSaveGenerations: [UUID: UInt64] = [:]

    init(book: Book, fileURL: URL, repository: any ReadingRepository, books: any BookRepository, readium: ReadiumServices) {
        self.book = book; self.fileURL = fileURL; self.repository = repository; self.books = books
        self.readium = readium
    }
    func prepare() async {
        guard !isPrepared else { return }
        do {
            let position = try await repository.position(for: book.id)
            try Task.checkCancellation()
            initialLocatorJSON = position?.locator.json
            progress = position?.locator.totalProgression ?? 0
            preferences = try await repository.preferences(for: book.id)
            try Task.checkCancellation()
            highlights = try await repository.highlights(for: book.id)
            notes = try await repository.notes(for: book.id)
            try Task.checkCancellation()
            try await books.markOpened(book.id, at: Date())
            try Task.checkCancellation()
            isPrepared = true
        } catch is CancellationError {
            return
        } catch {
            isPrepared = true
            errorMessage = error.localizedDescription
        }
    }
    func save(locator: BookLocator) {
        progress = locator.totalProgression ?? progress
        let currentChapter = chapter(for: locator)
        currentChapterTitle = currentChapter?.title ?? currentChapterTitle
        currentChapterID = currentChapter?.id ?? currentChapterID
        positionState.submit(.init(bookID: book.id, locator: locator))
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
        let generation = (noteSaveGenerations[note.id] ?? 0) &+ 1
        noteSaveGenerations[note.id] = generation
        let previous = noteSaveTasks[note.id]
        noteSaveTasks[note.id] = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do { try await self.repository.save(note: updated) }
            catch {
                if self.noteSaveGenerations[note.id] == generation,
                   let current = self.notes.firstIndex(where: { $0.id == original.id }) {
                    self.notes[current] = original
                }
                self.errorMessage = error.localizedDescription
            }
            if self.noteSaveGenerations[note.id] == generation {
                self.noteSaveTasks[note.id] = nil
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
        guard !query.isEmpty, let searchHandler else {
            searchState.invalidate()
            searchResults = []
            isSearching = false
            return
        }
        let token = searchState.begin()
        isSearching = searchState.isLoading
        do {
            let results = try await searchHandler(query)
            guard searchState.finish(token) else { return }
            searchResults = results
            isSearching = searchState.isLoading
        } catch is CancellationError {
            guard searchState.finish(token) else { return }
            isSearching = searchState.isLoading
        } catch {
            guard searchState.finish(token) else { return }
            isSearching = searchState.isLoading
            errorMessage = error.localizedDescription
        }
    }
    func flushPosition() async {
        positionSaveTask?.cancel()
        positionSaveTask = nil
        while let target = positionState.beginWrite() {
            do {
                try await repository.save(position: target.value)
                positionState.didWrite(target, succeeded: true)
            } catch is CancellationError {
                positionState.didWrite(target, succeeded: false)
                return
            } catch {
                positionState.didWrite(target, succeeded: false)
                errorMessage = error.localizedDescription
                return
            }
        }
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
        catch is CancellationError { return }
        catch { errorMessage = error.localizedDescription }
    }
    private func reloadAnnotations(after error: Error) async {
        do {
            highlights = try await repository.highlights(for: book.id)
            notes = try await repository.notes(for: book.id)
        } catch {}
        errorMessage = error.localizedDescription
    }
    private func chapter(for locator: BookLocator) -> ReaderChapter? {
        let resource = locator.href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? locator.href
        let candidates = chapters.filter { chapter in
            (chapter.href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? chapter.href) == resource
        }
        guard !candidates.isEmpty else { return nil }
        if locator.href.contains("#"), let exact = candidates.first(where: { $0.href == locator.href }) {
            return exact
        }
        if let progression = locator.progression {
            let positioned = candidates.compactMap { chapter in chapter.progression.map { (chapter, $0) } }
            if let closest = positioned.filter({ $0.1 <= progression }).max(by: { $0.1 < $1.1 }) {
                return closest.0
            }
        }
        if let currentChapterID, let current = candidates.first(where: { $0.id == currentChapterID }) {
            return current
        }
        return candidates.first
    }
}

struct ReaderChapter: Identifiable, Hashable {
    let id: String
    let title: String
    let depth: Int
    let href: String
    let locatorJSON: Data
    let progression: Double?
}

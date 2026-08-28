import AgentRuntime
import Foundation
import LibraryCore
import Observation
import ReaderCore
import ReaderAgent
import ReadingSessionCore
import ReflectionCore

enum ReaderSelectionIntent: Equatable {
    case highlight
    case note
}

struct PendingReaderSelection: Equatable {
    let locator: BookLocator
    let intent: ReaderSelectionIntent
}

@MainActor @Observable
final class ReaderModel {
    let book: Book
    let fileURL: URL
    let repository: any ReadingRepository
    private let books: any BookRepository
    let reflectionRepository: any ReflectionRepository
    let readerAgent: ReaderAgent
    let makePolishService: (@MainActor () async -> TranscriptPolishService?)?
    /// Injected by ReaderScreen so reflection models built here can report
    /// achievement events (unlock badges are App-layer, not part of ReaderAgent).
    var achievements: AchievementModel?
    private let sessions: ReadingSessionService
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
    var shouldStartNoteEditing = false
    var pendingSelection: PendingReaderSelection?
    var contextReflection: SessionReflectionModel?
    private(set) var currentLocator: BookLocator?
    private(set) var canNavigateBack = false
    private(set) var activeSession: ReadingSession?
    private(set) var isPrepared = false
    @ObservationIgnored var searchHandler: (@MainActor (String) async throws -> [ReaderSearchResult])?
    @ObservationIgnored private var positionSaveTask: Task<Void, Never>?
    @ObservationIgnored private var positionState = LatestValueState<ReadingPosition>()
    @ObservationIgnored private var preferenceSaveTask: Task<Void, Never>?
    @ObservationIgnored private var preferenceState = LatestValueState<ReaderPreferences>()
    @ObservationIgnored private var searchState = LatestRequestState()
    @ObservationIgnored private var locatorHistory = LocatorHistory()
    @ObservationIgnored private var noteSaveTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var noteSaveGenerations: [UUID: UInt64] = [:]
    @ObservationIgnored var onSelectionFinished: (() -> Void)?

    init(
        book: Book,
        fileURL: URL,
        repository: any ReadingRepository,
        books: any BookRepository,
        sessions: ReadingSessionService,
        reflections: any ReflectionRepository,
        readerAgent: ReaderAgent,
        makePolishService: (@MainActor () async -> TranscriptPolishService?)? = nil,
        requestedLocator: BookLocator? = nil,
        readium: ReadiumServices
    ) {
        self.book = book; self.fileURL = fileURL; self.repository = repository; self.books = books
        self.sessions = sessions; reflectionRepository = reflections
        self.readerAgent = readerAgent
        self.makePolishService = makePolishService
        self.readium = readium
        if let requestedLocator {
            initialLocatorJSON = requestedLocator.json
            currentLocator = requestedLocator
            progress = requestedLocator.totalProgression ?? 0
        }
    }
    func prepare() async {
        guard !isPrepared else { return }
        do {
            let position = try await repository.position(for: book.id)
            try Task.checkCancellation()
            if initialLocatorJSON == nil {
                initialLocatorJSON = position?.locator.json
                currentLocator = position?.locator
                progress = position?.locator.totalProgression ?? 0
            }
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
        currentLocator = locator
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
        if let activeSession, activeSession.endedAt != nil,
           let end = activeSession.endLocator,
           !end.identifiesSameAnchor(as: locator) {
            self.activeSession = nil
        }
        if activeSession == nil {
            Task { [weak self] in await self?.startSessionIfNeeded(at: locator) }
        }
    }
    @discardableResult
    func saveHighlight(locator: BookLocator, color: HighlightColor) -> Highlight? {
        if let existing = highlights.first(where: { $0.locator.identifiesSameAnchor(as: locator) }) {
            return existing
        }
        let highlight = Highlight(bookID: book.id, locator: locator, color: color)
        highlights.append(highlight)
        Task {
            do { try await repository.save(highlight: highlight) }
            catch {
                highlights.removeAll { $0.id == highlight.id }
                errorMessage = error.localizedDescription
            }
        }
        return highlight
    }

    func beginSelection(at locator: BookLocator, intent: ReaderSelectionIntent) {
        pendingSelection = .init(locator: locator, intent: intent)
        showsControls = false
    }

    func completePendingSelection(with color: HighlightColor) {
        guard let pendingSelection else { return }
        self.pendingSelection = nil
        preferences.lastUsedHighlightColor = color
        savePreferences()
        let highlight = saveHighlight(locator: pendingSelection.locator, color: color)
        onSelectionFinished?()
        guard let highlight else { return }
        selectHighlight(highlight.id, startNoteEditing: pendingSelection.intent == .note)
    }

    func cancelPendingSelection() {
        guard pendingSelection != nil else { return }
        pendingSelection = nil
        onSelectionFinished?()
    }

    func selectHighlight(_ id: UUID, startNoteEditing: Bool = false) {
        guard highlights.contains(where: { $0.id == id }) else { return }
        selectedHighlightID = id
        shouldStartNoteEditing = startNoteEditing
        showsControls = false
    }

    func update(highlight: Highlight, color: HighlightColor) {
        guard let index = highlights.firstIndex(where: { $0.id == highlight.id }) else { return }
        var updated = highlight
        updated.color = color
        highlights[index] = updated
        Task {
            do { try await repository.save(highlight: updated) }
            catch {
                if let currentIndex = self.highlights.firstIndex(where: { $0.id == highlight.id }) {
                    self.highlights[currentIndex] = highlight
                }
                self.errorMessage = error.localizedDescription
            }
        }
    }
    func saveNote(locator: BookLocator, body: String) {
        if let highlight = highlights.first(where: { $0.locator.identifiesSameAnchor(as: locator) }) {
            saveNote(for: highlight, body: body)
            return
        }
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
    func saveNote(for highlight: Highlight, body: String) {
        guard !notes.contains(where: { $0.highlightID == highlight.id }) else { return }
        let note = Note(bookID: book.id, highlightID: highlight.id, locator: highlight.locator, body: body)
        notes.append(note)
        Task {
            do { try await repository.save(note: note) }
            catch {
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
        if selectedHighlightID == highlight.id { selectedHighlightID = nil }
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

    func clearSelectedHighlight() {
        selectedHighlightID = nil
        shouldStartNoteEditing = false
    }
    func jump(to locator: BookLocator) {
        if let currentLocator, !currentLocator.identifiesSameAnchor(as: locator) {
            locatorHistory.record(currentLocator)
            canNavigateBack = locatorHistory.canGoBack
        }
        jumpTargetJSON = locator.json
        showsControls = false
    }

    func navigateBack() {
        guard let locator = locatorHistory.pop() else { return }
        canNavigateBack = locatorHistory.canGoBack
        jumpTargetJSON = locator.json
        showsControls = false
    }
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
        preferenceState.submit(preferences)
        preferenceSaveTask?.cancel()
        preferenceSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.flushPreferences()
        }
    }
    func flushPreferences() async {
        preferenceSaveTask?.cancel()
        preferenceSaveTask = nil
        while let target = preferenceState.beginWrite() {
            do {
                try await repository.save(preferences: target.value, for: book.id)
                preferenceState.didWrite(target, succeeded: true)
            } catch is CancellationError {
                preferenceState.didWrite(target, succeeded: false)
                return
            } catch {
                preferenceState.didWrite(target, succeeded: false)
                errorMessage = error.localizedDescription
                return
            }
        }
    }
    /// Highlights created within a session's window. Used for the session
    /// highlight count and for linking highlight IDs into the Reflection/Journal.
    func highlights(in session: ReadingSession) -> [Highlight] {
        highlights.filter { $0.createdAt >= session.startedAt }
    }

    func jump(to chapter: ReaderChapter) {
        if let locator = try? BookLocator(
            json: chapter.locatorJSON,
            href: chapter.href,
            progression: chapter.progression
        ) {
            jump(to: locator)
        } else {
            jumpTargetJSON = chapter.locatorJSON
        }
        currentChapterTitle = chapter.title
        currentChapterID = chapter.id
    }
    func toggleControls() {
        showsControls.toggle()
    }
    func hideControls() { showsControls = false }
    func endReadingSession() async -> SessionEndingSummary? {
        guard let locator = currentLocator else { return nil }
        do {
            await flushPosition()
            let session: ReadingSession
            if let activeSession {
                session = activeSession
            } else {
                session = try await sessions.start(bookID: book.id, at: locator)
                activeSession = session
            }
            let completed = try await sessions.end(
                id: session.id,
                at: locator,
                highlightCount: highlights(in: session).count,
                noteCount: notes.filter { $0.createdAt >= session.startedAt }.count
            )
            activeSession = completed
            return SessionEndingSummary(session: completed)
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func reflect(on locator: BookLocator) async {
        do {
            let session: ReadingSession
            if let activeSession, activeSession.endedAt == nil {
                session = activeSession
            } else {
                session = try await sessions.start(bookID: book.id, at: locator)
                activeSession = session
            }
            contextReflection = SessionReflectionModel(
                book: book,
                summary: SessionEndingSummary(session: session),
                locator: locator,
                linkedHighlightIDs: highlights(in: session).map(\.id),
                reflectionRepository: reflectionRepository,
                readerAgent: readerAgent,
                makePolishService: makePolishService,
                achievements: achievements
            )
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startSessionIfNeeded(at locator: BookLocator) async {
        guard activeSession == nil else { return }
        do {
            activeSession = try await sessions.start(bookID: book.id, at: locator)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
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

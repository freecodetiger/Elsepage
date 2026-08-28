import AgentRuntime
import CoreGraphics
import Foundation
import LibraryCore
import Observation
import ReaderCore
import ReaderAgent
import ReadingSessionCore
import ReflectionCore
import UIKit

/// A live text selection captured from the navigator, plus its on-screen
/// frame in navigator (full-screen) coordinates. The selection toolbar is
/// visible exactly while a context is set.
struct ReaderSelectionContext: Equatable {
    let locator: BookLocator
    let text: String
    let frame: CGRect?
}

/// The single in-place annotation surface. Either the toolbar for a fresh
/// selection or the menu of an existing highlight — never both at once.
enum ReaderAnnotationMenu: Equatable {
    case selection(ReaderSelectionContext)
    case highlight(id: UUID, anchor: CGRect?)
}

enum ReaderNoteEditorTarget: Hashable {
    case highlight(UUID)
    case note(UUID)
}

/// One note-editor presentation. Carries a fresh id per request so the
/// item-based sheet always re-presents, even for the same note opened twice
/// in a row.
struct ReaderNoteEditorRequest: Identifiable, Equatable {
    let id = UUID()
    let target: ReaderNoteEditorTarget
}

/// Short-lived, non-blocking feedback pill. The delete kinds carry the exact
/// state needed to undo, so nothing is lost while the pill is visible.
struct ReaderTransientNotice: Equatable, Identifiable {
    enum Kind: Equatable {
        case copied
        case deletedHighlight(Highlight, notes: [Note])
        case deletedNote(Note)
    }

    let id = UUID()
    let kind: Kind
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
    var annotationMenu: ReaderAnnotationMenu?
    var noteEditorRequest: ReaderNoteEditorRequest?
    var transientNotice: ReaderTransientNotice?
    private var pendingHighlightAfterJumpID: UUID?
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
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
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
        clearTransientAnnotationUI()
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
        if let pendingHighlightAfterJumpID,
           let highlight = highlights.first(where: { $0.id == pendingHighlightAfterJumpID }),
           highlight.locator.identifiesSameAnchor(as: locator) {
            self.pendingHighlightAfterJumpID = nil
            showHighlightMenu(for: highlight.id, anchor: nil)
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

    // MARK: Selection toolbar
    //
    // Invariant: the custom selection toolbar is visible exactly while a
    // selection exists in the navigator. Opening it replaces any highlight
    // menu; acting on it closes it and clears the navigator selection.

    func showSelectionMenu(locator: BookLocator, text: String, frame: CGRect?) {
        annotationMenu = .selection(.init(locator: locator, text: text, frame: frame))
        showsControls = false
    }

    func dismissSelectionMenu() {
        guard case .selection = annotationMenu else { return }
        annotationMenu = nil
        onSelectionFinished?()
    }

    func createHighlightFromSelection(with color: HighlightColor) {
        guard case .selection(let context) = annotationMenu else { return }
        annotationMenu = nil
        onSelectionFinished?()
        preferences.lastUsedHighlightColor = color
        savePreferences()
        if let existing = highlights.first(where: { $0.locator.identifiesSameAnchor(as: context.locator) }) {
            update(highlight: existing, color: color)
            return
        }
        saveHighlight(locator: context.locator, color: color)
        AnnotationHaptics.highlightCreated()
    }

    func beginNoteFromSelection() {
        guard case .selection(let context) = annotationMenu else { return }
        annotationMenu = nil
        onSelectionFinished?()
        guard let highlight = saveHighlight(locator: context.locator, color: preferences.lastUsedHighlightColor) else { return }
        openNoteEditor(.highlight(highlight.id))
    }

    /// Opens the note editor for a highlight's note or a standalone note.
    func openNoteEditor(_ target: ReaderNoteEditorTarget) {
        noteEditorRequest = ReaderNoteEditorRequest(target: target)
    }

    func copySelection() {
        guard case .selection(let context) = annotationMenu else { return }
        UIPasteboard.general.string = context.text
        annotationMenu = nil
        onSelectionFinished?()
        showNotice(.copied)
    }

    func reflectOnSelection() {
        guard case .selection(let context) = annotationMenu else { return }
        annotationMenu = nil
        onSelectionFinished?()
        Task { await reflect(on: context.locator) }
    }

    // MARK: Highlight menu

    func showHighlightMenu(for id: UUID, anchor: CGRect?) {
        guard highlights.contains(where: { $0.id == id }) else { return }
        if case .highlight(let current, _) = annotationMenu, current == id, anchor != nil {
            annotationMenu = nil
            return
        }
        annotationMenu = .highlight(id: id, anchor: anchor)
        showsControls = false
    }

    /// Dismisses a visible highlight menu; returns whether one was open so
    /// content taps can avoid also toggling the reader chrome.
    @discardableResult
    func closeHighlightMenu() -> Bool {
        guard case .highlight = annotationMenu else { return false }
        annotationMenu = nil
        return true
    }

    func changeHighlightColor(_ id: UUID, to color: HighlightColor) {
        guard let highlight = highlights.first(where: { $0.id == id }) else { return }
        guard highlight.color != color else { return }
        preferences.lastUsedHighlightColor = color
        savePreferences()
        update(highlight: highlight, color: color)
    }

    /// Deletes a highlight immediately, keeps its notes as standalone notes
    /// (persisting the unlink, unlike the old in-memory-only rewrite), and
    /// offers a one-tap undo before the notice expires.
    func deleteHighlightWithUndo(_ id: UUID) {
        guard let highlight = highlights.first(where: { $0.id == id }) else { return }
        closeHighlightMenu()
        let linkedNotes = notes.filter { $0.highlightID == id }
        let unlinkedNotes = linkedNotes.map(\.detachedFromHighlight)
        highlights.removeAll { $0.id == id }
        for note in unlinkedNotes {
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index] = note
            }
        }
        AnnotationHaptics.annotationDeleted()
        showNotice(.deletedHighlight(highlight, notes: linkedNotes))
        Task {
            do {
                try await repository.deleteHighlight(id: id)
                for note in unlinkedNotes {
                    try await repository.save(note: note)
                }
            } catch {
                await reloadAnnotations(after: error)
            }
        }
    }

    // MARK: Transient annotation UI

    /// Closes annotation menus. Called on navigation, rotation, and scene
    /// changes where stale screen coordinates would anchor UI to nothing.
    func clearTransientAnnotationUI() {
        if case .selection = annotationMenu { onSelectionFinished?() }
        annotationMenu = nil
    }

    func showNotice(_ kind: ReaderTransientNotice.Kind) {
        transientNotice = ReaderTransientNotice(kind: kind)
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.transientNotice = nil
        }
    }

    func clearNotice() {
        noticeTask?.cancel()
        noticeTask = nil
        transientNotice = nil
    }

    func undoNotice() {        guard let notice = transientNotice else { return }
        switch notice.kind {
        case .copied:
            clearNotice()
        case .deletedHighlight(let highlight, let removedNotes):
            clearNotice()
            guard !highlights.contains(where: { $0.id == highlight.id }) else { return }
            highlights.append(highlight)
            let relinkedNotes = removedNotes.map { $0.attached(to: highlight.id) }
            for note in relinkedNotes {
                if let index = notes.firstIndex(where: { $0.id == note.id }) {
                    notes[index] = note
                } else {
                    notes.append(note)
                }
            }
            Task {
                do {
                    try await repository.save(highlight: highlight)
                    for note in relinkedNotes {
                        try await repository.save(note: note)
                    }
                } catch {
                    await reloadAnnotations(after: error)
                }
            }
        case .deletedNote(let note):
            clearNotice()
            guard !notes.contains(where: { $0.id == note.id }) else { return }
            notes.append(note)
            notes.sort { $0.createdAt < $1.createdAt }
            Task {
                do { try await repository.save(note: note) }
                catch {
                    notes.removeAll { $0.id == note.id }
                    errorMessage = error.localizedDescription
                }
            }
        }
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
    /// Removes a note immediately with a one-tap undo. Used when the user
    /// clears a note's text entirely — the note is never silently lost.
    func deleteNoteWithUndo(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        showNotice(.deletedNote(note))
        Task {
            do { try await repository.deleteNote(id: note.id) }
            catch {
                notes.append(note)
                notes.sort { $0.createdAt < $1.createdAt }
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Waits for any debounced note writes so dismissal cannot lose the last
    /// keystrokes. User output is the product's most important data (PRD P2).
    func flushNoteSaves() async {
        let tasks = Array(noteSaveTasks.values)
        for task in tasks {
            await task.value
        }
    }
    func jump(to locator: BookLocator) {
        if let currentLocator, !currentLocator.identifiesSameAnchor(as: locator) {
            locatorHistory.record(currentLocator)
            canNavigateBack = locatorHistory.canGoBack
        }
        jumpTargetJSON = locator.json
        showsControls = false
    }

    func jumpToHighlight(_ id: UUID) {
        guard let highlight = highlights.first(where: { $0.id == id }) else { return }
        pendingHighlightAfterJumpID = id
        jump(to: highlight.locator)
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

extension Note {
    /// Detaches a note from its highlight so it survives as a standalone note.
    var detachedFromHighlight: Note {
        Note(id: id, bookID: bookID, locator: locator, body: body, createdAt: createdAt, updatedAt: updatedAt)
    }

    /// Re-attaches a detached note to a highlight (undo of a deletion).
    func attached(to highlightID: UUID) -> Note {
        Note(id: id, bookID: bookID, highlightID: highlightID, locator: locator, body: body, createdAt: createdAt, updatedAt: updatedAt)
    }
}

/// Restrained haptics for annotation moments only (PRD 10.4); page turns and
/// ordinary reading never vibrate.
enum AnnotationHaptics {
    static func highlightCreated() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func annotationDeleted() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
}

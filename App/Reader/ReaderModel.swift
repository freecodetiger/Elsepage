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

struct ReaderHelpPresentation: Identifiable {
    let id = UUID()
    let model: ReaderHelpModel
}

/// The single in-place annotation surface. Either the toolbar for a fresh
/// selection or the menu of an existing highlight — never both at once.
struct ReaderAnnotationConflict: Equatable {
    let noteID: UUID
    let highlightID: UUID
    let anchor: CGRect?
}

enum ReaderAnnotationMenu: Equatable {
    case selection(ReaderSelectionContext)
    case highlight(id: UUID, anchor: CGRect?)
    case conflict(ReaderAnnotationConflict)
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
        /// 从 Agent Citation 跳回原文 (PRD §10.3) — chrome-level acknowledgment
        /// only; the EPUB content itself never animates (P1).
        case returnedToSource
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
    let readerHelpService: ReaderHelpService
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
    var helpPresentation: ReaderHelpPresentation?
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
    @ObservationIgnored private var deferredPreparationTask: Task<Void, Never>?
    @ObservationIgnored private var helpSession: ReaderHelpModel?
    @ObservationIgnored var onSelectionFinished: (() -> Void)?
    /// Phase-0 perf anchor: set by ReaderScreen when the cover opens; the
    /// coordinator records readerOpen = now → first locationDidChange.
    @ObservationIgnored var perfOpenBeganAt: CFTimeInterval = 0

    init(
        book: Book,
        fileURL: URL,
        repository: any ReadingRepository,
        books: any BookRepository,
        sessions: ReadingSessionService,
        reflections: any ReflectionRepository,
        readerAgent: ReaderAgent,
        readerHelpService: ReaderHelpService,
        makePolishService: (@MainActor () async -> TranscriptPolishService?)? = nil,
        requestedLocator: BookLocator? = nil,
        readium: ReadiumServices
    ) {
        self.book = book; self.fileURL = fileURL; self.repository = repository; self.books = books
        self.sessions = sessions; reflectionRepository = reflections
        self.readerAgent = readerAgent
        self.readerHelpService = readerHelpService
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
        // Begin EPUB parsing before the small DB gate. ReadiumServices joins
        // this task when the navigator asks for the same publication.
        readium.preload(fileURL, allowUserInteraction: true)
        do {
            // Only position and preferences gate navigator construction. The
            // remaining reads are presentation data and can settle after the
            // first frame is already on screen.
            async let positionTask = repository.position(for: book.id)
            async let preferencesTask = repository.preferences(for: book.id)
            let (position, loadedPreferences) = try await (positionTask, preferencesTask)
            try Task.checkCancellation()
            if initialLocatorJSON == nil {
                initialLocatorJSON = position?.locator.json
                currentLocator = position?.locator
                progress = position?.locator.totalProgression ?? 0
            }
            preferences = loadedPreferences
            isPrepared = true

            let repository = self.repository
            let books = self.books
            let bookID = book.id
            deferredPreparationTask = Task { [weak self] in
                do {
                    async let highlightsTask = repository.highlights(for: bookID)
                    async let notesTask = repository.notes(for: bookID)
                    let (loadedHighlights, loadedNotes) = try await (highlightsTask, notesTask)
                    try Task.checkCancellation()
                    guard let self else { return }
                    self.highlights = loadedHighlights
                    self.notes = loadedNotes
                    try await books.markOpened(bookID, at: Date())
                } catch is CancellationError {
                    return
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        } catch is CancellationError {
            return
        } catch {
            isPrepared = true
            errorMessage = error.localizedDescription
        }
    }
    func save(locator: BookLocator) {
        // Location changes no longer close annotation menus. Readium emits
        // locationDidChange while the webview's layout settles (compensating
        // column reflows, image loading) even though the visible page did not
        // move — on device these landed tens of milliseconds after a menu
        // opened and flashed it away. Menus close on real navigation instead
        // (jumps, taps, menu actions, rotation, backgrounding); a menu left
        // over after a gesture page turn is dismissed by the next content tap.
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
        let replacedMenu = annotationMenu != nil
        annotationMenu = .selection(.init(locator: locator, text: text, frame: frame))
        showsControls = false
        AnnotationLog.event("selection.show frame=\(AnnotationLog.rect(frame)) replacedMenu=\(replacedMenu) text=\"\(text.prefix(24))\"")
    }

    func dismissSelectionMenu() {
        guard case .selection = annotationMenu else { return }
        annotationMenu = nil
        onSelectionFinished?()
        AnnotationLog.event("selection.dismiss (catcher tap)")
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

    func askAgentFromSelection() {
        guard case .selection(let context) = annotationMenu else { return }
        annotationMenu = nil
        onSelectionFinished?()

        let helpModel: ReaderHelpModel
        if let existing = helpSession, existing.anchor.identifiesSameAnchor(as: context.locator) {
            helpModel = existing
        } else {
            let anchor = context.locator
            helpModel = ReaderHelpModel(
                book: book,
                anchor: anchor,
                selectedText: context.text,
                chapterTitle: currentChapterTitle,
                service: readerHelpService
            ) { [weak self] body in
                guard let self else { throw ReaderHelpModelError.readerUnavailable }
                try await self.saveHelpNote(anchor: anchor, body: body)
            }
            helpSession = helpModel
        }
        Perf.shared.event("readerHelp.present")
        helpPresentation = ReaderHelpPresentation(model: helpModel)
    }

    // MARK: Highlight menu

    /// Stray events from the very tap that opened the menu (a pointer-derived
    /// `didTapAt` or a duplicated decoration activation can race the menu
    /// opening when the webview's decoration layout settles mid-tap) must not
    /// close it again. Human re-taps always land later than this window.
    static let highlightMenuGraceInterval: TimeInterval = 0.35
    @ObservationIgnored private var highlightMenuOpenedAt: TimeInterval = 0

    func showHighlightMenu(for id: UUID, anchor: CGRect?) {
        guard highlights.contains(where: { $0.id == id }) else {
            AnnotationLog.event("menu.show id=\(AnnotationLog.id(id)) anchor=\(AnnotationLog.rect(anchor)) → rejected: highlight missing")
            return
        }
        if case .highlight(let current, _) = annotationMenu, current == id, anchor != nil {
            let sinceOpen = CFAbsoluteTimeGetCurrent() - highlightMenuOpenedAt
            let since = String(format: "%.3f", sinceOpen)
            if sinceOpen <= Self.highlightMenuGraceInterval {
                AnnotationLog.event("menu.reactivate id=\(AnnotationLog.id(id)) sinceOpen=\(since) → ignored (grace)")
                return
            }
            AnnotationLog.event("menu.reactivate id=\(AnnotationLog.id(id)) sinceOpen=\(since) → toggled closed")
            annotationMenu = nil
            return
        }
        let replacedSelection: Bool
        if case .selection = annotationMenu { replacedSelection = true } else { replacedSelection = false }
        annotationMenu = .highlight(id: id, anchor: anchor)
        highlightMenuOpenedAt = CFAbsoluteTimeGetCurrent()
        showsControls = false
        AnnotationLog.event("menu.open id=\(AnnotationLog.id(id)) anchor=\(AnnotationLog.rect(anchor)) replacedSelection=\(replacedSelection)")
    }

    /// Outcome of a tap-driven close attempt: the menu was dismissed, the tap
    /// fell inside the grace window (swallow it, do not toggle the chrome
    /// either), or there was no menu at all.
    enum HighlightMenuClose {
        case closed
        case deferred
        case absent
    }

    /// Dismisses a visible highlight menu on a content tap; the result tells
    /// the caller whether the same tap may still toggle the reader chrome.
    func closeHighlightMenu() -> HighlightMenuClose {
        let identifier: String
        switch annotationMenu {
        case .highlight(let current, _):
            identifier = AnnotationLog.id(current)
        case .conflict(let conflict):
            identifier = "conflict:\(AnnotationLog.id(conflict.noteID)):\(AnnotationLog.id(conflict.highlightID))"
        default:
            return .absent
        }

        let sinceOpen = CFAbsoluteTimeGetCurrent() - highlightMenuOpenedAt
        let since = String(format: "%.3f", sinceOpen)
        guard sinceOpen > Self.highlightMenuGraceInterval else {
            AnnotationLog.event("menu.tapClose id=\(identifier) sinceOpen=\(since) → deferred (grace)")
            return .deferred
        }
        annotationMenu = nil
        AnnotationLog.event("menu.tapClose id=\(identifier) sinceOpen=\(since) → closed")
        return .closed
    }

    func handleHighlightActivation(for id: UUID, anchor: CGRect?) {
        guard highlights.contains(where: { $0.id == id }) else { return }
        if let note = conflictingStandaloneNote(forHighlightID: id) {
            showAnnotationConflict(noteID: note.id, highlightID: id, anchor: anchor)
        } else {
            showHighlightMenu(for: id, anchor: anchor)
        }
    }

    func handleNoteActivation(for id: UUID, anchor: CGRect?) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        if let highlightID = note.highlightID {
            showHighlightMenu(for: highlightID, anchor: anchor)
        } else if let highlight = overlappingHighlight(for: note) {
            showAnnotationConflict(noteID: note.id, highlightID: highlight.id, anchor: anchor)
        } else {
            openNoteEditor(.note(id))
        }
    }

    func chooseNoteFromConflict(_ conflict: ReaderAnnotationConflict) {
        annotationMenu = nil
        openNoteEditor(.note(conflict.noteID))
    }

    func chooseHighlightFromConflict(_ conflict: ReaderAnnotationConflict) {
        annotationMenu = nil
        showHighlightMenu(for: conflict.highlightID, anchor: conflict.anchor)
    }

    func hasNote(forHighlightID id: UUID) -> Bool {
        note(forHighlightID: id) != nil
    }

    func openNote(forHighlightID id: UUID) {
        dismissHighlightMenu()
        if let note = note(forHighlightID: id) {
            openNoteEditor(.note(note.id))
        } else {
            openNoteEditor(.highlight(id))
        }
    }

    private func note(forHighlightID id: UUID) -> Note? {
        if let attached = notes.first(where: { $0.highlightID == id }) {
            return attached
        }
        return conflictingStandaloneNote(forHighlightID: id)
    }

    private func conflictingStandaloneNote(forHighlightID id: UUID) -> Note? {
        guard let highlight = highlights.first(where: { $0.id == id }) else { return nil }
        return notes
            .filter { $0.highlightID == nil && $0.locator.appearsToOverlapText(with: highlight.locator) }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private func overlappingHighlight(for note: Note) -> Highlight? {
        let matches = highlights.filter { $0.locator.appearsToOverlapText(with: note.locator) }
        if let exact = matches.first(where: { $0.locator.identifiesSameAnchor(as: note.locator) }) {
            return exact
        }
        return matches.min { lhs, rhs in
            let lhsDistance = abs((lhs.locator.progression ?? 0) - (note.locator.progression ?? 0))
            let rhsDistance = abs((rhs.locator.progression ?? 0) - (note.locator.progression ?? 0))
            return lhsDistance < rhsDistance
        }
    }

    private func showAnnotationConflict(noteID: UUID, highlightID: UUID, anchor: CGRect?) {
        annotationMenu = .conflict(.init(noteID: noteID, highlightID: highlightID, anchor: anchor))
        highlightMenuOpenedAt = CFAbsoluteTimeGetCurrent()
        showsControls = false
        AnnotationLog.event("conflict.open note=\(AnnotationLog.id(noteID)) highlight=\(AnnotationLog.id(highlightID)) anchor=\(AnnotationLog.rect(anchor))")
    }

    /// Immediate programmatic dismissal (menu buttons, deletion) — no grace.
    func dismissHighlightMenu() {
        guard case .highlight(let current, _) = annotationMenu else { return }
        annotationMenu = nil
        AnnotationLog.event("menu.dismiss id=\(AnnotationLog.id(current)) (programmatic)")
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
        dismissHighlightMenu()
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
    func clearTransientAnnotationUI(reason: String) {
        if case .selection = annotationMenu { onSelectionFinished?() }
        let hadMenu = annotationMenu != nil
        annotationMenu = nil
        if hadMenu {
            AnnotationLog.event("menu.clear reason=\(reason)")
        }
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
        case .copied, .returnedToSource:
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

    func saveHelpNote(anchor: BookLocator, body: String) async throws {
        let highlightID = highlights.first(where: {
            $0.locator.identifiesSameAnchor(as: anchor)
        })?.id
        let note = Note(
            bookID: book.id,
            highlightID: highlightID,
            locator: anchor,
            body: body
        )
        try await repository.save(note: note)
        notes.append(note)
        notes.sort { $0.createdAt < $1.createdAt }
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
        // Explicit app navigation (TOC/search/annotation) moves the content
        // under any open menu — close it here, since location changes no
        // longer close menus (they carry layout-settle noise).
        clearTransientAnnotationUI(reason: "jump")
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
        clearTransientAnnotationUI(reason: "navigateBack")
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

    /// FIX-01: hook that counts one user-initiated agent discussion (reflection
    /// submission or follow-up send) against the reading session.
    var agentDiscussionRecorder: AgentDiscussionRecorder? {
        let sessions = sessions
        return { sessionID in
            _ = try? await sessions.recordAgentDiscussion(id: sessionID)
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
                achievements: achievements,
                recordAgentDiscussion: agentDiscussionRecorder
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
/// ordinary reading never vibrate. The vocabulary itself lives in Haptics.
@MainActor
private enum AnnotationHaptics {
    static func highlightCreated() {
        Haptics.highlightCreated()
    }

    static func annotationDeleted() {
        Haptics.annotationDeleted()
    }
}

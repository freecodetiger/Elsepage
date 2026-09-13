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
    let range: AnnotationRange?
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
        case highlightOverlap
        case deletedHighlight(TextAnnotation)
        case deletedNote(TextAnnotation)
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
    let textAnnotationRepository: any TextAnnotationRepository
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
    private(set) var textAnnotations: [TextAnnotation] = []
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
        textAnnotations: any TextAnnotationRepository,
        makePolishService: (@MainActor () async -> TranscriptPolishService?)? = nil,
        requestedLocator: BookLocator? = nil,
        readium: ReadiumServices
    ) {
        self.book = book; self.fileURL = fileURL; self.repository = repository; self.books = books
        self.sessions = sessions; reflectionRepository = reflections
        self.readerAgent = readerAgent
        self.readerHelpService = readerHelpService
        self.textAnnotationRepository = textAnnotations
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

            let annotations = textAnnotationRepository
            let books = self.books
            let bookID = book.id
            deferredPreparationTask = Task { [weak self] in
                do {
                    let loadedAnnotations = try await annotations.annotations(for: bookID)
                    try Task.checkCancellation()
                    guard let self else { return }
                    self.textAnnotations = loadedAnnotations
                    self.refreshAnnotationProjections()
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
    private func annotation(for locator: BookLocator, range: AnnotationRange? = nil) -> TextAnnotation? {
        let resolvedRange = range ?? AnnotationRange(
            bookID: book.id,
            resourceHref: locator.href,
            startLocator: locator,
            endLocator: locator
        )
        return textAnnotations.first { $0.range.rangeKey == resolvedRange.rangeKey }
    }

    private func annotation(forHighlightID id: UUID) -> TextAnnotation? {
        textAnnotations.first { $0.id == id }
    }

    private func annotation(forNoteID id: UUID) -> TextAnnotation? {
        textAnnotations.first { annotation in annotation.notes.contains { $0.id == id } }
    }

    private func replaceAnnotation(_ annotation: TextAnnotation) {
        if let index = textAnnotations.firstIndex(where: { $0.id == annotation.id }) {
            textAnnotations[index] = annotation
        } else {
            textAnnotations.append(annotation)
        }
        textAnnotations.sort { $0.createdAt < $1.createdAt }
        refreshAnnotationProjections()
        Task { [weak self] in
            do { try await self?.textAnnotationRepository.save(annotation: annotation) }
            catch {
                await self?.reloadAnnotations(after: error)
            }
        }
    }

    private func removeAnnotation(id: UUID) {
        textAnnotations.removeAll { $0.id == id }
        refreshAnnotationProjections()
        Task { [weak self] in
            do { try await self?.textAnnotationRepository.deleteAnnotation(id: id) }
            catch {
                await self?.reloadAnnotations(after: error)
            }
        }
    }

    private func refreshAnnotationProjections() {
        highlights = textAnnotations.compactMap { annotation in
            guard let layer = annotation.highlight else { return nil }
            return Highlight(
                id: annotation.id,
                bookID: annotation.range.bookID,
                locator: annotation.range.renderLocator,
                color: layer.color,
                createdAt: layer.createdAt
            )
        }
        notes = textAnnotations.flatMap { annotation in
            annotation.notes.map { entry in
                Note(
                    id: entry.id,
                    bookID: annotation.range.bookID,
                    highlightID: nil,
                    locator: annotation.range.renderLocator,
                    body: entry.body,
                    createdAt: entry.createdAt,
                    updatedAt: entry.updatedAt
                )
            }
        }
        notes.sort { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    func saveHighlight(locator: BookLocator, range: AnnotationRange? = nil, color: HighlightColor) -> Highlight? {
        let now = Date()
        if var existing = annotation(for: locator, range: range) {
            if var highlight = existing.highlight {
                highlight.color = color
                highlight.updatedAt = now
                existing.highlight = highlight
                existing.updatedAt = now
                replaceAnnotation(existing)
            } else {
                existing.highlight = HighlightLayer(color: color, createdAt: now, updatedAt: now)
                existing.updatedAt = now
                replaceAnnotation(existing)
            }
            return highlights.first { $0.id == existing.id }
        }

        let resolvedRange = range ?? AnnotationRange(
            bookID: book.id,
            resourceHref: locator.href,
            startLocator: locator,
            endLocator: locator
        )
        if textAnnotations.contains(where: {
            $0.highlight != nil && $0.range.appearsToOverlapText(with: resolvedRange)
        }) {
            showNotice(.highlightOverlap)
            return nil
        }

        let annotation = TextAnnotation(
            range: resolvedRange,
            highlight: HighlightLayer(color: color, createdAt: now, updatedAt: now),
            createdAt: now,
            updatedAt: now
        )
        replaceAnnotation(annotation)
        return highlights.first { $0.id == annotation.id }
    }

    // MARK: Selection toolbar
    //
    // Invariant: the custom selection toolbar is visible exactly while a
    // selection exists in the navigator. Opening it replaces any highlight
    // menu; acting on it closes it and clears the navigator selection.

    func showSelectionMenu(locator: BookLocator, range: AnnotationRange? = nil, text: String, frame: CGRect?) {
        let replacedMenu = annotationMenu != nil
        annotationMenu = .selection(.init(locator: locator, range: range, text: text, frame: frame))
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
        if saveHighlight(locator: context.locator, range: context.range, color: color) != nil {
            AnnotationHaptics.highlightCreated()
        }
    }

    func beginNoteFromSelection() {
        guard case .selection(let context) = annotationMenu else { return }
        annotationMenu = nil
        onSelectionFinished?()
        let now = Date()
        let resolvedRange = context.range ?? AnnotationRange(
            bookID: book.id,
            resourceHref: context.locator.href,
            startLocator: context.locator,
            endLocator: context.locator
        )
        var annotation = annotation(for: context.locator, range: resolvedRange) ?? TextAnnotation(
            range: resolvedRange,
            createdAt: now,
            updatedAt: now
        )
        let entry = NoteEntry(body: "", createdAt: now, updatedAt: now)
        annotation.notes.append(entry)
        annotation.updatedAt = now
        replaceAnnotation(annotation)
        openNoteEditor(.note(entry.id))
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
                try await self.saveHelpNote(anchor: anchor, range: context.range, body: body)
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

    func handleHighlightActivation(for id: UUID, confirmedNoteID: UUID? = nil, anchor: CGRect?) {
        guard let annotation = annotation(forHighlightID: id) else { return }
        let validatedConfirmedNoteID = confirmedNoteID.flatMap { candidate in
            self.annotation(forNoteID: candidate) == nil ? nil : candidate
        }
        let noteID = validatedConfirmedNoteID ?? annotation.notes.last?.id ?? overlappingNoteID(for: annotation.range)
        let noteDescription = noteID.map { AnnotationLog.id($0) } ?? "nil"
        AnnotationLog.event("highlight.activate id=\(AnnotationLog.id(id)) ownNotes=\(annotation.notes.count) conflictNote=\(noteDescription)")
        Perf.shared.event("annotation.activate kind=highlight id=\(AnnotationLog.id(id)) overlapNote=\(noteDescription)")
        if let noteID {
            showAnnotationConflict(noteID: noteID, highlightID: id, anchor: anchor)
        } else {
            showHighlightMenu(for: id, anchor: anchor)
        }
    }

    func handleNoteActivation(for id: UUID, confirmedHighlightID: UUID? = nil, anchor: CGRect?) {
        guard let annotation = annotation(forNoteID: id) else { return }
        let validatedConfirmedHighlightID = confirmedHighlightID.flatMap { candidate in
            self.annotation(forHighlightID: candidate) == nil ? nil : candidate
        }
        if let validatedConfirmedHighlightID {
            AnnotationLog.event("note.activate id=\(AnnotationLog.id(id)) conflictHighlight=\(AnnotationLog.id(validatedConfirmedHighlightID)) pointHit=true")
            Perf.shared.event("annotation.activate kind=note id=\(AnnotationLog.id(id)) overlapHighlight=\(AnnotationLog.id(validatedConfirmedHighlightID)) pointHit=true")
            showAnnotationConflict(noteID: id, highlightID: validatedConfirmedHighlightID, anchor: anchor)
            return
        }
        if annotation.highlight != nil {
            AnnotationLog.event("note.activate id=\(AnnotationLog.id(id)) conflictHighlight=\(AnnotationLog.id(annotation.id)) sameRange=true")
            Perf.shared.event("annotation.activate kind=note id=\(AnnotationLog.id(id)) overlapHighlight=\(AnnotationLog.id(annotation.id)) sameRange=true")
            showAnnotationConflict(noteID: id, highlightID: annotation.id, anchor: anchor)
            return
        }
        if let overlappingHighlight = textAnnotations.first(where: {
            $0.highlight != nil && $0.range.appearsToOverlapText(with: annotation.range)
        }) {
            AnnotationLog.event("note.activate id=\(AnnotationLog.id(id)) conflictHighlight=\(AnnotationLog.id(overlappingHighlight.id)) sameRange=false")
            Perf.shared.event("annotation.activate kind=note id=\(AnnotationLog.id(id)) overlapHighlight=\(AnnotationLog.id(overlappingHighlight.id)) sameRange=false")
            showAnnotationConflict(noteID: id, highlightID: overlappingHighlight.id, anchor: anchor)
            return
        }
        AnnotationLog.event("note.activate id=\(AnnotationLog.id(id)) conflictHighlight=nil")
        Perf.shared.event("annotation.activate kind=note id=\(AnnotationLog.id(id)) overlapHighlight=nil")
        openNoteEditor(.note(id))
    }

    private func overlappingNoteID(for range: AnnotationRange) -> UUID? {
        let candidates = textAnnotations
            .filter { !$0.notes.isEmpty && $0.range.appearsToOverlapText(with: range) }
            .sorted { $0.updatedAt > $1.updatedAt }
        return candidates.first?.notes.last?.id
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
        annotation(forHighlightID: id)?.notes.isEmpty == false
    }

    func openNote(forHighlightID id: UUID) {
        dismissHighlightMenu()
        guard let note = annotation(forHighlightID: id)?.notes.first else {
            openNoteEditor(.highlight(id))
            return
        }
        openNoteEditor(.note(note.id))
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
        guard var annotation = annotation(forHighlightID: id),
              var highlight = annotation.highlight,
              highlight.color != color else { return }
        preferences.lastUsedHighlightColor = color
        savePreferences()
        highlight.color = color
        highlight.updatedAt = Date()
        annotation.highlight = highlight
        annotation.updatedAt = Date()
        replaceAnnotation(annotation)
    }

    /// Removes only the highlight layer. NoteEntry values stay on the same
    /// TextAnnotation and remain visible as underline annotations.
    func deleteHighlightWithUndo(_ id: UUID) {
        guard var annotation = annotation(forHighlightID: id) else { return }
        let snapshot = annotation
        dismissHighlightMenu()
        annotation.highlight = nil
        annotation.updatedAt = Date()
        if annotation.isEmpty {
            removeAnnotation(id: annotation.id)
        } else {
            replaceAnnotation(annotation)
        }
        AnnotationHaptics.annotationDeleted()
        showNotice(.deletedHighlight(snapshot))
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

    func undoNotice() {
        guard let notice = transientNotice else { return }
        switch notice.kind {
        case .copied, .returnedToSource, .highlightOverlap:
            clearNotice()
        case .deletedHighlight(let snapshot), .deletedNote(let snapshot):
            clearNotice()
            replaceAnnotation(snapshot)
        }
    }

    func update(highlight: Highlight, color: HighlightColor) {
        changeHighlightColor(highlight.id, to: color)
    }

    func saveNote(for highlight: Highlight, body: String) {
        guard var annotation = annotation(forHighlightID: highlight.id) else { return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let now = Date()
        annotation.notes.append(NoteEntry(body: trimmed, createdAt: now, updatedAt: now))
        annotation.updatedAt = now
        replaceAnnotation(annotation)
    }

    func saveHelpNote(anchor: BookLocator, range: AnnotationRange? = nil, body: String) async throws {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let now = Date()
        let resolvedRange = range ?? AnnotationRange(
            bookID: book.id,
            resourceHref: anchor.href,
            startLocator: anchor,
            endLocator: anchor
        )
        var annotation = annotation(for: anchor, range: resolvedRange) ?? TextAnnotation(
            range: resolvedRange,
            createdAt: now,
            updatedAt: now
        )
        annotation.notes.append(NoteEntry(body: trimmed, createdAt: now, updatedAt: now))
        annotation.updatedAt = now
        try await textAnnotationRepository.save(annotation: annotation)
        if let index = textAnnotations.firstIndex(where: { $0.id == annotation.id }) {
            textAnnotations[index] = annotation
        } else {
            textAnnotations.append(annotation)
        }
        textAnnotations.sort { $0.createdAt < $1.createdAt }
        refreshAnnotationProjections()
    }

    @discardableResult
    func appendNoteEntry(after noteID: UUID) -> UUID? {
        guard var annotation = annotation(forNoteID: noteID) else { return nil }
        let now = Date()
        let entry = NoteEntry(body: "", createdAt: now, updatedAt: now)
        annotation.notes.append(entry)
        annotation.updatedAt = now
        replaceAnnotation(annotation)
        return entry.id
    }

    func update(note: Note, body: String) {
        guard var annotation = annotation(forNoteID: note.id),
              let index = annotation.notes.firstIndex(where: { $0.id == note.id }) else { return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            deleteNoteWithUndo(note)
            return
        }
        annotation.notes[index].body = trimmed
        annotation.notes[index].updatedAt = Date()
        annotation.updatedAt = Date()
        replaceAnnotation(annotation)
    }

    /// Removes one NoteEntry with one-tap undo. Other entries and highlight
    /// layers on the same annotation remain untouched.
    func deleteNoteWithUndo(_ note: Note) {
        guard var annotation = annotation(forNoteID: note.id) else { return }
        let snapshot = annotation
        annotation.notes.removeAll { $0.id == note.id }
        annotation.updatedAt = Date()
        if annotation.isEmpty {
            removeAnnotation(id: annotation.id)
        } else {
            replaceAnnotation(annotation)
        }
        showNotice(.deletedNote(snapshot))
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
            textAnnotations = try await textAnnotationRepository.annotations(for: book.id)
            refreshAnnotationProjections()
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

import LibraryCore
import Observation
import ReadingSessionCore
import ReflectionCore

/// Resolves the one meaningful next action for the library. It is a *persistent*
/// entry point, not a transient one: a session that ended without a reflection
/// keeps offering one until the user writes it. "这次不写" only closes the card
/// for the current run — the session is not written to the permanent store, so
/// the card returns on the next launch and the reader offers the next session's
/// reflection as usual.
@MainActor @Observable
final class LibraryNextActionModel {
    private let library: LibraryModel
    private(set) var state: TodayProductState = .noCurrentBook
    private(set) var isLoading = false
    private let dismissals: ReflectionPromptDismissalStore
    /// Sessions skipped during this run. In-memory on purpose: a skip must not
    /// survive a relaunch, or "这次不写" becomes a permanent opt-out again.
    private var dismissedThisRun: Set<ReadingSessionID> = []

    init(library: LibraryModel, dismissals: ReflectionPromptDismissalStore = ReflectionPromptDismissalStore()) {
        self.library = library
        self.dismissals = dismissals
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let book = library.currentBook else {
            state = .noCurrentBook
            return
        }

        do {
            let reflections = try await library.reflectionRepository.reflections(for: book.id)
            let sessions = try await library.sessionRepository.sessions(for: book.id)
            state = TodayProductStateResolver.resolve(
                currentBook: book,
                sessions: sessions,
                reflections: reflections,
                dismissedSessionIDs: dismissals.dismissedSessionIDs()
                    .union(dismissedThisRun)
            )
        } catch is CancellationError {
            return
        } catch {
            state = .continueReading(book)
        }
    }

    func dismissReflectionPrompt(for sessionID: ReadingSessionID) {
        dismissedThisRun.insert(sessionID)
    }

    /// The book and session awaiting a reflection, or nil. At most one card in
    /// the grid shows the 补写想法 affordance.
    var pendingReflection: (book: Book, session: ReadingSession)? {
        guard case .offerReflection(let book, let session) = state else { return nil }
        return (book, session)
    }
}

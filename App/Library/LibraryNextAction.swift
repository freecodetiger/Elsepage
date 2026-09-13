import AchievementCore
import LibraryCore
import Observation
import ReadingSessionCore
import ReflectionCore
import SwiftUI

/// The only retained capability from the former Today tab: surface the one
/// meaningful next action above the library. All other Today states are already
/// represented by the library grid or the reflection flow itself.
@MainActor @Observable
final class LibraryNextActionModel {
    let library: LibraryModel
    private(set) var state: TodayProductState = .noCurrentBook
    private(set) var isLoading = false
    private let dismissals: ReflectionPromptDismissalStore

    init(library: LibraryModel, dismissals: ReflectionPromptDismissalStore = ReflectionPromptDismissalStore()) {
        self.library = library
        self.dismissals = dismissals
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let book = library.books.max(by: {
            ($0.lastOpenedAt ?? $0.importedAt) < ($1.lastOpenedAt ?? $1.importedAt)
        }) else {
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
            )
        } catch is CancellationError {
            return
        } catch {
            state = .continueReading(book)
        }
    }

    func dismissReflectionPrompt(for sessionID: ReadingSessionID) {
        dismissals.dismiss(sessionID)
    }
}

struct LibraryNextActionView: View {
    @Bindable var model: LibraryNextActionModel
    let achievements: AchievementModel?
    let onSaved: () -> Void

    @State private var reflection: SessionReflectionModel?
    @State private var presentedReflectionSessionID: ReadingSessionID?
    @State private var didSaveReflectionInSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if case .offerReflection(let book, let session) = model.state {
                card(book: book, session: session)
                    .transition(.moment(reduceMotion))
            }
        }
        .animation(ElsepageTheme.Motion.moment(reduceMotion), value: model.state)
        .sheet(item: $reflection) { reflection in
            SessionReflectionSheet(model: reflection) { _ in
                didSaveReflectionInSheet = true
                Task { await model.reload() }
                onSaved()
            }
        }
        .onChange(of: reflection?.id) { _, currentID in
            guard currentID == nil, let sessionID = presentedReflectionSessionID else { return }
            presentedReflectionSessionID = nil
            defer { didSaveReflectionInSheet = false }
            if !didSaveReflectionInSheet {
                model.dismissReflectionPrompt(for: sessionID)
                Task { await model.reload() }
            }
        }
    }

    private func card(book: Book, session: ReadingSession) -> some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.medium) {
            Text("下一步")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.elsepageTextTertiary)

            Text("刚才读的，还没有留下想法。")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.elsepageTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(book.title)
                .font(.subheadline)
                .foregroundStyle(Color.elsepageTextSecondary)

            Button("补写想法") {
                guard let locator = session.endLocator else { return }
                didSaveReflectionInSheet = false
                presentedReflectionSessionID = session.id
                reflection = SessionReflectionModel(
                    book: book,
                    summary: SessionEndingSummary(session: session),
                    locator: locator,
                    reflectionRepository: model.library.reflectionRepository,
                    readerAgent: model.library.readerAgent,
                    makePolishService: model.library.makePolishService,
                    achievements: achievements,
                    recordAgentDiscussion: { sessionID in
                        try? await model.library.sessionService.recordAgentDiscussion(id: sessionID)
                    }
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(.elsepageInteractive)
            .foregroundStyle(Color.elsepageOnInteractive)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ElsepageTheme.Spacing.large)
        .background(
            Color.elsepageSurface,
            in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.large, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ElsepageTheme.Radius.large, style: .continuous)
                .stroke(Color.elsepageBorder)
        }
    }
}

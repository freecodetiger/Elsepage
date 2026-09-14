import AchievementCore
import AppInfrastructure
import LibraryCore
import Observation
import ReadingSessionCore
import ReflectionCore
import SwiftUI
import UIKit

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

/// The reading desk above the physical shelf. It always presents the current
/// book; when a Reflection is waiting, a paper note becomes the primary action.
struct LibraryCurrentReadingDeskView: View {
    @Bindable var model: LibraryNextActionModel
    let book: Book
    let progress: Double?
    let cover: UIImage?
    let achievements: AchievementModel?
    let openBook: () -> Void
    let onSaved: () -> Void

    @State private var reflection: SessionReflectionModel?
    @State private var presentedReflectionSessionID: ReadingSessionID?
    @State private var didSaveReflectionInSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pendingSession: ReadingSession? {
        guard case .offerReflection(let stateBook, let session) = model.state,
              stateBook.id == book.id else { return nil }
        return session
    }

    private var accentColor: Color {
        LibraryShelfPalette.color(for: book.id)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: ElsepageTheme.Spacing.medium) {
                coverView
                metadata
            }
            VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.medium) {
                coverView
                metadata
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ElsepageTheme.Spacing.medium)
        .background(
            Color.elsepageSurface,
            in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.large, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ElsepageTheme.Radius.large, style: .continuous)
                .stroke(Color.elsepageBorder)
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

    private var coverView: some View {
        ZStack(alignment: .topTrailing) {
            ElsepageBookCover(
                image: cover,
                title: book.title,
                author: book.author,
                seed: Int(book.id.rawValue.uuid.0)
            )
            .frame(width: 84, height: 126)

            if let progress {
                GeometryReader { geometry in
                    Capsule()
                        .fill(accentColor)
                        .frame(width: 5, height: max(10, geometry.size.height * progress))
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 7)
                        .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                }
                .frame(width: 5, height: 110)
                .padding(.trailing, 8)
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
        .accessibilityHidden(true)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.xSmall) {
            Text(book.title)
                .font(.system(.headline, design: .serif, weight: .semibold))
                .foregroundStyle(Color.elsepageTextPrimary)
                .lineLimit(2)

            if let author = book.author, !author.isEmpty {
                Text(author)
                    .font(.caption)
                    .foregroundStyle(Color.elsepageTextSecondary)
                    .lineLimit(1)
            }

            HStack(spacing: ElsepageTheme.Spacing.xSmall) {
                if let progress {
                    ProgressView(value: progress)
                        .tint(accentColor)
                        .frame(maxWidth: 82)
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.elsepageTextSecondary)
                }
                if let lastOpenedAt = book.lastOpenedAt {
                    if progress != nil { Text("·").foregroundStyle(Color.elsepageTextTertiary) }
                    Text(ElsepageDateFormat.shortDate(lastOpenedAt))
                        .font(.caption)
                        .foregroundStyle(Color.elsepageTextTertiary)
                }
            }

            if let session = pendingSession {
                reflectionNote(session: session)
            } else {
                Button("继续阅读", action: openBook)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.elsepageInteractive)
                    .foregroundStyle(Color.elsepageOnInteractive)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reflectionNote(session: ReadingSession) -> some View {
        HStack(alignment: .center, spacing: ElsepageTheme.Spacing.small) {
            Text("还没有留下想法")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.elsepageTextPrimary)
            Spacer(minLength: 4)
            Button("补写") {
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
            .controlSize(.small)
            .tint(.elsepageInteractive)
            .foregroundStyle(Color.elsepageOnInteractive)
        }
        .padding(.horizontal, ElsepageTheme.Spacing.small)
        .padding(.vertical, 7)
        .background(
            accentColor.opacity(0.10),
            in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous)
                .stroke(accentColor.opacity(0.28))
        }
    }

}

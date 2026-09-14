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
            HStack(alignment: .center, spacing: ElsepageTheme.Spacing.large) {
                readingScene
                metadata
            }
            VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.large) {
                readingScene
                    .frame(maxWidth: .infinity, alignment: .center)
                metadata
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// A reading scene, not a card: the cover stands on a shallow, neutral
    /// surface with a single contact shadow. The metadata stays on the page.
    private var readingScene: some View {
        ZStack(alignment: .bottom) {
            deskSurface
                .offset(y: 5)

            coverView
                .padding(.bottom, 22)
        }
        .frame(width: 140, height: 182)
    }

    private var deskSurface: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [
                    Color.elsepageSurface,
                    Color.elsepageSurfaceSecondary
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Rectangle()
                .fill(Color.elsepageBorder.opacity(0.9))
                .frame(height: 1)
        }
        .frame(width: 140, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 8, y: 6)
        .accessibilityHidden(true)
    }

    private var coverView: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: openBook) {
                ZStack(alignment: .topTrailing) {
                    ElsepageBookCover(
                        image: cover,
                        title: book.title,
                        author: book.author,
                        seed: Int(book.id.rawValue.uuid.0)
                    )
                    .frame(
                        width: LibraryBookMetrics.currentCoverWidth,
                        height: LibraryBookMetrics.objectHeight
                    )

                    if let progress {
                        GeometryReader { geometry in
                            Capsule()
                                .fill(accentColor)
                                .frame(width: 5, height: max(10, geometry.size.height * progress))
                                .frame(maxHeight: .infinity, alignment: .top)
                                .padding(.top, 8)
                                .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                        }
                        .frame(width: 5, height: LibraryBookMetrics.objectHeight - 16)
                        .padding(.trailing, 8)
                        .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.plain)
            .shadow(color: .black.opacity(0.16), radius: 10, y: 6)
            .accessibilityLabel("《\(book.title)》，\(book.author ?? "未知作者")")
            .accessibilityHint("打开并继续阅读")

            if let session = pendingSession {
                reflectionTab(session: session)
                    .offset(x: 5, y: -11)
            }
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
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

            Button("继续阅读", action: openBook)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.elsepageInteractive)
                .foregroundStyle(Color.elsepageOnInteractive)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reflectionTab(session: ReadingSession) -> some View {
        Button {
            presentReflection(for: session)
        } label: {
            Text("补写想法")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.elsepageTextPrimary)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(
                    Color(red: 0.96, green: 0.91, blue: 0.79),
                    in: RoundedRectangle(cornerRadius: 3, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Color(red: 0.76, green: 0.67, blue: 0.47).opacity(0.55))
                }
                .rotationEffect(.degrees(2))
                .shadow(color: .black.opacity(0.13), radius: 3, y: 2)
        }
        .buttonStyle(.plain)
        .frame(width: AccessibilityMetrics.minimumTapTargetSide,
               height: AccessibilityMetrics.minimumTapTargetSide,
               alignment: .topTrailing)
        .contentShape(Rectangle())
        .accessibilityLabel("补写刚才阅读的想法")
        .accessibilityHint("打开 Reflection 补写")
    }

    private func presentReflection(for session: ReadingSession) {
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
}

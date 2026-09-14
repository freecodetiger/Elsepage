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

private enum ReadingDeskMetrics {
    static let sceneWidth: CGFloat = 112
    static let sceneHeight: CGFloat = 164
    static let metadataWidth: CGFloat = 172
    static let horizontalSpacing = ElsepageTheme.Spacing.medium
    static let padding = ElsepageTheme.Spacing.large
    static let cornerRadius: CGFloat = 22
    static let minimumHorizontalWidth = sceneWidth + horizontalSpacing + metadataWidth
}

/// The reading desk above the physical shelf. It always presents the current
/// book. The desk is a fixed stage: changing books may replace text, but never
/// moves the cover, metadata slots or actions.
struct LibraryCurrentReadingDeskView: View {
    @Bindable var model: LibraryNextActionModel
    let book: Book
    let progress: Double?
    let cover: UIImage?
    let achievements: AchievementModel?
    let transitionNamespace: Namespace.ID
    let openBook: () -> Void
    let onSaved: () -> Void

    @State private var reflection: SessionReflectionModel?
    @State private var presentedReflectionSessionID: ReadingSessionID?
    @State private var didSaveReflectionInSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var titleSlotHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .caption) private var supportingSlotHeight: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var actionSlotHeight: CGFloat = 30

    private var pendingSession: ReadingSession? {
        guard case .offerReflection(let stateBook, let session) = model.state,
              stateBook.id == book.id else { return nil }
        return session
    }

    private var deskPrimaryText: Color {
        .white.opacity(0.96)
    }

    private var deskSecondaryText: Color {
        .white.opacity(0.86)
    }

    private var deskTertiaryText: Color {
        .white.opacity(0.80)
    }

    private var deskAccentColor: Color {
        Color(red: 0.98, green: 0.87, blue: 0.66)
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                verticalDesk
            } else {
                ViewThatFits(in: .horizontal) {
                    horizontalDesk
                    verticalDesk
                }
            }
        }
        .padding(ReadingDeskMetrics.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LibraryWoodSurface(
                kind: .desk,
                cornerRadius: ReadingDeskMetrics.cornerRadius
            )
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

    private var horizontalDesk: some View {
        HStack(alignment: .center, spacing: ReadingDeskMetrics.horizontalSpacing) {
            readingScene
            metadata
                .frame(width: ReadingDeskMetrics.metadataWidth, alignment: .leading)
        }
        .frame(minWidth: ReadingDeskMetrics.minimumHorizontalWidth, alignment: .leading)
    }

    private var verticalDesk: some View {
        VStack(alignment: .leading, spacing: ReadingDeskMetrics.horizontalSpacing) {
            readingScene
                .frame(maxWidth: .infinity, alignment: .center)
            metadata
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The book is the only object on the desk. The desk itself is the shared
    /// wood surface behind this fixed stage.
    private var readingScene: some View {
        ZStack {
            Ellipse()
                .fill(.black.opacity(0.24))
                .frame(width: 94, height: 12)
                .blur(radius: 4)
                .offset(y: 12)
                .accessibilityHidden(true)

            coverView
        }
        .frame(width: ReadingDeskMetrics.sceneWidth, height: ReadingDeskMetrics.sceneHeight)
    }

    private var coverView: some View {
        Button(action: openBook) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous)
                    .fill(Color(red: 0.91, green: 0.86, blue: 0.76))
                    .frame(
                        width: LibraryBookMetrics.currentCoverWidth,
                        height: LibraryBookMetrics.objectHeight
                    )
                    .offset(x: 4, y: 4)
                    .overlay(alignment: .bottom) {
                        VStack(spacing: 2) {
                            Rectangle().fill(.black.opacity(0.10)).frame(height: 0.7)
                            Rectangle().fill(.black.opacity(0.07)).frame(height: 0.7)
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 3)
                    }

                ElsepageBookCover(
                    image: cover,
                    title: book.title,
                    author: book.author,
                    seed: Int(book.id.rawValue.uuid.0),
                    showsShadow: false
                )
                .frame(
                    width: LibraryBookMetrics.currentCoverWidth,
                    height: LibraryBookMetrics.objectHeight
                )
            }
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: book.id, in: transitionNamespace)
        .accessibilityLabel("《\(book.title)》，\(book.author ?? "未知作者")")
        .accessibilityHint("打开并继续阅读")
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
            Text(book.title)
                .font(.system(.headline, design: .serif, weight: .semibold))
                .foregroundStyle(deskPrimaryText)
                .lineLimit(2)
                .truncationMode(.tail)
                .allowsTightening(true)
                .frame(height: titleSlotHeight, alignment: .topLeading)

            Text(displayAuthor)
                .font(.caption)
                .foregroundStyle(deskSecondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: supportingSlotHeight, alignment: .topLeading)

            progressAndDate
                .frame(height: supportingSlotHeight, alignment: .leading)

            deskActions
                .frame(height: actionSlotHeight, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayAuthor: String {
        guard let author = book.author?.trimmingCharacters(in: .whitespacesAndNewlines),
              !author.isEmpty else { return "未知作者" }
        return author
    }

    private var progressAndDate: some View {
        HStack(spacing: ElsepageTheme.Spacing.xSmall) {
            if let progress {
                ProgressView(value: progress)
                    .tint(deskAccentColor)
                    .frame(maxWidth: 82)
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(deskSecondaryText)
            }
            if let lastOpenedAt = book.lastOpenedAt {
                if progress != nil { Text("·").foregroundStyle(deskTertiaryText) }
                Text(ElsepageDateFormat.shortDate(lastOpenedAt))
                    .font(.caption)
                    .foregroundStyle(deskTertiaryText)
            }
        }
    }

    @ViewBuilder
    private var deskActions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
                continueReadingButton
                if let session = pendingSession {
                    reflectionButton(session: session)
                }
            }
        } else {
            HStack(spacing: ElsepageTheme.Spacing.small) {
                continueReadingButton
                if let session = pendingSession {
                    reflectionButton(session: session)
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var continueReadingButton: some View {
        deskActionButton("继续阅读", action: openBook)
    }

    private func reflectionButton(session: ReadingSession) -> some View {
        deskActionButton("补写想法") {
            presentReflection(for: session)
        }
    }

    private func deskActionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(DeskActionButtonStyle())
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity)
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

private struct DeskActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color(red: 0.20, green: 0.12, blue: 0.07))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                Color(red: 0.96, green: 0.90, blue: 0.78)
                    .opacity(configuration.isPressed ? 0.82 : 1),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(configuration.isPressed ? 0.10 : 0.24))
            }
            .shadow(
                color: .black.opacity(configuration.isPressed ? 0.08 : 0.16),
                radius: configuration.isPressed ? 1 : 3,
                y: configuration.isPressed ? 1 : 2
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.20, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

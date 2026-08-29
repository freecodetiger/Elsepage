import LibraryCore
import Observation
import ReaderCore
import ReadingSessionCore
import ReflectionCore
import SwiftUI

@MainActor @Observable
final class TodayModel {
    let library: LibraryModel
    private(set) var state: TodayProductState = .noCurrentBook
    private(set) var readingStreak = ReadingStreak(days: 0)
    private(set) var thinkingStreak = ThinkingStreak(days: 0)
    private(set) var isLoading = false
    /// Remembers "今天先不了" per session so the 补写 card stays quiet afterwards.
    private let dismissals: ReflectionPromptDismissalStore

    init(library: LibraryModel, dismissals: ReflectionPromptDismissalStore = ReflectionPromptDismissalStore()) {
        self.library = library
        self.dismissals = dismissals
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        await library.reload()
        guard let book = library.books.max(by: { ($0.lastOpenedAt ?? $0.importedAt) < ($1.lastOpenedAt ?? $1.importedAt) }) else {
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
            await refreshStreaks()
        } catch is CancellationError {
            return
        } catch {
            state = .continueReading(book)
        }
    }

    /// Persists an explicit "今天先不了" for this session; completing a reflection
    /// needs no flag because it is derived from the reflections table.
    func dismissReflectionPrompt(for sessionID: ReadingSessionID) {
        dismissals.dismiss(sessionID)
    }

    /// Streaks are GLOBAL: derived from every book's sessions/reflections.
    private func refreshStreaks() async {
        do {
            let reflections = try await library.reflectionRepository.allReflections()
            let sessions = try await library.sessionRepository.allSessions()
            let now = Date()
            let calendar = Calendar.current
            readingStreak = StreakCalculator.readingStreak(
                sessionStartDates: sessions.map(\.startedAt),
                now: now,
                calendar: calendar
            )
            thinkingStreak = StreakCalculator.thinkingStreak(
                reflectionDates: reflections.map(\.createdAt),
                now: now,
                calendar: calendar
            )
        } catch is CancellationError {
            return
        } catch {
            // Streaks are derived presentation data; keep previous values on failure.
        }
    }
}

struct TodayView: View {
    @State private var model: TodayModel
    @State private var reflection: SessionReflectionModel?
    /// The session whose 补写 sheet is currently presented, so a close without
    /// saving can be recorded as an explicit "今天先不了" for exactly that session.
    @State private var presentedReflectionSessionID: ReadingSessionID?
    @State private var didSaveReflectionInSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let openBook: (Book) -> Void
    let openLibrary: () -> Void
    let achievements: AchievementModel?

    init(
        library: LibraryModel,
        achievements: AchievementModel? = nil,
        openBook: @escaping (Book) -> Void,
        openLibrary: @escaping () -> Void
    ) {
        _model = State(initialValue: TodayModel(library: library))
        self.achievements = achievements
        self.openBook = openBook
        self.openLibrary = openLibrary
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading { ProgressView("正在看看今天…") }
                else { content.padding(ElsepageTheme.Spacing.page) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.elsepageBackground)
            // 阅读完成 / Reflection 完成 state swaps land as a quiet cross-fade
            // (PRD §10.3); instant under Reduce Motion.
            .animation(ElsepageTheme.Motion.moment(reduceMotion), value: model.state)
            .navigationTitle("今天")
            .navigationBarTitleDisplayMode(.large)
            .task { await model.reload() }
            .sheet(item: $reflection) { reflection in
                SessionReflectionSheet(model: reflection) { _ in
                    didSaveReflectionInSheet = true
                    Task { await model.reload() }
                }
            }
            .onChange(of: reflection?.id) { _, currentID in
                guard currentID == nil, let sessionID = presentedReflectionSessionID else { return }
                presentedReflectionSessionID = nil
                defer { didSaveReflectionInSheet = false }
                // Closing without saving counts as "今天先不了": the card stays
                // quiet for this session. Saving (or deleting afterwards) keeps
                // being derived from the reflections table, not this flag.
                if !didSaveReflectionInSheet {
                    model.dismissReflectionPrompt(for: sessionID)
                    Task { await model.reload() }
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .noCurrentBook:
            ContentUnavailableView("带一本书进来", systemImage: "books.vertical", description: Text("从书架导入 EPUB，今天就可以从一页开始。"))
                .transition(.moment(reduceMotion))
        case .continueReading(let book):
            todayCard(book: book, title: "今天，读一点就好。", action: "继续阅读") { openBook(book) }
        case .offerReflection(let book, let session):
            // 补写入口（PRD §6.1 未完成的 Reflection）：上一段有意义的阅读还没有
            // 留下想法。语气克制，不制造负罪感（PRD F4）。
            todayCard(book: book, title: "刚才读的，还没有留下想法。", action: "补写想法") {
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
                        // 补写 reopen the same session's discussion thread (FIX-01).
                        try? await model.library.sessionService.recordAgentDiscussion(id: sessionID)
                    }
                )
            }
        case .reflectionComplete(let book):
            todayCard(book: book, title: "今天已经留下来了。", action: "继续阅读") { openBook(book) }
        }
    }

    private func todayCard(book: Book, title: String, action: String, onTap: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.large) {
            Text(book.title).font(.system(.title3, design: .serif, weight: .semibold))
            Text(title).font(.title2).fixedSize(horizontal: false, vertical: true)
            Divider()
            streaksView
            Button(action, action: onTap)
                .buttonStyle(.borderedProminent)
                .tint(.elsepageAccent)
                // A11Y-03: AA label on the accent fill in both color schemes.
                .foregroundStyle(Color.elsepageOnAccent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ElsepageTheme.Spacing.xLarge)
        .background(ElsepageTheme.MaterialToken.chrome, in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.large, style: .continuous))
        .transition(.moment(reduceMotion))
    }

    private var streaksView: some View {
        // A11Y-01: at accessibility sizes the two capsules stack instead of
        // squeezing; ViewThatFits picks the first layout that fits.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: ElsepageTheme.Spacing.medium) {
                streakBadge(label: "连续阅读", days: model.readingStreak.days, emphasized: false)
                streakBadge(label: "连续思考", days: model.thinkingStreak.days, emphasized: true)
            }
            VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
                streakBadge(label: "连续阅读", days: model.readingStreak.days, emphasized: false)
                streakBadge(label: "连续思考", days: model.thinkingStreak.days, emphasized: true)
            }
        }
        // Streak 延续 (PRD §10.3): the day counter rolls over quietly.
        .animation(ElsepageTheme.Motion.moment(reduceMotion), value: model.readingStreak.days)
        .animation(ElsepageTheme.Motion.moment(reduceMotion), value: model.thinkingStreak.days)
    }

    private func streakBadge(label: String, days: Int, emphasized: Bool) -> some View {
        HStack(spacing: ElsepageTheme.Spacing.xSmall) {
            Image(systemName: emphasized ? "brain.head.profile" : "book")
                .accessibilityHidden(true)
            Text("\(label) \(days) 天")
                .font(emphasized ? .subheadline.weight(.semibold) : .footnote)
                .contentTransition(reduceMotion ? .identity : .numericText())
        }
        .foregroundStyle(emphasized ? Color.elsepageAccent : Color.secondary)
        .padding(.horizontal, emphasized ? ElsepageTheme.Spacing.medium : ElsepageTheme.Spacing.small)
        .padding(.vertical, ElsepageTheme.Spacing.xSmall)
        .background(
            emphasized ? Color.elsepageAccent.opacity(0.12) : Color.secondary.opacity(0.08),
            in: Capsule()
        )
        // A11Y-02: one element per badge — the decorative glyph stays silent.
        .accessibilityElement(children: .combine)
    }
}

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

    init(library: LibraryModel) { self.library = library }

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
                reflections: reflections
            )
            await refreshStreaks()
        } catch is CancellationError {
            return
        } catch {
            state = .continueReading(book)
        }
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
    let openBook: (Book) -> Void
    let openLibrary: () -> Void

    init(
        library: LibraryModel,
        openBook: @escaping (Book) -> Void,
        openLibrary: @escaping () -> Void
    ) {
        _model = State(initialValue: TodayModel(library: library))
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
            .navigationTitle("今天")
            .navigationBarTitleDisplayMode(.large)
            .task { await model.reload() }
            .sheet(item: $reflection) { reflection in
                SessionReflectionSheet(model: reflection) { _ in
                    Task { await model.reload() }
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .noCurrentBook:
            ContentUnavailableView("带一本书进来", systemImage: "books.vertical", description: Text("从书架导入 EPUB，今天就可以从一页开始。"))
        case .continueReading(let book):
            todayCard(book: book, title: "今天，读一点就好。", action: "继续阅读") { openBook(book) }
        case .offerReflection(let book, let session):
            todayCard(book: book, title: "刚才有什么东西，还留在脑子里吗？", action: "留下一点想法") {
                guard let locator = session.endLocator else { return }
                reflection = SessionReflectionModel(
                    book: book,
                    summary: SessionEndingSummary(session: session),
                    locator: locator,
                    reflectionRepository: model.library.reflectionRepository,
                    readerAgent: model.library.readerAgent,
                    makePolishService: model.library.makePolishService
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
            Button(action, action: onTap).buttonStyle(.borderedProminent).tint(.elsepageAccent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ElsepageTheme.Spacing.xLarge)
        .background(ElsepageTheme.MaterialToken.chrome, in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.large, style: .continuous))
    }

    private var streaksView: some View {
        HStack(spacing: ElsepageTheme.Spacing.medium) {
            streakBadge(label: "连续阅读", days: model.readingStreak.days, emphasized: false)
            streakBadge(label: "连续思考", days: model.thinkingStreak.days, emphasized: true)
        }
    }

    private func streakBadge(label: String, days: Int, emphasized: Bool) -> some View {
        HStack(spacing: ElsepageTheme.Spacing.xSmall) {
            Image(systemName: emphasized ? "brain.head.profile" : "book")
            Text("\(label) \(days) 天")
                .font(emphasized ? .subheadline.weight(.semibold) : .footnote)
        }
        .foregroundStyle(emphasized ? Color.elsepageAccent : Color.secondary)
        .padding(.horizontal, emphasized ? ElsepageTheme.Spacing.medium : ElsepageTheme.Spacing.small)
        .padding(.vertical, ElsepageTheme.Spacing.xSmall)
        .background(
            emphasized ? Color.elsepageAccent.opacity(0.12) : Color.secondary.opacity(0.08),
            in: Capsule()
        )
    }
}

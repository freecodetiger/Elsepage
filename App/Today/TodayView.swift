import LibraryCore
import Observation
import ReaderCore
import ReadingSessionCore
import ReflectionCore
import SwiftUI

@MainActor @Observable
final class TodayModel {
    enum State {
        case noBook
        case ready(Book)
        case reflectionAvailable(Book, SessionEndingSummary, BookLocator)
        case reflectionComplete(Book)
    }

    let library: LibraryModel
    private(set) var state: State = .noBook
    private(set) var isLoading = false

    init(library: LibraryModel) { self.library = library }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        await library.reload()
        guard let book = library.books.max(by: { ($0.lastOpenedAt ?? $0.importedAt) < ($1.lastOpenedAt ?? $1.importedAt) }) else {
            state = .noBook
            return
        }
        do {
            let reflections = try await library.reflectionRepository.reflections(for: book.id)
            let sessions = try await library.sessionRepository.sessions(for: book.id)
            if let session = sessions.first(where: { session in
                session.endedAt != nil && !reflections.contains(where: { $0.sessionID == session.id })
            }), let locator = session.endLocator {
                state = .reflectionAvailable(book, .init(session: session), locator)
            } else if reflections.contains(where: { Calendar.current.isDateInToday($0.createdAt) }) {
                state = .reflectionComplete(book)
            } else {
                state = .ready(book)
            }
        } catch is CancellationError {
            return
        } catch {
            state = .ready(book)
        }
    }
}

struct TodayView: View {
    @State private var model: TodayModel
    @State private var reflection: SessionReflectionModel?
    @State private var showsReflection = false
    let openLibrary: () -> Void

    init(library: LibraryModel, openLibrary: @escaping () -> Void) {
        _model = State(initialValue: TodayModel(library: library))
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
            .sheet(isPresented: $showsReflection) {
                if let reflection {
                    SessionReflectionSheet(model: reflection) { _ in Task { await model.reload() } }
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .noBook:
            ContentUnavailableView("带一本书进来", systemImage: "books.vertical", description: Text("从书架导入 EPUB，今天就可以从一页开始。"))
        case .ready(let book):
            todayCard(book: book, title: "读一点就好。", action: "去书架") { openLibrary() }
        case .reflectionAvailable(let book, let summary, let locator):
            todayCard(book: book, title: "刚才有什么东西，还留在脑子里吗？", action: "留下一点想法") {
                reflection = SessionReflectionModel(book: book, summary: summary, locator: locator, reflectionRepository: model.library.reflectionRepository)
                showsReflection = true
            }
        case .reflectionComplete(let book):
            todayCard(book: book, title: "今天已经留下来了。", action: "继续阅读") { openLibrary() }
        }
    }

    private func todayCard(book: Book, title: String, action: String, onTap: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.large) {
            Text(book.title).font(.system(.title3, design: .serif, weight: .semibold))
            Text(title).font(.title2).fixedSize(horizontal: false, vertical: true)
            Button(action, action: onTap).buttonStyle(.borderedProminent).tint(.elsepageAccent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ElsepageTheme.Spacing.xLarge)
        .background(ElsepageTheme.MaterialToken.chrome, in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.large, style: .continuous))
    }
}

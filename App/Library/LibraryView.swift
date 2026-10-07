import AchievementCore
import AppInfrastructure
import LibraryCore
import ReadingSessionCore
import ReflectionCore
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Bindable var model: LibraryModel
    @Bindable var settings: SettingsRootModel
    let achievements: AchievementModel?
    @State private var nextActionModel: LibraryNextActionModel
    @State private var importing = false
    @State private var showsSettings = false
    @State private var selectedBook: Book?
    @State private var deletingBook: Book?
    @State private var reflection: SessionReflectionModel?
    @State private var presentedReflectionSessionID: ReadingSessionID?
    @State private var didSaveReflectionInSheet = false
    @Namespace private var bookTransitionNamespace

    init(
        model: LibraryModel,
        settings: SettingsRootModel,
        achievements: AchievementModel? = nil
    ) {
        self.model = model
        self.settings = settings
        self.achievements = achievements
        _nextActionModel = State(initialValue: LibraryNextActionModel(library: model))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.elsepageBackground.ignoresSafeArea()
                if model.books.isEmpty { emptyLibrary } else { bookList(model) }
            }
            .navigationTitle("书架")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Menu {
                        Picker("排序", selection: $model.sortOrder) {
                            ForEach(LibrarySortOrder.allCases) { order in
                                Text(order.title).tag(order)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("排序书架")
                    // 导入与排序同风格的原生工具栏按钮;导入中显示进度圈。
                    if model.isImporting {
                        ProgressView().accessibilityLabel("正在导入 EPUB")
                    } else {
                        Button { importing = true } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .accessibilityLabel("导入 EPUB")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType.epub], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task {
                        _ = await model.importBook(url)
                        await nextActionModel.reload()
                    }
                }
            }
            .sheet(isPresented: $showsSettings) {
                SettingsView(model: settings)
            }
            .sheet(item: $reflection) { reflection in
                SessionReflectionSheet(model: reflection) { _ in
                    didSaveReflectionInSheet = true
                    Task {
                        await model.reload()
                        await nextActionModel.reload()
                    }
                }
            }
            .onChange(of: reflection?.id) { _, currentID in
                guard currentID == nil, let sessionID = presentedReflectionSessionID else { return }
                presentedReflectionSessionID = nil
                defer { didSaveReflectionInSheet = false }
                if !didSaveReflectionInSheet {
                    nextActionModel.dismissReflectionPrompt(for: sessionID)
                    Task { await nextActionModel.reload() }
                }
            }
            .navigationDestination(item: $selectedBook) { book in
                ReaderScreen(
                    model: model.readerModel(for: book),
                    openingCover: model.cover(for: book)
                ) {
                    Task {
                        await model.reload()
                        await nextActionModel.reload()
                    }
                }
                .modifier(
                    BookZoomNavigationTransition(
                        sourceID: book.id,
                        namespace: bookTransitionNamespace
                    )
                )
            }
            .searchable(text: $model.searchQuery, prompt: "搜索书名或作者")
            .alert("导入失败", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("好") {} } message: { Text(model.errorMessage ?? "") }
            .alert("这本书已经在书库中", isPresented: Binding(get: { model.duplicateTitle != nil }, set: { if !$0 { model.duplicateTitle = nil } })) { Button("好") {} } message: { Text(model.duplicateTitle ?? "") }
            .alert("从书架移除这本书？", isPresented: Binding(
                get: { deletingBook != nil },
                set: { if !$0 { deletingBook = nil } }
            )) {
                Button("取消", role: .cancel) { deletingBook = nil }
                Button("移除", role: .destructive) {
                    guard let book = deletingBook else { return }
                    deletingBook = nil
                    Task { await model.delete(book) }
                }
            } message: {
                Text("会删除本机 EPUB、阅读位置和全部标注，无法恢复。")
            }
            .safeAreaInset(edge: .bottom) {
                if model.isImporting { importStatus }
            }
            .task {
                await model.reload()
                await nextActionModel.reload()
            }
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: ElsepageTheme.Spacing.large) {
            Image(systemName: "books.vertical")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.elsepageInteractive)
                .accessibilityHidden(true)
            VStack(spacing: ElsepageTheme.Spacing.small) {
                Text("带一本书进来")
                    .font(ElsepageTheme.Typography.emptyStateTitle)
                Text("从“文件”导入无 DRM 的 EPUB。\n没有网络或 AI，也可以安静地读完它。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("导入 EPUB") { importing = true }
                .buttonStyle(.borderedProminent)
                .tint(.elsepageInteractive)
                // A11Y-03: AA label on the accent fill in both color schemes.
                .foregroundStyle(Color.elsepageOnInteractive)
                .disabled(model.isImporting)
        }
        .padding(ElsepageTheme.Spacing.xLarge)
    }

    private var importStatus: some View {
        HStack(spacing: ElsepageTheme.Spacing.small) {
            ProgressView()
            Text("正在导入 EPUB…").font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, ElsepageTheme.Spacing.medium)
        .padding(.vertical, ElsepageTheme.Spacing.small)
        .background(Color.elsepageSurface, in: Capsule())
        .overlay(Capsule().stroke(Color.elsepageBorder))
        .padding(.bottom, ElsepageTheme.Spacing.small)
        .accessibilityElement(children: .combine)
    }

    private func bookList(_ model: LibraryModel) -> some View {
        // The grid needs its available width to size covers explicitly.
        GeometryReader { proxy in
            ScrollView {
                if model.visibleBooks.isEmpty {
                    ContentUnavailableView.search(text: model.searchQuery)
                        .frame(maxWidth: .infinity, minHeight: 260)
                        .padding(ElsepageTheme.Spacing.page)
                } else {
                    LibraryGridView(
                        books: model.visibleBooks,
                        cover: { model.cover(for: $0) },
                        progress: { model.progress(for: $0) },
                        statusLine: { statusLine(for: $0) },
                        pendingReflectionBookID: nextActionModel.pendingReflection?.book.id,
                        transitionNamespace: bookTransitionNamespace,
                        openBook: { selectedBook = $0 },
                        loadCover: { await model.loadCover(for: $0) },
                        writeReflection: { _ in presentReflection() },
                        requestDelete: { deletingBook = $0 },
                        accessibilityLabel: { accessibilityLabel(for: $0) },
                        containerWidth: proxy.size.width
                    )
                }
            }
        }
        .refreshable {
            await model.reload()
            await nextActionModel.reload()
        }
        // The index is only consulted for the book on the desk, and only once
        // per book; the chapter is presentation data, never a blocking load.
        .task(id: model.currentBook?.id) {
            guard let book = model.currentBook else { return }
            await model.loadChapterTitle(for: book)
        }
    }

    /// One quiet line under a card. The book you are reading says where you are;
    /// every other book says what it has accumulated. A fresh book says nothing
    /// rather than "0%".
    private func statusLine(for book: Book) -> String? {
        if book.id == model.currentBook?.id {
            if let chapter = model.chapterTitles[book.id], !chapter.isEmpty { return chapter }
            // Opened before but no chapter resolved — still the book you would
            // resume. Never opened: fall through to the statistics.
            if book.lastOpenedAt != nil { return "继续阅读中" }
        }
        return model.statsLine(for: book)
    }

    private func accessibilityLabel(for book: Book) -> String {
        LibraryBookAccessibility.label(
            title: book.title,
            author: book.author,
            statsLine: model.statsLine(for: book),
            progress: model.progress(for: book)
        )
    }

    /// Presents the reflection the reader offered at the end of a session and
    /// the user has not written yet. Moving off the shelf without saving counts
    /// as "今天先不了" — see the dismissal store.
    private func presentReflection() {
        guard let pending = nextActionModel.pendingReflection,
              let locator = pending.session.endLocator else { return }
        didSaveReflectionInSheet = false
        presentedReflectionSessionID = pending.session.id
        reflection = SessionReflectionModel(
            book: pending.book,
            summary: SessionEndingSummary(session: pending.session),
            locator: locator,
            reflectionRepository: model.reflectionRepository,
            readerAgent: model.readerAgent,
            makePolishService: model.makePolishService,
            achievements: achievements,
            recordAgentDiscussion: { sessionID in
                try? await model.sessionService.recordAgentDiscussion(id: sessionID)
            }
        )
    }
}

/// Applies the native iOS 18 zoom transition to the Reader destination.
/// Reduce Motion keeps the normal navigation transition instead.
private struct BookZoomNavigationTransition<ID: Hashable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let sourceID: ID
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        }
    }
}

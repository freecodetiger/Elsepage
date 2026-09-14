import AchievementCore
import AppInfrastructure
import LibraryCore
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Bindable var model: LibraryModel
    @Bindable var settings: SettingsRootModel
    let achievements: AchievementModel?
    @State private var nextActionModel: LibraryNextActionModel
    @State private var displayMode: LibraryDisplayMode = .spines
    @State private var importing = false
    @State private var showsSettings = false
    @State private var selectedBook: Book?
    @State private var deletingBook: Book?
    /// A11Y-01: the grid collapses to one readable column at accessibility
    /// Dynamic Type sizes instead of squeezing titles into half-width cells.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                        Divider()
                        Picker("显示", selection: $displayMode) {
                            ForEach(LibraryDisplayMode.allCases) { mode in
                                Text(mode.title).tag(mode)
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
            .navigationDestination(item: $selectedBook) { book in
                ReaderScreen(model: model.readerModel(for: book)) {
                    Task {
                        await model.reload()
                        await nextActionModel.reload()
                    }
                }
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
        ScrollView {
            VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.xLarge) {
                if model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let currentBook = model.currentBook {
                    LibraryCurrentReadingDeskView(
                        model: nextActionModel,
                        book: currentBook,
                        progress: model.progress(for: currentBook),
                        cover: model.cover(for: currentBook),
                        achievements: achievements,
                        openBook: { selectedBook = currentBook },
                        onSaved: {
                            Task {
                                await model.reload()
                                await nextActionModel.reload()
                            }
                        }
                    )
                    .task(id: currentBook.id) {
                        await model.loadCover(for: currentBook)
                    }
                }

                let shelfBooks = model.visibleBooks.filter { candidate in
                    guard model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          let currentBook = model.currentBook else { return true }
                    return candidate.id != currentBook.id
                }

                if shelfBooks.isEmpty {
                    if model.visibleBooks.isEmpty {
                        ContentUnavailableView.search(text: model.searchQuery)
                            .frame(maxWidth: .infinity, minHeight: 260)
                    }
                } else {
                    LibraryShelfView(
                        books: shelfBooks,
                        mode: displayMode,
                        cover: { model.cover(for: $0) },
                        progress: { model.progress(for: $0) },
                        openBook: { selectedBook = $0 },
                        loadCover: { await model.loadCover(for: $0) }
                    )
                }
            }
            .padding(ElsepageTheme.Spacing.page)
        }
    }

    private func metadata(for book: Book) -> String {
        if let author = book.author, !author.isEmpty { return author }
        return "未知作者"
    }

    private func accessibilityLabel(for book: Book) -> String {
        LibraryBookAccessibility.label(
            title: book.title,
            author: book.author,
            statsLine: model.statsLine(for: book),
            progress: model.progress(for: book)
        )
    }
}

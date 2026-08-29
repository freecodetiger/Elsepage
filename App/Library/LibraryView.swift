import AppInfrastructure
import LibraryCore
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Bindable var model: LibraryModel
    @Bindable var settings: SettingsRootModel
    let onReflectionSaved: () -> Void
    @State private var importing = false
    @State private var showsSettings = false
    @State private var selectedBook: Book?
    @State private var deletingBook: Book?
    /// A11Y-01: the grid collapses to one readable column at accessibility
    /// Dynamic Type sizes instead of squeezing titles into half-width cells.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(model: LibraryModel, settings: SettingsRootModel, onReflectionSaved: @escaping () -> Void = {}) {
        self.model = model
        self.settings = settings
        self.onReflectionSaved = onReflectionSaved
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
                if case .success(let urls) = result, let url = urls.first { Task { await model.importBook(url) } }
            }
            .sheet(isPresented: $showsSettings) {
                SettingsView(model: settings)
            }
            .navigationDestination(item: $selectedBook) { book in
                ReaderScreen(model: model.readerModel(for: book), onReflectionSaved: onReflectionSaved)
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
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: ElsepageTheme.Spacing.large) {
            Image(systemName: "books.vertical")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.elsepageAccent)
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
                .tint(.elsepageAccent)
                // A11Y-03: AA label on the accent fill in both color schemes.
                .foregroundStyle(Color.elsepageOnAccent)
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
        .background(ElsepageTheme.MaterialToken.chrome, in: Capsule())
        .padding(.bottom, ElsepageTheme.Spacing.small)
        .accessibilityElement(children: .combine)
    }

    private func bookList(_ model: LibraryModel) -> some View {
        GeometryReader { geometry in
            let columnCount = LibraryGridLayout.columnCount(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
            let columnWidth = LibraryGridLayout.columnWidth(
                containerWidth: geometry.size.width,
                horizontalPadding: ElsepageTheme.Spacing.page,
                columnSpacing: ElsepageTheme.Spacing.medium,
                columnCount: columnCount
            )

            if model.visibleBooks.isEmpty {
                // 书架搜索无结果：明确但不责备。
                ContentUnavailableView.search(text: model.searchQuery)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    // Fixed columns prevent SwiftUI from using a cover's ideal width
                    // during grid measurement. Every cell gets the same finite width.
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.fixed(columnWidth), spacing: ElsepageTheme.Spacing.medium),
                            count: columnCount
                        ),
                        spacing: ElsepageTheme.Spacing.xLarge
                    ) {
                ForEach(model.visibleBooks) { book in
                    Button { selectedBook = book } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            // Keep the geometry independent from the source image's
                            // aspect ratio. Wide EPUB covers are cropped inside this
                            // fixed 2:3 portrait frame instead of expanding the cell.
                            ZStack {
                                Color.clear
                                ElsepageBookCover(
                                    image: model.cover(for: book),
                                    title: book.title,
                                    author: book.author,
                                    seed: Int(book.id.rawValue.uuid.0)
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .frame(
                                width: columnWidth,
                                height: columnWidth / LibraryGridLayout.coverAspectRatio
                            )
                            .aspectRatio(LibraryGridLayout.coverAspectRatio, contentMode: .fit)
                            .task(id: book.id) { await model.loadCover(for: book) }
                            Text(book.title)
                                .font(ElsepageTheme.Typography.itemTitle)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text(metadata(for: book))
                                .font(ElsepageTheme.Typography.metadata)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            // Quiet card statistics (PRD §6.2): omitted entirely
                            // until a book has reading time or annotations.
                            if let statsLine = model.statsLine(for: book) {
                                Text(statsLine)
                                    .font(ElsepageTheme.Typography.metadata)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            if let progress = model.progress(for: book) {
                                ProgressView(value: progress)
                                    .tint(.elsepageAccent)
                                    .accessibilityLabel("阅读进度")
                                    .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
                            }
                        }
                        .frame(width: columnWidth, alignment: .leading)
                        .clipped()
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(for: book))
                    .accessibilityHint("打开并继续阅读")
                    .contextMenu {
                        Button(role: .destructive) { deletingBook = book } label: {
                            Label("从书架移除", systemImage: "trash")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: columnWidth, alignment: .leading)
                }
                }
                .padding(ElsepageTheme.Spacing.page)
                }
            }
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

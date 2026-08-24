import LibraryCore
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Bindable var model: LibraryModel
    @State private var importing = false
    @State private var selectedBook: Book?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.elsepageBackground.ignoresSafeArea()
                if model.books.isEmpty { emptyLibrary } else { bookList(model) }
            }
            .navigationTitle("书架")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if model.isImporting {
                        ProgressView().accessibilityLabel("正在导入 EPUB")
                    } else {
                        ElsepageIconButton(systemName: "plus", accessibilityLabel: "导入 EPUB") { importing = true }
                    }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType.epub], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first { Task { await model.importBook(url) } }
            }
            .navigationDestination(item: $selectedBook) { book in
                ReaderScreen(model: model.readerModel(for: book))
            }
            .alert("导入失败", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("好") {} } message: { Text(model.errorMessage ?? "") }
            .alert("这本书已经在书库中", isPresented: Binding(get: { model.duplicateTitle != nil }, set: { if !$0 { model.duplicateTitle = nil } })) { Button("好") {} } message: { Text(model.duplicateTitle ?? "") }
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
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: ElsepageTheme.Spacing.medium)], spacing: ElsepageTheme.Spacing.xLarge) {
                ForEach(model.books) { book in
                    Button { selectedBook = book } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            ElsepageBookCover(title: book.title, author: book.author, seed: Int(book.id.rawValue.uuid.0))
                                .aspectRatio(0.7, contentMode: .fit)
                            Text(book.title)
                                .font(ElsepageTheme.Typography.itemTitle)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text(metadata(for: book))
                                .font(ElsepageTheme.Typography.metadata)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(for: book))
                    .accessibilityHint("打开并继续阅读")
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
        "\(book.title)，\(metadata(for: book))"
    }
}

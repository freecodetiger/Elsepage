import LibraryCore
import SwiftUI
import UniformTypeIdentifiers

enum ElsepageTheme {
    enum Spacing {
        static let xSmall: CGFloat = 6
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
        static let xLarge: CGFloat = 28
        static let page: CGFloat = 20
    }

    enum Radius {
        static let small: CGFloat = 12
        static let large: CGFloat = 24
    }

    enum Motion {
        static let quick = Animation.easeInOut(duration: 0.18)
    }
}

extension ShapeStyle where Self == Color {
    static var elsepageBackground: Color {
        Color(light: UIColor(red: 0.969, green: 0.965, blue: 0.949, alpha: 1), dark: UIColor(red: 0.075, green: 0.078, blue: 0.071, alpha: 1))
    }

    static var elsepageSurface: Color {
        Color(light: UIColor(red: 0.992, green: 0.988, blue: 0.976, alpha: 1), dark: UIColor(red: 0.125, green: 0.129, blue: 0.118, alpha: 1))
    }

    static var elsepageAccent: Color {
        Color(light: UIColor(red: 0.373, green: 0.431, blue: 0.373, alpha: 1), dark: UIColor(red: 0.61, green: 0.69, blue: 0.60, alpha: 1))
    }

    static var elsepageReaderSepia: Color {
        Color(light: UIColor(red: 0.965, green: 0.945, blue: 0.902, alpha: 1), dark: UIColor(red: 0.14, green: 0.13, blue: 0.105, alpha: 1))
    }
}

private extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

struct ElsepageIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 42, height: 42)
                .background(.thinMaterial, in: Circle())
                .overlay(Circle().stroke(.primary.opacity(0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct ElsepageBookCover: View {
    let title: String
    let author: String?
    let seed: Int

    private var palette: [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.25, green: 0.29, blue: 0.25), Color(red: 0.39, green: 0.45, blue: 0.38)],
            [Color(red: 0.36, green: 0.22, blue: 0.18), Color(red: 0.57, green: 0.37, blue: 0.30)],
            [Color(red: 0.31, green: 0.29, blue: 0.20), Color(red: 0.49, green: 0.46, blue: 0.34)],
            [Color(red: 0.21, green: 0.28, blue: 0.29), Color(red: 0.38, green: 0.47, blue: 0.47)]
        ]
        return palettes[abs(seed) % palettes.count]
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.xSmall) {
                Text(title)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .lineLimit(4)
                if let author, !author.isEmpty {
                    Text(author).font(.caption2).opacity(0.72).lineLimit(2)
                }
            }
            .foregroundStyle(.white)
            .padding(ElsepageTheme.Spacing.medium)
        }
        .clipShape(RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous))
        .shadow(color: .black.opacity(0.17), radius: 10, y: 6)
        .accessibilityHidden(true)
    }
}

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
                    ElsepageIconButton(systemName: "plus", accessibilityLabel: "导入 EPUB") { importing = true }
                        .disabled(model.isImporting)
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
                    .font(.system(.title2, design: .serif, weight: .semibold))
                Text("从“文件”导入无 DRM 的 EPUB。\n没有网络或 AI，也可以安静地读完它。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("导入 EPUB") { importing = true }
                .buttonStyle(.borderedProminent)
                .tint(.elsepageAccent)
        }
        .padding(ElsepageTheme.Spacing.xLarge)
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
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text(metadata(for: book))
                                .font(.caption)
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

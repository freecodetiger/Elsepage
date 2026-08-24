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
                Color(uiColor: .secondarySystemBackground).ignoresSafeArea()
                if model.books.isEmpty { emptyLibrary } else { bookList(model) }
            }
            .navigationTitle("我的书架")
            .toolbar {
                Button("导入", systemImage: "plus") { importing = true }
                    .disabled(model.isImporting)
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
        ContentUnavailableView {
            Label("带一本书进来", systemImage: "books.vertical.fill")
        } description: {
            Text("从“文件”导入无 DRM 的 EPUB。阅读不需要网络或 AI。")
        } actions: {
            Button("导入 EPUB") { importing = true }.buttonStyle(.borderedProminent)
        }
    }

    private func bookList(_ model: LibraryModel) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 20)], spacing: 24) {
                ForEach(model.books) { book in
                    Button { selectedBook = book } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            ZStack(alignment: .bottomLeading) {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.indigo.opacity(0.9), Color.blue.opacity(0.55)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .aspectRatio(0.7, contentMode: .fit)
                                    .shadow(color: .black.opacity(0.16), radius: 8, y: 5)
                                Text(book.title)
                                    .font(.system(.headline, design: .serif, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(4)
                                    .padding(14)
                            }
                            Text(book.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text(book.author ?? "未知作者")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
    }
}

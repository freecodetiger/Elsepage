import LibraryCore
import RetrievalCore
import SwiftUI

/// Per-book RAG progress page: index state, lexical + semantic progress, last
/// error, and per-book actions (重新语义索引 / 重建索引).
struct RAGManagementView: View {
    @Bindable var model: RAGManagementModel

    var body: some View {
        Group {
            if model.isLoading && model.statuses.isEmpty {
                ProgressView("正在读取检索状态…")
            } else if model.statuses.isEmpty {
                ContentUnavailableView(
                    "还没有书籍",
                    systemImage: "books.vertical",
                    description: Text("导入 EPUB 后，这里会显示每本书的检索进度。")
                )
            } else {
                List(model.statuses) { status in
                    statusRow(status)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("检索 (RAG)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.reload() }
        .refreshable { await model.reload() }
        .alert("暂时无法完成操作", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) { Button("好") {} } message: { Text(model.errorMessage ?? "") }
    }

    private func statusRow(_ status: BookIndexStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(status.title).font(.headline).lineLimit(1)
                Spacer()
                badge(status.state)
            }
            if status.totalChunks > 0 {
                ProgressView(value: status.semanticFraction)
                    .tint(.elsepageAccent)
                    .accessibilityLabel("语义索引进度")
                    .accessibilityValue(Text(semanticLabel(status)))
                Text(semanticLabel(status)).font(.caption).foregroundStyle(.secondary)
            }
            if status.totalResources > 0, status.state != .ready {
                ProgressView(value: status.lexicalFraction)
                    .tint(.secondary)
                    .accessibilityLabel("词法索引进度")
                    .accessibilityValue(Text("词法索引 \(min(status.nextResourceOrdinal, status.totalResources))/\(status.totalResources)"))
                Text("词法索引 \(min(status.nextResourceOrdinal, status.totalResources))/\(status.totalResources)")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            if let error = status.lastError {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
            }
            HStack(spacing: 16) {
                Button("重新语义索引") { model.reembed(status.bookID) }
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                Button("重建索引", role: .destructive) {
                    Task { await model.reindex(status.bookID) }
                }
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .font(.footnote)
        }
        .padding(.vertical, 4)
    }

    private func semanticLabel(_ status: BookIndexStatus) -> String {
        let count = "\(min(status.embeddedCount, status.totalChunks))/\(status.totalChunks)"
        switch status.state {
        case .embedding: return "语义索引中 \(count)"
        case .ready: return "语义索引 \(count)\(status.embeddingModel.map { " · \($0)" } ?? "")"
        case .lexicalReady: return "词法就绪，语义待索引 \(count)"
        default: return "语义索引 \(count)"
        }
    }

    @ViewBuilder private func badge(_ state: BookIndexState) -> some View {
        let (text, color): (String, Color) = switch state {
        case .pending: ("等待中", Color.secondary)
        case .extracting: ("提取中", Color.blue)
        case .lexicalReady: ("词法就绪", Color.teal)
        case .embedding: ("语义索引中", Color.elsepageAccent)
        case .ready: ("就绪", Color.green)
        case .failed: ("失败", Color.red)
        }
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

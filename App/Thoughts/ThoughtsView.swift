import ReflectionCore
import SwiftUI

struct ThoughtsView: View {
    @Bindable var model: ThoughtsModel

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading && model.entries.isEmpty {
                    ProgressView("正在整理你的想法…")
                } else if model.entries.isEmpty {
                    ContentUnavailableView(
                        "还没有留下想法",
                        systemImage: "quote.bubble",
                        description: Text("结束一次阅读后，写下一点真正留下来的东西。它会先安静地保存在本机。")
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: ElsepageTheme.Spacing.medium) {
                            ForEach(model.entries) { entry in
                                ThoughtEntryCard(entry: entry)
                            }
                        }
                        .padding(ElsepageTheme.Spacing.page)
                    }
                    .refreshable { await model.reload() }
                }
            }
            .background(Color.elsepageBackground)
            .navigationTitle("思想")
            .navigationBarTitleDisplayMode(.large)
            .task { await model.reload() }
            .alert("暂时无法读取思想档案", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("好") {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }
}

private struct ThoughtEntryCard: View {
    let entry: ReflectionArchiveEntry

    var body: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.medium) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.book.title)
                    .font(.system(.subheadline, design: .serif, weight: .semibold))
                Text(entry.reflection.createdAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("我说的")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.elsepageAccent)
                Text(entry.reflection.originalText)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let response = entry.derivedAgentResponse {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("回应")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(response.content)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(ElsepageTheme.Spacing.medium)
        .background(ElsepageTheme.MaterialToken.chrome, in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ElsepageTheme.Radius.large, style: .continuous)
                .stroke(.primary.opacity(0.06))
        }
    }
}

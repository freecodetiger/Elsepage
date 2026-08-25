import LibraryCore
import ReaderCore
import ReflectionCore
import SwiftUI

struct ThoughtsView: View {
    @Bindable var model: ThoughtsModel
    @Bindable var providerSettings: ProviderSettingsModel
    @State private var showsProviderSettings = false
    let openSource: (Book, BookLocator) -> Void

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
                                ThoughtEntryCard(
                                    entry: entry,
                                    isReplying: model.replyingTo == entry.reflection.id,
                                    requestReply: {
                                        if providerSettings.hasSavedKey {
                                            Task { await model.requestAgentReply(for: entry.reflection) }
                                        } else {
                                            showsProviderSettings = true
                                        }
                                    },
                                    openSource: openSource
                                )
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsProviderSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("AI Provider 设置")
                }
            }
            .task { await model.reload() }
            .sheet(isPresented: $showsProviderSettings) {
                ProviderSettingsView(model: providerSettings)
            }
            .alert("暂时无法完成操作", isPresented: Binding(
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
    let isReplying: Bool
    let requestReply: () -> Void
    let openSource: (Book, BookLocator) -> Void

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
            } else {
                Divider()
                Button(action: requestReply) {
                    if isReplying {
                        Label("正在回应…", systemImage: "ellipsis.bubble")
                    } else {
                        Label("请 Agent 回应", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isReplying)
            }
            if !entry.messages.isEmpty {
                ForEach(entry.messages.filter { $0.id != entry.derivedAgentResponse?.id }) { message in
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message.author == .user ? "继续说" : "回应")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(message.content).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let connection = entry.connections.first {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("过去的你")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.elsepageAccent)
                    Text(connection.sourceReflection.originalText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    if let locator = connection.sourceLocator {
                        Button("回到《\(connection.sourceBook.title)》") {
                            openSource(connection.sourceBook, locator)
                        }
                        .font(.footnote.weight(.medium))
                    }
                }
            }
            if let locator = entry.sourceLocator {
                Divider()
                Button("回到原文") { openSource(entry.book, locator) }
                    .font(.footnote.weight(.medium))
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

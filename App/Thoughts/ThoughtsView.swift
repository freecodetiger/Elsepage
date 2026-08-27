import ContextRouting
import LibraryCore
import ReaderCore
import ReflectionCore
import SwiftUI

struct ThoughtsView: View {
    @Bindable var model: ThoughtsModel
    @Bindable var settings: SettingsRootModel
    @State private var showsSettings = false
    @State private var searchText = ""
    @State private var viewMode: ThoughtsViewMode = .timeline
    @State private var filter: ThoughtsArchiveFilter = .all
    @State private var expandedEntryID: ReflectionID?
    let openSource: (Book, BookLocator) -> Void

    private var visibleEntries: [ReflectionArchiveEntry] {
        ThoughtsArchiveProjection.entries(model.entries, matching: searchText, filter: filter)
    }

    private var visibleJournalEntries: [JournalEntry] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return model.journalEntries }
        return model.journalEntries.filter { entry in
            entry.book.title.localizedCaseInsensitiveContains(term)
                || entry.reflection.displayText.localizedCaseInsensitiveContains(term)
                || entry.reflection.originalText.localizedCaseInsensitiveContains(term)
                || entry.whatIThink.contains { $0.thought.localizedCaseInsensitiveContains(term) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading && model.entries.isEmpty {
                    ProgressView("正在整理你的想法…")
                } else if model.entries.isEmpty {
                    emptyArchive
                } else {
                    archive
                }
            }
            .background(Color.elsepageBackground)
            .navigationTitle("思想")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "搜索想法、书名或回应")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                }
            }
            .task { await model.reload() }
            .sheet(isPresented: $showsSettings) {
                SettingsView(model: settings)
            }
            .alert("暂时无法完成操作", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("好") {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .onChange(of: searchText) { expandedEntryID = nil }
            .onChange(of: filter) { expandedEntryID = nil }
            .onChange(of: viewMode) { expandedEntryID = nil }
        }
    }

    private var emptyArchive: some View {
        ContentUnavailableView(
            "还没有留下想法",
            systemImage: "quote.bubble",
            description: Text("结束一次阅读后，写下一点真正留下来的东西。它会先安静地保存在本机。")
        )
    }

    private var archive: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ElsepageTheme.Spacing.large) {
                controls
                if viewMode == .journal {
                    if visibleJournalEntries.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .frame(maxWidth: .infinity)
                            .padding(.top, ElsepageTheme.Spacing.xLarge)
                    } else {
                        journalSections
                    }
                } else if visibleEntries.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, ElsepageTheme.Spacing.xLarge)
                } else if viewMode == .timeline {
                    timelineSections
                } else {
                    bookSections
                }
            }
            .padding(ElsepageTheme.Spacing.page)
        }
        .refreshable { await model.reload() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
            Picker("查看方式", selection: $viewMode) {
                ForEach(ThoughtsViewMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ElsepageTheme.Spacing.small) {
                    ForEach(ThoughtsArchiveFilter.allCases, id: \.self) { option in
                        Button(option.title) { filter = option }
                            .buttonStyle(.bordered)
                            .tint(filter == option ? .elsepageAccent : .secondary)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var timelineSections: some View {
        ForEach(ThoughtsArchiveProjection.monthSections(visibleEntries)) { section in
            archiveSection(
                title: section.month.formatted(.dateTime.year().month(.wide)),
                subtitle: "\(section.entries.count) 条"
            ) {
                entryCards(section.entries, showsBook: true)
            }
        }
    }

    private var bookSections: some View {
        ForEach(ThoughtsArchiveProjection.bookSections(visibleEntries)) { section in
            archiveSection(
                title: section.book.title,
                subtitle: "\(section.entries.count) 条想法"
            ) {
                entryCards(section.entries, showsBook: false)
            }
        }
    }

    // MARK: - Journal

    /// New structured Journal path. The archive projection above is untouched so
    /// the concurrent Citation/Router tasks can keep editing it; the final
    /// "which view is default" toggle is left for the coordinator to decide.
    private var journalSections: some View {
        LazyVStack(alignment: .leading, spacing: ElsepageTheme.Spacing.medium) {
            ForEach(visibleJournalEntries) { entry in
                JournalEntryCard(entry: entry, openSource: openSource)
            }
        }
    }

    private func archiveSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(.headline, design: .serif, weight: .semibold))
                Spacer()
                Text(subtitle).font(.caption).foregroundStyle(.tertiary)
            }
            content()
        }
    }

    private func entryCards(_ entries: [ReflectionArchiveEntry], showsBook: Bool) -> some View {
        ForEach(entries) { entry in
            ThoughtEntryCard(
                entry: entry,
                isExpanded: expandedEntryID == entry.id,
                showsBook: showsBook,
                isReplying: model.replyingTo == entry.reflection.id,
                contextTrace: model.tracesByReflection[entry.reflection.id],
                toggleExpanded: {
                    withAnimation(.snappy(duration: 0.24)) {
                        expandedEntryID = expandedEntryID == entry.id ? nil : entry.id
                    }
                },
                requestReply: {
                    if settings.hasSavedKey {
                        Task { await model.requestAgentReply(for: entry.reflection) }
                    } else {
                        showsSettings = true
                    }
                },
                openSource: openSource
            )
        }
    }
}

private enum ThoughtsViewMode: String, CaseIterable, Identifiable {
    case timeline
    case books
    case journal

    var id: String { rawValue }
    var title: String {
        switch self {
        case .timeline: "时间"
        case .books: "书籍"
        case .journal: "日志"
        }
    }
    var systemImage: String {
        switch self {
        case .timeline: "calendar"
        case .books: "books.vertical"
        case .journal: "book.closed"
        }
    }
}

private extension ThoughtsArchiveFilter {
    var title: String {
        switch self {
        case .all: "全部"
        case .hasAgentResponse: "有回应"
        case .hasConnection: "有连接"
        }
    }
}

private struct ThoughtEntryCard: View {
    let entry: ReflectionArchiveEntry
    let isExpanded: Bool
    let showsBook: Bool
    let isReplying: Bool
    var contextTrace: ContextPlanTrace?
    let toggleExpanded: () -> Void
    let requestReply: () -> Void
    let openSource: (Book, BookLocator) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.medium) {
            Button(action: toggleExpanded) {
                VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
                    metadata
                    Text(entry.reflection.displayText)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(isExpanded ? nil : 3)
                    if !isExpanded { compactStatus }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "收起想法" : "展开想法")

            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(ElsepageTheme.Spacing.medium)
        .background(ElsepageTheme.MaterialToken.chrome, in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous)
                .stroke(.primary.opacity(isExpanded ? 0.10 : 0.05))
        }
    }

    private var metadata: some View {
        HStack(alignment: .firstTextBaseline, spacing: ElsepageTheme.Spacing.small) {
            if showsBook {
                Text(entry.book.title)
                    .font(.system(.subheadline, design: .serif, weight: .semibold))
                    .lineLimit(1)
            }
            Text(entry.reflection.createdAt, format: .dateTime.month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private var compactStatus: some View {
        HStack(spacing: ElsepageTheme.Spacing.medium) {
            if entry.derivedAgentResponse != nil {
                Label("有回应", systemImage: "sparkles")
            }
            if !entry.connections.isEmpty {
                Label("连接过去", systemImage: "link")
            }
            let discussionCount = entry.messages.filter { $0.author == .user }.count
            if discussionCount > 0 {
                Label("\(discussionCount) 次讨论", systemImage: "bubble.left.and.bubble.right")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var expandedContent: some View {
        if let response = entry.derivedAgentResponse {
            Divider()
            responseBlock(title: "回应", message: response)
            if let line = contextDisclosureLine(contextTrace) {
                Divider()
                Label(line, systemImage: "doc.text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        } else {
            Divider()
            Button(action: requestReply) {
                Label(isReplying ? "正在回应…" : "请 Agent 回应", systemImage: "sparkles")
            }
            .buttonStyle(.bordered)
            .disabled(isReplying)
        }

        ForEach(entry.messages.filter { $0.id != entry.derivedAgentResponse?.id }) { message in
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text(message.author == .user ? "继续说" : "回应")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if message.author == .agent {
                    AgentMarkdownText(
                        content: message.content,
                        provenance: entry.responseProvenance[message.id] ?? .init(evidence: [], citations: []),
                        openCitation: openEvidence
                    ).font(.subheadline)
                } else {
                    Text(message.content).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        if let connection = entry.connections.first {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Label("过去的你", systemImage: "link")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.elsepageAccent)
                Text(connection.sourceReflection.originalText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
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

    private func responseBlock(title: String, message: ReflectionMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            AgentMarkdownText(
                content: message.content,
                provenance: entry.responseProvenance[message.id] ?? .init(evidence: [], citations: []),
                openCitation: openEvidence
            )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let provenance = entry.responseProvenance[message.id], !provenance.evidence.isEmpty {
                DisclosureGroup("查看本次使用的上下文") {
                    ForEach(provenance.evidence) { evidence in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(evidence.title ?? "阅读证据").font(.caption.weight(.semibold))
                            Text(evidence.excerpt).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                            if evidence.locator != nil {
                                Button("回到原文") { openEvidence(evidence) }.font(.caption)
                            }
                        }.padding(.vertical, 3)
                    }
                }.font(.footnote)
            }
        }
    }

    private func openEvidence(_ evidence: AgentResponseEvidence) {
        guard evidence.bookID == entry.book.id, let locator = evidence.locator else { return }
        openSource(entry.book, locator)
    }

    private func contextDisclosureLine(_ trace: ContextPlanTrace?) -> String? {
        guard let trace else { return nil }
        var parts: [String] = []
        if !trace.selectedBookEvidenceIDs.isEmpty {
            parts.append("参考了已读部分 \(trace.selectedBookEvidenceIDs.count) 处书内内容")
        }
        if trace.connectedReflectionID != nil {
            parts.append("连接过去的一则想法")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "，")
    }
}

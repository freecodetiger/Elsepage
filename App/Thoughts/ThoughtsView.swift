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
    @State private var viewMode: ThoughtsViewMode = .records
    @State private var grouping: ThoughtsGrouping = .timeline
    @State private var filter: ThoughtsArchiveFilter = .all
    @State private var expandedEntryID: ReflectionID?
    @State private var selectedConversation: ReflectionConversationModel?
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
            .navigationTitle("想法")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "搜索想法、书名或回应")
            .toolbar {
                if viewMode == .records {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("分组", selection: $grouping) {
                                ForEach(ThoughtsGrouping.allCases) { option in
                                    Label(option.title, systemImage: option.systemImage).tag(option)
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .accessibilityLabel("分组方式")
                    }
                }
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
            .sheet(item: $selectedConversation) { conversation in
                NavigationStack {
                    ReflectionConversationView(
                        model: conversation,
                        openCitation: { evidence in
                            guard let entry = model.entries.first(where: {
                                $0.reflection.id == conversation.reflection.id
                            }), evidence.bookID == entry.book.id,
                                  let locator = evidence.locator else { return }
                            openSource(entry.book, locator)
                        },
                        onConversationDeleted: {
                            selectedConversation = nil
                            Task { await model.reload() }
                        }
                    )
                    .navigationTitle("会话")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { selectedConversation = nil }
                        }
                    }
                }
                .presentationBackground(Color.elsepageBackground)
            }
            .achievementToast(model.achievements)
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
            .onChange(of: grouping) { expandedEntryID = nil }
        }
    }

    private var emptyArchive: some View {
        ContentUnavailableView(
            "还没有留下想法",
            systemImage: "quote.bubble",
            description: Text("结束一次阅读后，写下一点真正留下来的东西。它会先安静地保存在本机。")
        )
    }

    private var searchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchEmptyState: some View {
        ContentUnavailableView.search(text: searchText)
            .frame(maxWidth: .infinity)
            .padding(.top, ElsepageTheme.Spacing.xLarge)
    }

    private var archive: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ElsepageTheme.Spacing.large) {
                controls
                if viewMode == .journal {
                    if visibleJournalEntries.isEmpty {
                        if searchActive {
                            searchEmptyState
                        } else {
                            // 日志为空：说明这条路径会沉淀什么，不催促。
                            ContentUnavailableView(
                                "档案还没有整理出条目",
                                systemImage: "book.closed",
                                description: Text("每次阅读后留下的记录、看法、问题和记忆变化，会安静地整理在这里。")
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, ElsepageTheme.Spacing.xLarge)
                        }
                    } else {
                        journalSections
                    }
                } else if visibleEntries.isEmpty {
                    if searchActive {
                        searchEmptyState
                    } else {
                        // 筛选（有回应/有连接）下没有条目：温和说明，不制造负罪感。
                        ContentUnavailableView(
                            "这个筛选下没有想法",
                            systemImage: "line.3.horizontal.decrease",
                            description: Text("换个筛选条件看看，或回到「全部」。")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, ElsepageTheme.Spacing.xLarge)
                    }
                } else if grouping == .timeline {
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
            Picker("查看内容", selection: $viewMode) {
                ForEach(ThoughtsViewMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if viewMode == .records {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: ElsepageTheme.Spacing.small) {
                        ForEach(ThoughtsArchiveFilter.allCases, id: \.self) { option in
                            Button(option.title) { filter = option }
                                .buttonStyle(.bordered)
                                .tint(filter == option ? .elsepageInteractive : .secondary)
                                // A11Y-03: keep the chip reachable at 44pt tall.
                                .frame(minHeight: 44)
                        }
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

    /// Structured reading archive: what survived a session, user-confirmed
    /// thoughts, questions, citations and memory changes. Details stay behind an
    /// explicit disclosure so the primary record remains easy to scan.
    private var journalSections: some View {
        LazyVStack(alignment: .leading, spacing: ElsepageTheme.Spacing.medium) {
            ForEach(visibleJournalEntries) { entry in
                JournalEntryCard(
                    entry: entry,
                    openConversation: {
                        selectedConversation = model.makeConversation(for: entry.reflection)
                    },
                    openSource: openSource,
                    onEditThought: { thought, newText in
                        Task { await model.applyThoughtEdit(thought, newText: newText) }
                    }
                )
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
                    .font(.headline.weight(.semibold))
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
                    if expandedEntryID != entry.id { Haptics.cardExpanded() }
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
                openConversation: {
                    selectedConversation = model.makeConversation(for: entry.reflection)
                },
                openSource: openSource
            )
        }
    }
}

private enum ThoughtsViewMode: String, CaseIterable, Identifiable {
    case records
    case journal

    var id: String { rawValue }
    var title: String {
        switch self {
        case .records: "记录"
        case .journal: "档案"
        }
    }
    var systemImage: String {
        switch self {
        case .records: "quote.bubble"
        case .journal: "doc.text"
        }
    }
}

private enum ThoughtsGrouping: String, CaseIterable, Identifiable {
    case timeline
    case books

    var id: String { rawValue }
    var title: String {
        switch self {
        case .timeline: "按时间"
        case .books: "按书籍"
        }
    }
    var systemImage: String {
        switch self {
        case .timeline: "calendar"
        case .books: "books.vertical"
        }
    }
}

private extension ThoughtsArchiveFilter {
    var title: String {
        switch self {
        case .all: "全部"
        case .hasAgentResponse: "有回应"
        case .hasConnection: "有关联"
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
    let openConversation: () -> Void
    let openSource: (Book, BookLocator) -> Void

    private var statusItems: [ThoughtStatus] {
        var items: [ThoughtStatus] = []
        if entry.derivedAgentResponse != nil {
            items.append(ThoughtStatus(title: "有回应", systemImage: "sparkles"))
        }
        if !entry.connections.isEmpty {
            items.append(ThoughtStatus(title: "连接过去", systemImage: "link"))
        }
        let discussionCount = entry.messages.filter { $0.author == .user }.count
        if discussionCount > 0 {
            items.append(ThoughtStatus(title: "\(discussionCount) 次讨论", systemImage: "bubble.left.and.bubble.right"))
        }
        return Array(items.prefix(2))
    }

    private var hasMoreEvidence: Bool {
        contextDisclosureLine(contextTrace) != nil
            || entry.derivedAgentResponse.flatMap { entry.responseProvenance[$0.id] }?.evidence.isEmpty == false
            || !entry.connections.isEmpty
            || entry.sourceLocator != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.medium) {
            Button(action: toggleExpanded) {
                VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
                    Text(entry.reflection.displayText)
                        .font(.body)
                        .foregroundStyle(Color.elsepageTextPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(isExpanded ? nil : 3)
                    metadata
                    if !isExpanded, !statusItems.isEmpty {
                        compactStatus
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // A11Y-02: 原话、书名、时间与状态读作一条，展开状态由 hint 表达。
            .accessibilityElement(children: .combine)
            .accessibilityHint(isExpanded ? "轻点收起记录" : "轻点展开回应与依据")

            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(ElsepageTheme.Spacing.medium)
        .background(Color.elsepageSurface, in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous)
                .stroke(Color.elsepageBorder)
        }
    }

    private var metadata: some View {
        HStack(alignment: .firstTextBaseline, spacing: ElsepageTheme.Spacing.small) {
            if showsBook {
                Text(entry.book.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.elsepageTextSecondary)
                    .lineLimit(1)
            }
            Text(entry.reflection.createdAt, format: .dateTime.month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(Color.elsepageTextTertiary)
            Spacer(minLength: 4)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.elsepageTextTertiary)
                .accessibilityHidden(true)
        }
    }

    private var compactStatus: some View {
        // A11Y-01: status capsules wrap when large type no longer fits a row.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: ElsepageTheme.Spacing.medium) { statusRow }
            VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.xSmall) { statusRow }
        }
        .font(.caption)
        .foregroundStyle(Color.elsepageTextSecondary)
    }

    private var statusRow: some View {
        ForEach(statusItems) { item in
            Label(item.title, systemImage: item.systemImage)
        }
    }

    @ViewBuilder private var expandedContent: some View {
        if let response = entry.derivedAgentResponse {
            Divider()
            responseBlock(title: "AI 回应", message: response)
        } else {
            Divider()
            Button(action: requestReply) {
                Label(isReplying ? "正在回应…" : "请 AI 回应", systemImage: "sparkles")
            }
            .buttonStyle(.bordered)
            .disabled(isReplying)
        }

        ForEach(entry.messages.filter { $0.id != entry.derivedAgentResponse?.id }) { message in
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text(message.author == .user ? "继续说" : "AI 回应")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.elsepageTextSecondary)
                    .copyMessageContextMenu(
                        content: message.content,
                        authorLabel: message.author == .user ? "我" : "AI",
                        date: message.createdAt
                    )
                if message.author == .agent {
                    AgentMarkdownText(
                        content: message.content,
                        provenance: entry.responseProvenance[message.id] ?? .init(evidence: [], citations: []),
                        openCitation: openEvidence,
                        textStyle: .subheadline
                    )
                } else {
                    SelectableTextBody(content: message.content, textStyle: .subheadline)
                }
            }
        }

        if entry.derivedAgentResponse != nil || !entry.messages.isEmpty {
            Divider()
            Button(action: openConversation) {
                Label("继续对话", systemImage: "bubble.left.and.bubble.right")
            }
            .buttonStyle(.bordered)
        }

        if hasMoreEvidence {
            Divider()
            moreEvidence
        }
    }

    private var moreEvidence: some View {
        DisclosureGroup("更多依据") {
            VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.medium) {
                if let line = contextDisclosureLine(contextTrace) {
                    Label(line, systemImage: "doc.text.magnifyingglass")
                        .foregroundStyle(Color.elsepageTextSecondary)
                }

                if let response = entry.derivedAgentResponse,
                   let provenance = entry.responseProvenance[response.id],
                   !provenance.evidence.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("本次使用的上下文")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.elsepageTextSecondary)
                        ForEach(provenance.evidence) { evidence in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(evidence.title ?? "阅读证据")
                                    .font(.caption.weight(.semibold))
                                Text(evidence.excerpt)
                                    .font(.caption)
                                    .foregroundStyle(Color.elsepageTextSecondary)
                                    .lineLimit(4)
                                if evidence.locator != nil {
                                    Button("回到原文") { openEvidence(evidence) }
                                        .font(.caption)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                if let connection = entry.connections.first {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("过去的你", systemImage: "link")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.elsepageTextSecondary)
                        Text(connection.sourceReflection.originalText)
                            .font(.subheadline)
                            .foregroundStyle(Color.elsepageTextSecondary)
                            .lineLimit(4)
                            .textSelection(.enabled)
                        if let locator = connection.sourceLocator {
                            Button("回到《\(connection.sourceBook.title)》") {
                                openSource(connection.sourceBook, locator)
                            }
                            .font(.footnote.weight(.medium))
                        }
                    }
                }

                if let locator = entry.sourceLocator {
                    Button("回到原文") { openSource(entry.book, locator) }
                        .font(.footnote.weight(.medium))
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
            }
            .padding(.top, ElsepageTheme.Spacing.small)
        }
        .font(.footnote)
    }

    private func responseBlock(title: String, message: ReflectionMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.elsepageTextSecondary)
            AgentMarkdownText(
                content: message.content,
                provenance: entry.responseProvenance[message.id] ?? .init(evidence: [], citations: []),
                openCitation: openEvidence,
                textStyle: .subheadline,
                isSecondary: true
            )
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

private struct ThoughtStatus: Identifiable {
    let title: String
    let systemImage: String

    var id: String { title }
}

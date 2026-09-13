import AppInfrastructure
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
    @State private var grouping: ThoughtsGrouping = .timeline
    @State private var selectedEntry: ReflectionArchiveEntry?
    let openSource: (Book, BookLocator) -> Void

    private var visibleEntries: [ReflectionArchiveEntry] {
        ThoughtsArchiveProjection.entries(model.entries, matching: searchText, filter: .all)
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading && model.entries.isEmpty {
                    ProgressView("正在整理你的记录…")
                } else if model.entries.isEmpty {
                    emptyRecords
                } else {
                    records
                }
            }
            .background(Color.elsepageBackground)
            .navigationTitle("想法")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "搜索记录、书名或回应")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("分组", selection: $grouping) {
                            ForEach(ThoughtsGrouping.allCases) { option in
                                Label(option.title, systemImage: option.systemImage).tag(option)
                            }
                        }
                        Divider()
                        Button { showsSettings = true } label: {
                            Label("设置", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("更多")
                }
            }
            .task { await model.reload() }
            .sheet(isPresented: $showsSettings) {
                SettingsView(model: settings)
            }
            .navigationDestination(item: $selectedEntry) { entry in
                ThoughtRecordDetailView(
                    entry: entry,
                    journal: model.journalEntries.first(where: { $0.reflection.id == entry.reflection.id }),
                    makeConversation: {
                        model.makeConversation(for: entry.reflection)
                    },
                    openSource: openSource
                )
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
            .onChange(of: searchText) { selectedEntry = nil }
            .onChange(of: grouping) { selectedEntry = nil }
        }
    }

    private var emptyRecords: some View {
        ContentUnavailableView(
            "还没有留下记录",
            systemImage: "quote.bubble",
            description: Text("结束一次阅读后，写下一点真正留下来的东西。它会先安静地保存在本机。")
        )
    }

    private var searchEmptyState: some View {
        ContentUnavailableView.search(text: searchText)
            .frame(maxWidth: .infinity)
            .padding(.top, ElsepageTheme.Spacing.xLarge)
    }

    private var records: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ElsepageTheme.Spacing.large) {
                if visibleEntries.isEmpty {
                    searchEmptyState
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

    private var timelineSections: some View {
        ForEach(ThoughtsArchiveProjection.monthSections(visibleEntries)) { section in
            archiveSection(
                title: ElsepageDateFormat.monthTitle(section.month),
                subtitle: "\(section.entries.count) 条记录"
            ) {
                entryCards(section.entries, showsBook: true)
            }
        }
    }

    private var bookSections: some View {
        ForEach(ThoughtsArchiveProjection.bookSections(visibleEntries)) { section in
            archiveSection(
                title: section.book.title,
                subtitle: "\(section.entries.count) 条记录"
            ) {
                entryCards(section.entries, showsBook: false)
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
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.elsepageTextTertiary)
            }
            content()
        }
    }

    private func entryCards(_ entries: [ReflectionArchiveEntry], showsBook: Bool) -> some View {
        ForEach(entries) { entry in
            Button {
                selectedEntry = entry
            } label: {
                ThoughtCard(entry: entry, showsBook: showsBook)
            }
            .buttonStyle(.plain)
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

private struct ThoughtCard: View {
    let entry: ReflectionArchiveEntry
    let showsBook: Bool

    private var summaryText: String {
        entry.summary?.text ?? Self.fallbackSummary(entry.reflection.displayText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
            metadata
            Text(summaryText)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.elsepageTextPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ElsepageTheme.Spacing.medium)
        .background(
            Color.elsepageSurface,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.elsepageBorder)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开这条阅读记录")
    }

    private var metadata: some View {
        HStack(alignment: .firstTextBaseline, spacing: ElsepageTheme.Spacing.xSmall) {
            if showsBook {
                Text(entry.book.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.elsepageTextSecondary)
                    .lineLimit(1)
                Text("·")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.elsepageTextTertiary)
            }
            Text(ElsepageDateFormat.shortDate(entry.reflection.createdAt))
                .font(.system(size: 12))
                .foregroundStyle(Color.elsepageTextTertiary)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.elsepageTextTertiary)
                .accessibilityHidden(true)
        }
    }

    private static func fallbackSummary(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return "还没有概要" }
        if normalized.count <= ReflectionSummary.maximumCharacterCount {
            return normalized
        }
        let sentence = normalized.split(whereSeparator: { "。！？!?".contains($0) }).first.map(String.init)
        if let sentence, !sentence.isEmpty, sentence.count <= ReflectionSummary.maximumCharacterCount {
            return sentence + "。"
        }
        return String(normalized.prefix(ReflectionSummary.maximumCharacterCount - 1)) + "…"
    }
}

private struct ThoughtRecordDetailView: View {
    let entry: ReflectionArchiveEntry
    let journal: JournalEntry?
    let makeConversation: () -> ReflectionConversationModel
    let openSource: (Book, BookLocator) -> Void

    @State private var conversation: ReflectionConversationModel?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let conversation {
                ReflectionConversationView(
                    model: conversation,
                    header: AnyView(ThoughtRecordHeader(entry: entry)),
                    recordExtras: AnyView(
                        ThoughtRecordExtras(
                            entry: entry,
                            journal: journal,
                            openSource: openSource
                        )
                    ),
                    rootTitle: "我的原话",
                    rootTextOverride: entry.reflection.originalText,
                    showsInlineProvenance: false,
                    openCitation: { evidence in
                        guard evidence.bookID == entry.book.id,
                              let locator = evidence.locator else { return }
                        openSource(entry.book, locator)
                    },
                    onConversationDeleted: { dismiss() }
                )
            } else {
                ProgressView()
                    .task {
                        if conversation == nil {
                            conversation = makeConversation()
                        }
                    }
            }
        }
        .navigationTitle("阅读记录")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ThoughtRecordHeader: View {
    let entry: ReflectionArchiveEntry

    private var summaryText: String {
        entry.summary?.text ?? Self.fallbackSummary(entry.reflection.displayText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.medium) {
            HStack(alignment: .firstTextBaseline, spacing: ElsepageTheme.Spacing.xSmall) {
                Text(entry.book.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.elsepageTextSecondary)
                Text("·")
                    .foregroundStyle(Color.elsepageTextTertiary)
                Text(ElsepageDateFormat.shortDate(entry.reflection.createdAt))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.elsepageTextTertiary)
            }

            HStack(alignment: .top, spacing: ElsepageTheme.Spacing.small) {
                ZStack {
                    Circle()
                        .fill(Color.elsepageTextPrimary)
                        .frame(width: 36, height: 36)
                    Text("概")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.elsepageBackground)
                }
                Text(summaryText)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.elsepageTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, ElsepageTheme.Spacing.small)
    }

    private static func fallbackSummary(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return "还没有概要" }
        if normalized.count <= ReflectionSummary.maximumCharacterCount {
            return normalized
        }
        return String(normalized.prefix(ReflectionSummary.maximumCharacterCount - 1)) + "…"
    }
}

private struct ThoughtRecordExtras: View {
    let entry: ReflectionArchiveEntry
    let journal: JournalEntry?
    let openSource: (Book, BookLocator) -> Void

    private var hasStructuredLeftovers: Bool {
        journal?.whatIThink.isEmpty == false || journal?.questions.isEmpty == false
    }

    private var hasEvidence: Bool {
        !entry.connections.isEmpty
            || entry.sourceLocator != nil
            || journal?.citations.isEmpty == false
            || journal?.session != nil
            || journal?.chapters.isEmpty == false
            || entry.derivedAgentResponse.flatMap { entry.responseProvenance[$0.id] }?.evidence.isEmpty == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.large) {
            if hasStructuredLeftovers {
                leftoversSection
            }

            if hasEvidence {
                Divider()
                evidenceSection
            }
        }
    }

    private var leftoversSection: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.medium) {
            Text("这次留下")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Color.elsepageTextTertiary)

            if let thoughts = journal?.whatIThink, !thoughts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("看法")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.elsepageTextSecondary)
                    ForEach(thoughts.prefix(3), id: \.id) { thought in
                        Text("· \(thought.thought)")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.elsepageTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let questions = journal?.questions, !questions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("问题")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.elsepageTextSecondary)
                    ForEach(questions.prefix(2)) { question in
                        Text("· \(question.text)")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.elsepageTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.large) {
            Text("依据")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Color.elsepageTextTertiary)

            if let session = journal?.session, let duration = session.duration {
                evidenceRow(title: "本次阅读", value: durationLabel(duration))
            }

            if let chapters = journal?.chapters, !chapters.isEmpty {
                evidenceRow(
                    title: "覆盖章节",
                    value: chapters.compactMap(\.title).joined(separator: "、")
                )
            }

            if let response = entry.derivedAgentResponse,
               let provenance = entry.responseProvenance[response.id],
               !provenance.evidence.isEmpty {
                evidenceList(title: "本次使用的上下文", items: provenance.evidence.map {
                    ($0.title ?? "阅读证据", $0.excerpt, $0.locator)
                })
            }

            if let citations = journal?.citations, !citations.isEmpty {
                evidenceList(title: "引用", items: citations.map {
                    ($0.title ?? "原文引用", $0.excerpt ?? "", $0.locator)
                })
            }

            if let connection = entry.connections.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text("过去的你")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.elsepageTextSecondary)
                    Text(connection.sourceReflection.originalText)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.elsepageTextSecondary)
                        .lineLimit(4)
                    if let locator = connection.sourceLocator {
                        Button("回到《\(connection.sourceBook.title)》") {
                            openSource(connection.sourceBook, locator)
                        }
                        .font(.system(size: 13, weight: .medium))
                    }
                }
            }

            if let locator = entry.sourceLocator {
                Button("回到原文") { openSource(entry.book, locator) }
                    .font(.system(size: 13, weight: .medium))
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
    }

    @ViewBuilder
    private func evidenceList(
        title: String,
        items: [(String, String, BookLocator?)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.elsepageTextSecondary)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0)
                        .font(.system(size: 12, weight: .semibold))
                    Text(item.1)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.elsepageTextSecondary)
                        .lineLimit(4)
                    if let locator = item.2 {
                        Button("回到原文") { openSource(entry.book, locator) }
                            .font(.system(size: 12, weight: .medium))
                    }
                }
            }
        }
    }

    private func evidenceRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.elsepageTextSecondary)
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(Color.elsepageTextPrimary)
        }
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        let minutes = Int((duration / 60).rounded(.down))
        return minutes > 0 ? "\(minutes) 分钟" : "不足 1 分钟"
    }
}

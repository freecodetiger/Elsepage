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
            VStack(spacing: 0) {
                ElsepageRootHeader(title: "想法") {
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
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Color.elsepageTextPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("更多")
                }
                ElsepageSearchField(text: $searchText, prompt: "搜索记录、书名或回应")
                    .padding(.horizontal, ElsepageTheme.Spacing.pageInset)
                    .padding(.bottom, 12)
                Group {
                    if model.isLoading && model.entries.isEmpty {
                        ProgressView("正在整理你的记录…")
                    } else if model.entries.isEmpty {
                        emptyRecords
                    } else {
                        records
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.elsepageBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
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
        // No description line: the 想法 page holds records and nothing else,
        // so the title plus the icon already say what is missing. A second
        // paragraph here only competed with the tab bar and the search field.
        ContentUnavailableView(
            "还没有留下记录",
            systemImage: "quote.bubble"
        )
    }

    private var searchEmptyState: some View {
        ContentUnavailableView.search(text: searchText)
            .frame(maxWidth: .infinity)
            .padding(.top, ElsepageTheme.Spacing.xLarge)
    }

    private var records: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                if visibleEntries.isEmpty {
                    searchEmptyState
                } else if grouping == .timeline {
                    timelineSections
                } else {
                    bookSections
                }
            }
            .padding(.horizontal, ElsepageTheme.Spacing.pageInset)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable { await model.reload() }
    }

    private var timelineSections: some View {
        ForEach(ThoughtsArchiveProjection.monthSections(visibleEntries)) { section in
            archiveSection(
                title: ElsepageDateFormat.monthTitle(section.month),
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
                subtitle: "\(section.entries.count) 条"
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.elsepageTextPrimary)
                Spacer()
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color.elsepageTextTertiary)
            }
            .padding(.bottom, 8)
            content()
        }
    }

    private func entryCards(_ entries: [ReflectionArchiveEntry], showsBook: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                Button {
                    selectedEntry = entry
                } label: {
                    ThoughtCard(entry: entry, showsBook: showsBook)
                }
                .buttonStyle(.plain)
                if index < entries.count - 1 {
                    Divider()
                }
            }
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
        VStack(alignment: .leading, spacing: 4) {
            metadata
            Text(summaryText)
                .font(.headline)
                .foregroundStyle(Color.elsepageTextPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开这条阅读记录")
    }

    private var metadata: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if showsBook {
                Text(entry.book.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.elsepageTextPrimary)
                    .lineLimit(1)
                Text("·")
                    .font(.footnote)
                    .foregroundStyle(Color.elsepageTextTertiary)
            }
            Text(ElsepageDateFormat.shortDate(entry.reflection.createdAt))
                .font(.footnote)
                .foregroundStyle(Color.elsepageTextTertiary)
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

    private var recordExtras: AnyView? {
        guard let journal,
              !journal.whatIThink.isEmpty || !journal.questions.isEmpty else {
            return nil
        }
        return AnyView(ThoughtRecordExtras(journal: journal))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let conversation {
                    ReflectionConversationView(
                        model: conversation,
                        header: AnyView(
                            ThoughtRecordHeader(entry: entry)
                                .padding(.top, 48)
                        ),
                        recordExtras: recordExtras,
                        rootTextOverride: entry.reflection.originalText,
                        showsInlineProvenance: true,
                        openCitation: { evidence in
                            guard evidence.bookID == entry.book.id,
                                  let locator = evidence.locator else { return }
                            openSource(entry.book, locator)
                        },
                        contextualStrings: speechContextualStrings(for: entry.book),
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

            ElsepageIconButton(
                systemName: "chevron.left",
                accessibilityLabel: "返回想法列表"
            ) {
                dismiss()
            }
            .padding(.leading, 16)
            .padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
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
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.elsepageTextSecondary)
                Text("·")
                    .foregroundStyle(Color.elsepageTextTertiary)
                Text(ElsepageDateFormat.shortDate(entry.reflection.createdAt))
                    .font(.caption)
                    .foregroundStyle(Color.elsepageTextTertiary)
            }

            HStack(alignment: .top, spacing: ElsepageTheme.Spacing.small) {
                ZStack {
                    Circle()
                        .fill(Color.elsepageTextPrimary)
                        .frame(width: 36, height: 36)
                    Text("概")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.elsepageBackground)
                }
                Text(summaryText)
                    .font(.title3.weight(.semibold))
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
    let journal: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.medium) {
            Text("这次留下")
                .font(.caption2.weight(.semibold))
                .tracking(0.7)
                .foregroundStyle(Color.elsepageTextTertiary)

            if !journal.whatIThink.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("想法")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.elsepageTextSecondary)
                    ForEach(journal.whatIThink.prefix(3), id: \.id) { thought in
                        Text("· \(thought.thought)")
                            .font(.subheadline)
                            .foregroundStyle(Color.elsepageTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !journal.questions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("问题")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.elsepageTextSecondary)
                    ForEach(journal.questions.prefix(2)) { question in
                        Text("· \(question.text)")
                            .font(.subheadline)
                            .foregroundStyle(Color.elsepageTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

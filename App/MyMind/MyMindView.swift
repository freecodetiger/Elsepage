import AchievementCore
import AppInfrastructure
import BrainCore
import ContextEngineering
import LibraryCore
import ReaderAgent
import ReaderCore
import ReflectionCore
import SwiftUI

/// 「我的大脑」(docs/brain.md §14): Thoughts / Questions / Memories 三分区。
/// Thoughts and Questions live in the Brain store and are editable (never
/// manually created — they form through reading, phase 17); Memories keep the
/// legacy store and its full action set. The homepage is not a database
/// manager: sections stay quiet and empty until content actually forms.
struct MyMindView: View {
    @Bindable var model: MyMindModel
    @Bindable var settings: SettingsRootModel
    @Bindable var achievements: AchievementModel
    let openSource: (Book, BookLocator) -> Void

    @State private var expandedMemoryID: BrainItemID?
    @State private var editingMemory: BrainMemory?
    @State private var editText = ""
    @State private var showsClearAll = false
    @State private var showsSettings = false
    @State private var showsAchievements = false
    @State private var evidenceByMemory: [BrainItemID: MemoryEvidence] = [:]
    @State private var selectedThought: Thought?
    @State private var selectedQuestion: Question?
    @State private var discussingItem: BrainItem?
    @State private var editingThought: Thought?
    @State private var editingQuestion: Question?
    @State private var selectedFacet: MindFacet = .thoughts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isEmpty: Bool {
        model.memories.isEmpty && !model.hasBrainItems
    }

    init(
        model: MyMindModel,
        settings: SettingsRootModel,
        achievements: AchievementModel,
        openSource: @escaping (Book, BookLocator) -> Void
    ) {
        self.model = model
        self.settings = settings
        self.achievements = achievements
        self.openSource = openSource
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ElsepageRootHeader(title: "我的") {
                    Button { showsAchievements = true } label: {
                        Image(systemName: "rosette")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Color.elsepageTextPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("成就")
                    Button { showsSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Color.elsepageTextPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("设置")
                }
                stateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.elsepageBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            // 看法沉淀 (PRD §10.3): the first memories forming (and the empty state
            // handing over to them) land as a quiet cross-fade.
            .animation(ElsepageTheme.Motion.moment(reduceMotion), value: model.memories.isEmpty)
            .navigationDestination(isPresented: $showsAchievements) { achievementsDestination }
            .task { await model.reload() }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView(model: settings)
        }
        .achievementToast(achievements)
        .alert("暂时无法完成操作", isPresented: errorBinding) {
            Button("好") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("修改这条记忆", isPresented: editingBinding) {
            TextField("新的说法", text: $editText)
            Button("取消", role: .cancel) {}
            Button("保存") { commitMemoryEdit() }
        }
        .sheet(isPresented: editingThoughtBinding) { thoughtEditor }
        .sheet(isPresented: editingQuestionBinding) { questionEditor }
        .confirmationDialog("清除全部记忆？", isPresented: $showsClearAll, titleVisibility: .visible) {
            Button("清除全部记忆", role: .destructive) { Task { await model.deleteAllMemories() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会删除 AI 记住的每一条内容，且无法撤销。")
        }
    }

    /// The body expression is deliberately split into small sub-expressions —
    /// the single-expression form outgrew the type-checker budget.
    private var stateView: some View {
        Group {
            if model.isLoading && isEmpty {
                ProgressView("正在整理对你的理解…")
            } else {
                // The three facets are the page's structure, not a reward for
                // having data. Show the picker even when all three are empty;
                // each facet owns its one-line empty message.
                content
                    .transition(.moment(reduceMotion))
            }
        }
    }


    private var thoughtEditor: some View {
        Group {
            if let thought = editingThought {
                BrainItemEditorSheet(
                    title: "修改这个想法",
                    textTitle: "想法",
                    initialText: thought.statement,
                    secondaryTitle: "标题",
                    initialSecondaryText: thought.title,
                    stages: ThoughtStage.allCases,
                    selectedStage: thought.stage,
                    stageLabel: { brainStageLabel($0) },
                    onSave: { title, statement, stage in
                        guard let title else { return }
                        Task { await model.editThought(thought, title: title, statement: statement, stage: stage) }
                    }
                )
            }
        }
    }

    private var questionEditor: some View {
        Group {
            if let question = editingQuestion {
                BrainItemEditorSheet(
                    title: "修改这个问题",
                    textTitle: "问题",
                    initialText: question.question,
                    secondaryTitle: nil,
                    initialSecondaryText: nil,
                    stages: QuestionState.allCases,
                    selectedStage: question.state,
                    stageLabel: { brainStateLabel($0) },
                    onSave: { _, text, state in
                        Task { await model.editQuestion(question, text: text, state: state) }
                    }
                )
            }
        }
    }

    private func commitMemoryEdit() {
        let claim = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let memory = editingMemory, !claim.isEmpty else { return }
        Task { await model.edit(memory, newClaim: claim) }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    facetContent
                        .padding(.horizontal, ElsepageTheme.Spacing.pageInset)
                        .padding(.bottom, 24)
                } header: {
                    facetPicker
                }
            }
        }
        .navigationDestination(item: $selectedThought) { brainThoughtDestination($0) }
        .navigationDestination(item: $selectedQuestion) { brainQuestionDestination($0) }
        // Memory 更新 (PRD §10.3): confirmations/edits settle without a jump cut.
        .animation(ElsepageTheme.Motion.moment(reduceMotion), value: model.memories.map(\.id))
        .refreshable { await model.reload() }
    }

    /// The three facets are peers. A vertical feed made the top one primary by
    /// accident and pushed the rest away as it grew; a segmented control keeps
    /// the top fixed and gives each list its own scroll.
    private var facetPicker: some View {
        Picker("内容", selection: $selectedFacet) {
            Text("看法 \(model.thoughts.count)").tag(MindFacet.thoughts)
            Text("问题 \(model.questions.count)").tag(MindFacet.questions)
            Text("记忆 \(model.activeMemories.count)").tag(MindFacet.memories)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, ElsepageTheme.Spacing.pageInset)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(Color.elsepageBackground)
    }

    @ViewBuilder private var facetContent: some View {
        switch selectedFacet {
        case .thoughts:
            thoughtsFacet
        case .questions:
            questionsFacet
        case .memories:
            memoriesFacet
        }
    }

    @ViewBuilder private var thoughtsFacet: some View {
        if model.thoughts.isEmpty {
            facetEmpty("你的想法还在阅读里，会随讨论逐渐成形。")
        } else {
            grouped {
                ForEach(Array(model.thoughts.enumerated()), id: \.element.id) { index, thought in
                    MindRow(
                        title: thought.title,
                        preview: thought.statement,
                        meta: "\(brainStageLabel(thought.stage)) · \(ElsepageDateFormat.shortDate(thought.updatedAt))"
                    ) {
                        Haptics.cardExpanded()
                        selectedThought = thought
                    }
                    if index < model.thoughts.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
    }

    @ViewBuilder private var questionsFacet: some View {
        if model.questions.isEmpty {
            facetEmpty("还没有正在追踪的问题。")
        } else {
            grouped {
                ForEach(Array(model.questions.enumerated()), id: \.element.id) { index, question in
                    MindRow(
                        title: question.question,
                        preview: nil,
                        meta: "\(brainStateLabel(question.state)) · \(ElsepageDateFormat.shortDate(question.updatedAt))"
                    ) {
                        Haptics.cardExpanded()
                        selectedQuestion = question
                    }
                    if index < model.questions.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
    }

    @ViewBuilder private var memoriesFacet: some View {
        if model.activeMemories.isEmpty && model.retiredMemories.isEmpty {
            facetEmpty("这是我目前从阅读与讨论中形成的理解，会随你的反馈调整。")
        } else {
            VStack(alignment: .leading, spacing: 24) {
                if !model.activeMemories.isEmpty {
                    grouped {
                        ForEach(Array(model.activeMemories.enumerated()), id: \.element.id) { index, memory in
                            row(for: memory)
                            if index < model.activeMemories.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
                if !model.retiredMemories.isEmpty {
                    DisclosureGroup("已失效 \(model.retiredMemories.count) 条") {
                        grouped {
                            ForEach(Array(model.retiredMemories.enumerated()), id: \.element.id) { index, memory in
                                row(for: memory)
                                if index < model.retiredMemories.count - 1 {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    .font(.subheadline.weight(.semibold))
                }
                if !model.memories.isEmpty {
                    Button("清除全部记忆", role: .destructive) {
                        showsClearAll = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.elsepageDanger)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.top, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func grouped<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            Color.elsepageSurface,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private func facetEmpty(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.elsepageTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }

    private var achievementsDestination: some View {
        Group {
            if achievements.unlocked.isEmpty {
                ContentUnavailableView(
                    "还没有解锁成就",
                    systemImage: "rosette",
                    description: Text("读完并留下想法后，会开始解锁一些有意义的徽章。")
                )
            } else {
                List {
                    ForEach(Achievement.all.filter { definition in
                        achievements.unlocked.contains { $0.id == definition.id }
                    }) { definition in
                        HStack(spacing: 12) {
                            Image(systemName: definition.systemImage)
                                .font(.title3)
                                .foregroundStyle(Color.elsepageInteractive)
                                .frame(width: 38, height: 38)
                                .background(Color.elsepageInteractive.opacity(0.08), in: Circle())
                            Text(definition.title)
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 8)
                            if let record = achievements.unlocked.first(where: { $0.id == definition.id }) {
                                Text(ElsepageDateFormat.shortDate(record.unlockedAt))
                                    .font(.footnote)
                                    .foregroundStyle(Color.elsepageTextTertiary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("成就")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func brainThoughtDestination(_ thought: Thought) -> some View {
        BrainThoughtDetailView(
            thought: thought,
            evidenceLoader: { await model.brainEvidence(for: .thought(thought)) },
            revisionsLoader: { await model.brainRevisions(for: .thought(thought)) },
            contextLoader: { evidence in
                await model.brainEvidenceContext(for: evidence).map {
                    MemoryEvidence(reflectionText: $0.reflectionText, book: $0.book, locator: $0.locator)
                }
            },
            openSource: openSource,
            canContinueThinking: model.canContinueThinking,
            onContinueThinking: { discussingItem = .thought(thought) },
            onArchiveAsMemory: {
                Task { await model.archiveAsMemory(thought) }
            },
            onEdit: { editingThought = thought },
            onDelete: {
                Task {
                    await model.deleteThought(thought)
                    selectedThought = nil
                }
            }
        )
        .toolbar(.visible, for: .navigationBar)
    }

    private func brainQuestionDestination(_ question: Question) -> some View {
        // 可被关联的非 archived 想法(§18 addresses);空则详情页不显示该动作。
        let answerCandidates = model.thoughts.filter { $0.stage != .archived }
        return BrainQuestionDetailView(
            question: question,
            evidenceLoader: { await model.brainEvidence(for: .question(question)) },
            contextLoader: { evidence in
                await model.brainEvidenceContext(for: evidence).map {
                    MemoryEvidence(reflectionText: $0.reflectionText, book: $0.book, locator: $0.locator)
                }
            },
            openSource: openSource,
            canContinueThinking: model.canContinueThinking,
            onContinueThinking: { discussingItem = .question(question) },
            answerCandidates: answerCandidates,
            onResolve: { thoughtID in
                Task { await model.resolveQuestion(question, answeredBy: thoughtID) }
            },
            onEdit: { editingQuestion = question },
            onDelete: {
                Task {
                    await model.deleteQuestion(question)
                    selectedQuestion = nil
                }
            }
        )
        .toolbar(.visible, for: .navigationBar)
    }

    private func row(for memory: BrainMemory) -> some View {
        MemoryRow(
            memory: memory,
            isExpanded: expandedMemoryID == memory.id,
            evidence: evidenceByMemory[memory.id],
            onToggleEvidence: { toggleEvidence(memory) },
            onAccurate: { Task { await model.confirm(memory) } },
            onInaccurate: { Task { await model.markInaccurate(memory) } },
            onEdit: { startEdit(memory) },
            onDelete: { Task { await model.delete(memory) } },
            openSource: openSource
        )
    }

    private func startEdit(_ memory: BrainMemory) {
        editingMemory = memory
        editText = memory.content
    }

    private func toggleEvidence(_ memory: BrainMemory) {
        if expandedMemoryID == memory.id {
            withAnimation(.snappy(duration: 0.24)) { expandedMemoryID = nil }
        } else {
            withAnimation(.snappy(duration: 0.24)) { expandedMemoryID = memory.id }
            Haptics.cardExpanded()
            if evidenceByMemory[memory.id] == nil {
                Task { await loadEvidence(for: memory) }
            }
        }
    }

    private func loadEvidence(for memory: BrainMemory) async {
        if let context = await model.memoryEvidenceContext(for: memory) {
            evidenceByMemory[memory.id] = MemoryEvidence(
                reflectionText: context.reflectionText,
                book: context.book,
                locator: context.locator
            )
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    private var editingBinding: Binding<Bool> {
        Binding(get: { editingMemory != nil }, set: { if !$0 { editingMemory = nil } })
    }

    private var editingThoughtBinding: Binding<Bool> {
        Binding(get: { editingThought != nil }, set: { if !$0 { editingThought = nil } })
    }

    private var editingQuestionBinding: Binding<Bool> {
        Binding(get: { editingQuestion != nil }, set: { if !$0 { editingQuestion = nil } })
    }

    private var discussingBinding: Binding<Bool> {
        Binding(get: { discussingItem != nil }, set: { if !$0 { discussingItem = nil } })
    }

}

private enum MindFacet: Hashable {
    case thoughts
    case questions
    case memories
}

private struct MindRow: View {
    let title: String
    let preview: String?
    let meta: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color.elsepageTextPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let preview {
                        Text(preview)
                            .font(.subheadline)
                            .foregroundStyle(Color.elsepageTextSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Text(meta)
                        .font(.footnote)
                        .foregroundStyle(Color.elsepageTextTertiary)
                        .padding(.top, 2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.elsepageTextTertiary)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开详情")
    }
}

private struct MemoryEvidence {
    let reflectionText: String
    let book: Book?
    let locator: BookLocator?
}

private struct MemoryRow: View {
    let memory: BrainMemory
    let isExpanded: Bool
    let evidence: MemoryEvidence?
    let onToggleEvidence: () -> Void
    let onAccurate: () -> Void
    let onInaccurate: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let openSource: (Book, BookLocator) -> Void

    private var isRetired: Bool { memory.state == .superseded || memory.state == .forgotten }
    private var isUserExplicit: Bool { memory.origin == .userExplicit }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggleEvidence) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(memory.content)
                            .font(.subheadline)
                            .strikethrough(isRetired, color: Color.elsepageTextSecondary)
                            .foregroundStyle(isRetired ? Color.elsepageTextSecondary : Color.elsepageTextPrimary)
                            .lineLimit(isExpanded ? nil : 4)
                            .multilineTextAlignment(.leading)
                        Text(metaLine)
                            .font(.footnote)
                            .foregroundStyle(Color.elsepageTextTertiary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.elsepageTextTertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // A11Y-02: 来源性质、内容、时间与置信度读作一条;操作按需展开。
            .accessibilityElement(children: .combine)
            .accessibilityHint(isExpanded ? "轻点收起来源和操作" : "轻点查看来源和操作")

            if isExpanded {
                Divider()
                actions
                evidenceBlock
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
    }

    /// 来源性质(brain.md §17):用户明确表达 vs AI 推断——信任的第一信号。
    private var metaLine: String {
        var parts: [String] = []
        if memory.state == .needsReview { parts.append("待确认") }
        parts.append(isUserExplicit ? "用户明确表达" : "AI 推断")
        parts.append("置信度\(memory.confidence.displayName)")
        parts.append(ElsepageDateFormat.dateTime(memory.updatedAt))
        return parts.joined(separator: " · ")
    }

    private var actions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ElsepageTheme.Spacing.small) {
                Button("准确", action: onAccurate)
                    .disabled(isRetired)
                Button("不准确", action: onInaccurate)
                    .disabled(isRetired)
                Button("修改", action: onEdit)
                    .disabled(isRetired)
                Button("忘记", action: onDelete)
                Button(isExpanded ? "收起依据" : "查看依据", action: onToggleEvidence)
            }
            .font(.footnote)
            .buttonStyle(.bordered)
            .tint(Color.elsepageInteractive)
            // A11Y-03: keep each compact action at the 44pt minimum target.
            .frame(minHeight: 44)
        }
    }

    @ViewBuilder private var evidenceBlock: some View {
        Divider()
        if let evidence {
            VStack(alignment: .leading, spacing: 6) {
                Label("记忆来源", systemImage: "quote.bubble")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.elsepageInteractive)
                Text(evidence.reflectionText)
                    .font(.subheadline)
                    .foregroundStyle(Color.elsepageTextSecondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                if let locator = evidence.locator, let book = evidence.book {
                    Button("回到《\(book.title)》") { openSource(book, locator) }
                        .font(.footnote.weight(.medium))
                        .tint(Color.elsepageInteractive)
                }
            }
        } else {
            Text("没有可展示的来源依据")
                .font(.footnote)
                .foregroundStyle(Color.elsepageTextTertiary)
        }
    }
}

private extension MemoryConfidence {
    var displayName: String {
        switch self {
        case .high: "高"
        case .medium: "中"
        case .low: "低"
        }
    }
}

private func brainStageLabel(_ stage: ThoughtStage) -> String {
    switch stage {
    case .emerging: "萌芽"
    case .evolving: "演化中"
    case .stable: "稳定"
    case .reconsidering: "重新审视"
    case .archived: "已归档"
    }
}

private func brainStateLabel(_ state: QuestionState) -> String {
    switch state {
    case .open: "未解决"
    case .exploring: "探索中"
    case .partiallyResolved: "部分解决"
    case .resolved: "已解决"
    case .dormant: "暂放"
    }
}

/// Thought detail (brain.md §15): current statement, stage, evidence section,
/// edit, delete, and — for a `.stable` thought — 存档为记忆 (§18: archive a
/// confirmed thought as an active Memory via `derivedMemory`).
private struct BrainThoughtDetailView: View {
    let thought: Thought
    let evidenceLoader: () async -> [BrainEvidence]
    let revisionsLoader: () async -> [BrainItemRevision]
    let contextLoader: (BrainEvidence) async -> MemoryEvidence?
    let openSource: (Book, BookLocator) -> Void
    let canContinueThinking: Bool
    let onContinueThinking: () -> Void
    let onArchiveAsMemory: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var showsDelete = false
    @State private var evidence: [BrainEvidence] = []
    @State private var contexts: [String: MemoryEvidence] = [:]
    @State private var revisions: [BrainItemRevision] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.large) {
                VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
                    Text("当前的我")
                        .font(.headline.weight(.semibold))
                    Text(thought.statement)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                HStack(spacing: ElsepageTheme.Spacing.small) {
                    Text(brainStageLabel(thought.stage))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.elsepageInteractive.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.elsepageInteractive)
                    Text("更新于 \(ElsepageDateFormat.yearMonthDay(thought.updatedAt))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                BrainRevisionSection(revisions: revisions)
                BrainEvidenceSection(
                    heading: "来自我的阅读",
                    evidence: evidence,
                    contexts: contexts,
                    openSource: openSource
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ElsepageTheme.Spacing.page)
        }
        .background(Color.elsepageBackground)
        .navigationTitle(thought.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadEvidence() }
        .toolbar {
            if thought.stage == .stable {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("存档为记忆", action: onArchiveAsMemory)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("继续想想", action: onContinueThinking)
                    .disabled(!canContinueThinking)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("编辑", action: onEdit)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { showsDelete = true } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("删除这个想法")
            }
        }
        .confirmationDialog("删除这个想法？", isPresented: $showsDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: onDelete)
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法撤销。")
        }
    }

    private func loadEvidence() async {
        evidence = await evidenceLoader()
        revisions = await revisionsLoader()
        for row in evidence {
            let key = brainEvidenceKey(row.source)
            if case .reflection = row.source, contexts[key] == nil {
                contexts[key] = await contextLoader(row)
            }
        }
    }
}

/// The thought's evolution timeline (brain.md §10, phase 18): every replaced
/// statement, newest first. The current statement lives above; this is the
/// traceable path it took to get here.
private struct BrainRevisionSection: View {
    let revisions: [BrainItemRevision]

    var body: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
            Text("我的变化")
                .font(.headline.weight(.semibold))
            if revisions.isEmpty {
                Text("陈述会随讨论不断重写，旧版本留在这里。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(revisions, id: \.revision) { revision in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(revision.content)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(ElsepageDateFormat.yearMonth(revision.createdAt))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(ElsepageTheme.Spacing.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.elsepageSurface, in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Question detail (brain.md §16): the question, its state, and where it came
/// from. 标记已解决并关联想法 (§18) links the question to its answering thought
/// via an `addresses` relation.
private struct BrainQuestionDetailView: View {
    let question: Question
    let evidenceLoader: () async -> [BrainEvidence]
    let contextLoader: (BrainEvidence) async -> MemoryEvidence?
    let openSource: (Book, BookLocator) -> Void
    let canContinueThinking: Bool
    let onContinueThinking: () -> Void
    /// 可被关联为"答案"的非 archived 想法(§18 addresses)。
    let answerCandidates: [Thought]
    let onResolve: (BrainItemID) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var showsDelete = false
    @State private var showsResolvePicker = false
    @State private var evidence: [BrainEvidence] = []
    @State private var contexts: [String: MemoryEvidence] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.large) {
                VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
                    Text("问题")
                        .font(.headline.weight(.semibold))
                    Text(question.question)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                HStack(spacing: ElsepageTheme.Spacing.small) {
                    Text(brainStateLabel(question.state))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.elsepageInteractive.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.elsepageInteractive)
                    Text("更新于 \(ElsepageDateFormat.yearMonthDay(question.updatedAt))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                BrainEvidenceSection(
                    heading: "它从哪里来",
                    evidence: evidence,
                    contexts: contexts,
                    openSource: openSource
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ElsepageTheme.Spacing.page)
        }
        .background(Color.elsepageBackground)
        .navigationTitle("问题")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadEvidence() }
        .toolbar {
            if question.state != .resolved && !answerCandidates.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("标记已解决") { showsResolvePicker = true }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("继续想想", action: onContinueThinking)
                    .disabled(!canContinueThinking)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("编辑", action: onEdit)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { showsDelete = true } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("删除这个问题")
            }
        }
        .confirmationDialog("删除这个问题？", isPresented: $showsDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: onDelete)
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法撤销。")
        }
        .confirmationDialog("这个问题已被哪个想法回答？", isPresented: $showsResolvePicker, titleVisibility: .visible) {
            ForEach(answerCandidates, id: \.id) { thought in
                Button(thought.title) { onResolve(thought.id) }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func loadEvidence() async {
        evidence = await evidenceLoader()
        for row in evidence {
            let key = brainEvidenceKey(row.source)
            if case .reflection = row.source, contexts[key] == nil {
                contexts[key] = await contextLoader(row)
            }
        }
    }
}

/// Evidence block shared by both detail pages. Reflection sources resolve to
/// original words + a jump back into the book; other source types degrade to
/// a typed reference line. Empty state is the trust-preserving downgrade:
/// sources accumulate with discussion, they are never fabricated.
private struct BrainEvidenceSection: View {
    let heading: String
    let evidence: [BrainEvidence]
    let contexts: [String: MemoryEvidence]
    let openSource: (Book, BookLocator) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
            Text(heading)
                .font(.headline.weight(.semibold))
            if evidence.isEmpty {
                Text("来源会随讨论逐渐积累。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(evidence, id: \.self) { row in
                    evidenceRow(row)
                }
            }
        }
    }

    @ViewBuilder
    private func evidenceRow(_ row: BrainEvidence) -> some View {
        let key = brainEvidenceKey(row.source)
        if let context = contexts[key] {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.reflectionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: ElsepageTheme.Spacing.small) {
                    if let book = context.book {
                        Text("《\(book.title)》")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.elsepageInteractive)
                    }
                    Text(brainRelationLabel(row.relation))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let book = context.book, let locator = context.locator {
                    Button("回到《\(book.title)》") { openSource(book, locator) }
                        .font(.footnote.weight(.medium))
                        .tint(Color.elsepageInteractive)
                }
            }
            .padding(ElsepageTheme.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.elsepageSurface, in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous))
            .accessibilityElement(children: .combine)
        } else if case .reflection = row.source {
            // Soft-dangling: the reflection was deleted; show nothing for it.
            EmptyView()
        } else {
            HStack(spacing: ElsepageTheme.Spacing.small) {
                Text(brainSourceTypeLabel(row.source))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.elsepageInteractive.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.elsepageInteractive)
                Text(brainRelationLabel(row.relation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
            }
            .padding(ElsepageTheme.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.elsepageSurface, in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }
}

private func brainEvidenceKey(_ source: BrainEvidenceSource) -> String {
    switch source {
    case .reflection(let id): "reflection:\(id)"
    case .bookChunk(let id): "bookChunk:\(id)"
    case .message(let id): "message:\(id)"
    }
}

private func brainSourceTypeLabel(_ source: BrainEvidenceSource) -> String {
    switch source {
    case .reflection: "反思"
    case .bookChunk: "原文"
    case .message: "对话"
    }
}

private func brainRelationLabel(_ relation: EvidenceRelation) -> String {
    switch relation {
    case .origin: "来源"
    case .supports: "支持"
    case .contradicts: "相悖"
    case .revises: "修正"
    case .raises: "引发"
    case .answers: "回应"
    }
}

/// Lightweight edit sheet for an existing Thought / Question. `Stage` is the
/// item's stage-or-state enum; there is no creation path here on purpose —
/// brain items form through reading (phase 17), not through a form.
private struct BrainItemEditorSheet<Stage: Hashable>: View {
    let title: String
    let textTitle: String
    @State private var text: String
    let secondaryTitle: String?
    @State private var secondaryText: String?
    let stages: [Stage]
    @State private var selectedStage: Stage
    let stageLabel: (Stage) -> String
    let onSave: (_ secondary: String?, _ text: String, _ stage: Stage) -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        textTitle: String,
        initialText: String,
        secondaryTitle: String? = nil,
        initialSecondaryText: String? = nil,
        stages: [Stage],
        selectedStage: Stage,
        stageLabel: @escaping (Stage) -> String,
        onSave: @escaping (_ secondary: String?, _ text: String, _ stage: Stage) -> Void
    ) {
        self.title = title
        self.textTitle = textTitle
        _text = State(initialValue: initialText)
        self.secondaryTitle = secondaryTitle
        _secondaryText = State(initialValue: initialSecondaryText)
        self.stages = stages
        _selectedStage = State(initialValue: selectedStage)
        self.stageLabel = stageLabel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                if let secondaryTitle {
                    TextField(secondaryTitle, text: Binding(
                        get: { secondaryText ?? "" },
                        set: { secondaryText = $0.isEmpty ? nil : $0 }
                    ))
                }
                TextField(textTitle, text: $text, axis: .vertical)
                    .lineLimit(3...8)
                Picker("状态", selection: $selectedStage) {
                    ForEach(stages, id: \.self) { stage in
                        Text(stageLabel(stage)).tag(stage)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { commit() }
                }
            }
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var secondary: String?
        if secondaryTitle != nil {
            guard let trimmedSecondary = secondaryText?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !trimmedSecondary.isEmpty else { return }
            secondary = trimmedSecondary
        }
        onSave(secondary, trimmed, selectedStage)
        dismiss()
    }
}


/// 继续想想(形态 C,phase 19):用户文字存为新反思,Agent 带着置顶的
/// brain item 流式回应。原文永远是用户的话(F9);回复沉淀在想法里。
private struct BrainDiscussionSheet: View {
    let item: BrainItem
    let runner: (String) async throws -> AsyncStream<ReaderAgentEvent>
    @State private var draft = ""
    @State private var reply = ""
    @State private var isReplying = false
    @State private var finished = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.large) {
                    VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
                        Text("正在讨论")
                            .font(.headline.weight(.semibold))
                        Text(BrainContextProvider.titleText(of: item))
                            .font(.subheadline.weight(.medium))
                    }
                    if !reply.isEmpty || isReplying {
                        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
                            Text("页外的回应")
                                .font(.headline.weight(.semibold))
                            Text(reply.isEmpty ? "…" : reply)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                    if finished {
                        Label("已存入想法", systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(Color.elsepageInteractive)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Color.elsepageDanger)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(ElsepageTheme.Spacing.page)
            }
            .background(Color.elsepageBackground)
            .navigationTitle("继续想想")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(alignment: .bottom, spacing: ElsepageTheme.Spacing.small) {
                    TextField("写下此刻的想法…", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)
                    Button(action: submit) {
                        Image(systemName: isReplying ? "ellipsis.circle" : "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(isReplying || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .frame(minHeight: 44)
                }
                .padding(ElsepageTheme.Spacing.medium)
                .background(Color.elsepageSurface)
            }
        }
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isReplying else { return }
        isReplying = true
        errorMessage = nil
        Task {
            do {
                let stream = try await runner(text)
                draft = ""
                for await event in stream {
                    switch event {
                    case .textDelta(let delta): reply += delta
                    case .completed: finished = true; isReplying = false
                    case .failed(let failure): errorMessage = String(describing: failure); isReplying = false
                    case .cancelled: isReplying = false
                    case .started, .contextPrepared, .citationsValidated, .contextDisclosed, .summaryGenerated: break
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
                isReplying = false
            }
        }
    }
}

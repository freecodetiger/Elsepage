import AchievementCore
import BrainCore
import LibraryCore
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

    @State private var expandedMemoryID: UUID?
    @State private var editingMemory: ReaderMemory?
    @State private var editText = ""
    @State private var showsClearAll = false
    @State private var showsSettings = false
    @State private var evidenceByMemory: [UUID: MemoryEvidence] = [:]
    @State private var selectedThought: Thought?
    @State private var selectedQuestion: Question?
    @State private var editingThought: Thought?
    @State private var editingQuestion: Question?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isEmpty: Bool {
        model.allMemories.isEmpty && !model.hasBrainItems
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
            stateView
                .background(Color.elsepageBackground)
                // 思想沉淀 (PRD §10.3): the first memories forming (and the empty state
                // handing over to them) land as a quiet cross-fade.
                .animation(ElsepageTheme.Motion.moment(reduceMotion), value: model.allMemories.isEmpty)
                .navigationTitle("我的头脑")
                .navigationBarTitleDisplayMode(.large)
                .task { await model.reload() }
                .toolbar { toolbarContent }
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
            Button("清除全部记忆", role: .destructive) { Task { await model.deleteAll() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会删除 Agent 记住的每一条内容，且无法撤销。")
        }
    }

    /// The body expression is deliberately split into small sub-expressions —
    /// the single-expression form outgrew the type-checker budget.
    private var stateView: some View {
        Group {
            if model.isLoading && isEmpty {
                ProgressView("正在整理对你的理解…")
            } else if isEmpty {
                emptyState
                    .transition(.moment(reduceMotion))
            } else {
                content
                    .transition(.moment(reduceMotion))
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showsSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("设置")
        }
        if !model.allMemories.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { showsClearAll = true } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("清除全部记忆")
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
            sectionsList
        }
        .navigationDestination(item: $selectedThought) { brainThoughtDestination($0) }
        .navigationDestination(item: $selectedQuestion) { brainQuestionDestination($0) }
        // Memory 更新 (PRD §10.3): confirmations/edits settle without a jump cut.
        .animation(ElsepageTheme.Motion.moment(reduceMotion), value: model.allMemories.map(\.id))
        .refreshable { await model.reload() }
    }

    private var sectionsList: some View {
        LazyVStack(alignment: .leading, spacing: ElsepageTheme.Spacing.large) {
            achievementsSection
            thoughtsSection
            questionsSection
            profileSection
            memoriesSection
        }
        .padding(ElsepageTheme.Spacing.page)
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
            onEdit: { editingThought = thought },
            onDelete: {
                Task {
                    await model.deleteThought(thought)
                    selectedThought = nil
                }
            }
        )
    }

    private func brainQuestionDestination(_ question: Question) -> some View {
        BrainQuestionDetailView(
            question: question,
            evidenceLoader: { await model.brainEvidence(for: .question(question)) },
            contextLoader: { evidence in
                await model.brainEvidenceContext(for: evidence).map {
                    MemoryEvidence(reflectionText: $0.reflectionText, book: $0.book, locator: $0.locator)
                }
            },
            openSource: openSource,
            onEdit: { editingQuestion = question },
            onDelete: {
                Task {
                    await model.deleteQuestion(question)
                    selectedQuestion = nil
                }
            }
        )
    }

    // MARK: - Thoughts / Questions (brain.md §14)

    private var thoughtsSection: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text("Thoughts · 正在形成")
                    .font(.system(.headline, design: .serif, weight: .semibold))
                Spacer()
                Text("\(model.thoughts.count) 个")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if model.thoughts.isEmpty {
                Text("你的想法还在阅读里，会随讨论逐渐成形。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.thoughts, id: \.id) { thought in
                    BrainItemRow(
                        title: thought.title,
                        preview: thought.statement,
                        badge: brainStageLabel(thought.stage),
                        updatedAt: thought.updatedAt
                    ) {
                        Haptics.cardExpanded()
                        selectedThought = thought
                    }
                }
            }
        }
    }

    private var questionsSection: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text("Questions · 还没想明白")
                    .font(.system(.headline, design: .serif, weight: .semibold))
                Spacer()
                Text("\(model.questions.count) 个")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if model.questions.isEmpty {
                Text("还没有正在追踪的问题。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.questions, id: \.id) { question in
                    BrainItemRow(
                        title: question.question,
                        preview: nil,
                        badge: brainStateLabel(question.state),
                        updatedAt: question.updatedAt
                    ) {
                        Haptics.cardExpanded()
                        selectedQuestion = question
                    }
                }
            }
        }
    }

    private var editingThoughtBinding: Binding<Bool> {
        Binding(get: { editingThought != nil }, set: { if !$0 { editingThought = nil } })
    }

    private var editingQuestionBinding: Binding<Bool> {
        Binding(get: { editingQuestion != nil }, set: { if !$0 { editingQuestion = nil } })
    }

    /// 低调徽章区(PRD F13):只列出已解锁的成就,无锁定/进度/积分。
    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text("成就")
                    .font(.system(.headline, design: .serif, weight: .semibold))
                Spacer()
                Text("\(achievements.unlocked.count) 枚")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if achievements.unlocked.isEmpty {
                Text("读完并留下想法后，会开始解锁一些有意义的徽章。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Achievement.all.filter { definition in
                    achievements.unlocked.contains { $0.id == definition.id }
                }) { definition in
                    badgeRow(definition)
                }
            }
        }
    }

    private func badgeRow(_ achievement: Achievement) -> some View {
        HStack(spacing: ElsepageTheme.Spacing.medium) {
            Image(systemName: achievement.systemImage)
                .font(.title3)
                .foregroundStyle(Color.elsepageAccent)
                .frame(width: 40, height: 40)
                .background(Color.elsepageAccent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(achievement.title).font(.subheadline.weight(.semibold))
                Text(achievement.blurb).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let record = achievements.unlocked.first(where: { $0.id == achievement.id }) {
                Text(record.unlockedAt, format: .dateTime.month().day())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(ElsepageTheme.Spacing.medium)
        .background(ElsepageTheme.MaterialToken.chrome, in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous)
                .stroke(.primary.opacity(0.06))
        }
        // A11Y-02: badge icon, title, blurb and date read as one stop.
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "这里还没有记忆",
            systemImage: "brain.head.profile",
            description: Text("读完并留下想法后，这里会慢慢成形。")
        )
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text("AI 眼中的我")
                    .font(.system(.headline, design: .serif, weight: .semibold))
                Spacer()
                Text("\(model.projection.profileTraits.count) 条理解")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if model.projection.profileTraits.isEmpty {
                Text("读完并留下想法后，这里会慢慢成形。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.projection.profileTraits) { memory in
                    row(for: memory)
                }
            }
            Text("这是我目前从阅读与讨论中形成的理解，会随你的反馈调整。")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    private var memoriesSection: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text("记忆")
                    .font(.system(.headline, design: .serif, weight: .semibold))
                Spacer()
                Text("\(model.projection.activeMemories.count) 条")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            ForEach(activeByKind, id: \.kind) { group in
                VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
                    Text(group.kind.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(group.items) { memory in
                        row(for: memory)
                    }
                }
            }
            if !model.projection.supersededMemories.isEmpty {
                VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
                    Text("已失效")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(model.projection.supersededMemories) { memory in
                        row(for: memory)
                    }
                }
            }
        }
    }

    private var activeByKind: [(kind: MemoryKind, items: [ReaderMemory])] {
        MemoryKind.allCases.compactMap { kind in
            let items = model.projection.activeMemories.filter { $0.kind == kind }
            return items.isEmpty ? nil : (kind, items)
        }
    }

    private func row(for memory: ReaderMemory) -> some View {
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

    private func startEdit(_ memory: ReaderMemory) {
        editingMemory = memory
        editText = memory.claim
    }

    private func toggleEvidence(_ memory: ReaderMemory) {
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

    private func loadEvidence(for memory: ReaderMemory) async {
        if let context = await model.evidenceContext(for: memory) {
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
}

private struct MemoryEvidence {
    let reflectionText: String
    let book: Book?
    let locator: BookLocator?
}

private struct MemoryRow: View {
    let memory: ReaderMemory
    let isExpanded: Bool
    let evidence: MemoryEvidence?
    let onToggleEvidence: () -> Void
    let onAccurate: () -> Void
    let onInaccurate: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let openSource: (Book, BookLocator) -> Void

    private var isSuperseded: Bool { memory.status == .superseded }

    var body: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
            HStack(alignment: .top, spacing: ElsepageTheme.Spacing.small) {
                kindBadge
                VStack(alignment: .leading, spacing: 4) {
                    Text(memory.claim)
                        .font(.subheadline)
                        .strikethrough(isSuperseded, color: .secondary)
                        .foregroundStyle(isSuperseded ? .secondary : .primary)
                        .lineLimit(isExpanded ? nil : 4)
                        .multilineTextAlignment(.leading)
                    metadata
                }
                Spacer(minLength: 4)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            // A11Y-02: 类型、说法、时间与置信度读作一条；操作按钮保持独立可达。
            .accessibilityElement(children: .combine)
            actions
            if isExpanded {
                evidenceBlock
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(ElsepageTheme.Spacing.medium)
        .background(ElsepageTheme.MaterialToken.chrome, in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous)
                .stroke(.primary.opacity(isSuperseded ? 0.04 : 0.06))
        }
    }

    private var kindBadge: some View {
        Text(memory.kind.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.elsepageAccent.opacity(0.12), in: Capsule())
            .foregroundStyle(Color.elsepageAccent)
    }

    private var metadata: some View {
        HStack(spacing: ElsepageTheme.Spacing.small) {
            Label(memory.userEdited ? "用户明确表达" : "AI 推断", systemImage: memory.userEdited ? "person" : "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(memory.updatedAt, format: .dateTime.month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
            if memory.userEdited {
                Label("已修改", systemImage: "pencil")
                    .font(.caption)
                    .foregroundStyle(Color.elsepageAccent)
            }
            if !memory.evidenceIDs.isEmpty {
                Text("\(memory.evidenceIDs.count) 条依据")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            Text("置信度 \(confidenceLabel(memory.confidence))")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ElsepageTheme.Spacing.small) {
                Button("准确", action: onAccurate)
                    .disabled(isSuperseded)
                Button("不准确", action: onInaccurate)
                    .disabled(isSuperseded)
                Button("修改", action: onEdit)
                    .disabled(isSuperseded)
                Button("忘记", action: onDelete)
                Button(isExpanded ? "收起依据" : "查看依据", action: onToggleEvidence)
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .tint(Color.elsepageAccent)
            // A11Y-03: keep each compact action at the 44pt minimum target.
            .frame(minHeight: 44)
        }
    }

    @ViewBuilder private var evidenceBlock: some View {
        Divider()
        if let evidence {
            VStack(alignment: .leading, spacing: 6) {
                Label("记忆来源", systemImage: "quote.bubble")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.elsepageAccent)
                Text(evidence.reflectionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                if let locator = evidence.locator, let book = evidence.book {
                    Button("回到《\(book.title)》") { openSource(book, locator) }
                        .font(.footnote.weight(.medium))
                        .tint(Color.elsepageAccent)
                }
            }
        } else {
            Text("没有可展示的来源依据")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

private extension MemoryKind {
    var displayName: String {
        switch self {
        case .episodic: "经历"
        case .semantic: "理解"
        case .preference: "偏好"
        case .openQuestion: "未解问题"
        case .profileTrait: "特质"
        }
    }
}

private func confidenceLabel(_ confidence: Double) -> String {
    if confidence >= 0.8 { "高" } else if confidence >= 0.5 { "中" } else { "低" }
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

/// A Thoughts/Questions row on the homepage: tap opens the detail view.
private struct BrainItemRow: View {
    let title: String
    let preview: String?
    let badge: String
    let updatedAt: Date
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let preview {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: ElsepageTheme.Spacing.small) {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.elsepageAccent.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.elsepageAccent)
                    Text(updatedAt, format: .dateTime.month().day())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ElsepageTheme.Spacing.medium)
            .background(ElsepageTheme.MaterialToken.chrome, in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous)
                    .stroke(.primary.opacity(0.06))
            }
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
    }
}

/// Thought detail (brain.md §15, phase-14 subset): current statement, stage,
/// evidence section, edit and delete. Evolution timeline arrives with
/// revisions (phase 18); related-item sections arrive when phase 17 starts
/// writing relations.
private struct BrainThoughtDetailView: View {
    let thought: Thought
    let evidenceLoader: () async -> [BrainEvidence]
    let revisionsLoader: () async -> [BrainItemRevision]
    let contextLoader: (BrainEvidence) async -> MemoryEvidence?
    let openSource: (Book, BookLocator) -> Void
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
                        .font(.system(.headline, design: .serif, weight: .semibold))
                    Text(thought.statement)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: ElsepageTheme.Spacing.small) {
                    Text(brainStageLabel(thought.stage))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.elsepageAccent.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.elsepageAccent)
                    Text("更新于 \(thought.updatedAt, format: .dateTime.year().month().day())")
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
                .font(.system(.headline, design: .serif, weight: .semibold))
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
                        Text(revision.createdAt, format: .dateTime.year().month())
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(ElsepageTheme.Spacing.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ElsepageTheme.MaterialToken.chrome, in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Question detail (brain.md §16, phase-14 subset): the question, its state,
/// and where it came from. "正在形成的答案" arrives when phase 17 writes
/// addresses relations.
private struct BrainQuestionDetailView: View {
    let question: Question
    let evidenceLoader: () async -> [BrainEvidence]
    let contextLoader: (BrainEvidence) async -> MemoryEvidence?
    let openSource: (Book, BookLocator) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var showsDelete = false
    @State private var evidence: [BrainEvidence] = []
    @State private var contexts: [String: MemoryEvidence] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.large) {
                VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
                    Text("问题")
                        .font(.system(.headline, design: .serif, weight: .semibold))
                    Text(question.question)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: ElsepageTheme.Spacing.small) {
                    Text(brainStateLabel(question.state))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.elsepageAccent.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.elsepageAccent)
                    Text("更新于 \(question.updatedAt, format: .dateTime.year().month().day())")
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
        .navigationTitle("还没想明白")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadEvidence() }
        .toolbar {
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
                .font(.system(.headline, design: .serif, weight: .semibold))
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
                            .foregroundStyle(Color.elsepageAccent)
                    }
                    Text(brainRelationLabel(row.relation))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let book = context.book, let locator = context.locator {
                    Button("回到《\(book.title)》") { openSource(book, locator) }
                        .font(.footnote.weight(.medium))
                        .tint(Color.elsepageAccent)
                }
            }
            .padding(ElsepageTheme.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ElsepageTheme.MaterialToken.chrome, in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous))
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
                    .background(Color.elsepageAccent.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.elsepageAccent)
                Text(brainRelationLabel(row.relation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
            }
            .padding(ElsepageTheme.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ElsepageTheme.MaterialToken.chrome, in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous))
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

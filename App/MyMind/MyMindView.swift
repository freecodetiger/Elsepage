import AchievementCore
import LibraryCore
import ReaderCore
import ReflectionCore
import SwiftUI

/// WS2 "My Mind" / "AI 眼中的我". Shows what the Agent remembers about the
/// reader. Every memory is traceable to its source reflection and mutable
/// (准确 / 不准确 / 修改 / 忘记 / 查看依据 / 一键清除). The tone is "这是我目前
/// 从阅读与讨论中形成的理解" — never a psychological-diagnosis vibe.
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
            Group {
                if model.isLoading && model.allMemories.isEmpty {
                    ProgressView("正在整理对你的理解…")
                } else if model.allMemories.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .background(Color.elsepageBackground)
            .navigationTitle("我的头脑")
            .navigationBarTitleDisplayMode(.large)
            .task { await model.reload() }
            .toolbar {
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
                Button("保存") {
                    let claim = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let memory = editingMemory, !claim.isEmpty else { return }
                    Task { await model.edit(memory, newClaim: claim) }
                }
            }
            .confirmationDialog("清除全部记忆？", isPresented: $showsClearAll, titleVisibility: .visible) {
                Button("清除全部记忆", role: .destructive) { Task { await model.deleteAll() } }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这会删除 Agent 记住的每一条内容，且无法撤销。")
            }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ElsepageTheme.Spacing.large) {
                profileSection
                achievementsSection
                memoriesSection
            }
            .padding(ElsepageTheme.Spacing.page)
        }
        .refreshable { await model.reload() }
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
            }
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
            Text("\(Int(memory.confidence * 100))%")
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
            .controlSize(.small)
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

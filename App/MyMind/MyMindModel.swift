import AchievementCore
import BrainCore
import Foundation
import LibraryCore
import Observation
import ReaderAgent
import ReaderCore
import ReflectionCore

/// 继续想想不可用(Agent 未装配/书架空/文字为空)。
struct ReflectionAgentUnavailable: Error {}

/// Presentation state for the "我的大脑" surface (docs/brain.md §14). All three
/// sections read the Brain store (brainItems) — since phase 17 the projection
/// service is the single production writer for memories, so the legacy
/// `memories` table is retired from this UI (v21 backfill covered old rows).
/// Every memory is traceable to its source reflection and mutable
/// (准确 / 不准确 / 修改 / 忘记 / 一键清除); Thought/Question are editable but
/// never manually created — they form through reading.
@MainActor @Observable
final class MyMindModel {
    private let brain: any BrainRepository
    private let reflections: any ReflectionRepository
    private let books: any BookRepository
    /// 继续想想(phase 19,形态 C):nil → 详情页按钮隐藏。
    private let readerAgent: ReaderAgent?
    /// FIX-03: 修改/不准确 are the deterministic "Changed My Mind" signals —
    /// fired only on the user's own action, never on Agent inference.
    let achievements: AchievementModel?

    private(set) var memories: [BrainMemory] = []
    private(set) var thoughts: [Thought] = []
    private(set) var questions: [Question] = []
    private(set) var isLoading = false
    var errorMessage: String?

    init(
        brain: any BrainRepository,
        reflections: any ReflectionRepository,
        books: any BookRepository,
        achievements: AchievementModel? = nil,
        readerAgent: ReaderAgent? = nil
    ) {
        self.brain = brain
        self.reflections = reflections
        self.books = books
        self.achievements = achievements
        self.readerAgent = readerAgent
    }

    /// The live memory list (most recently updated first).
    var activeMemories: [BrainMemory] {
        memories.filter { $0.state != .superseded && $0.state != .forgotten }
    }

    /// The audit trail: 不准确 / 忘记 rows, shown struck-through.
    var retiredMemories: [BrainMemory] {
        memories.filter { $0.state == .superseded || $0.state == .forgotten }
    }

    /// 继续想想的可用性:需要 Agent,且书架非空(反思必须挂一本书)。
    var canContinueThinking: Bool { readerAgent != nil }

    /// Brain items form only through reading (phase 17); before that the two
    /// sections stay intentionally empty instead of offering a manager UI.
    var hasBrainItems: Bool { !thoughts.isEmpty || !questions.isEmpty }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let brainItems = try await brain.items()
            memories = brainItems.compactMap { item in
                if case .memory(let memory) = item { return memory } else { return nil }
            }.sorted { $0.updatedAt > $1.updatedAt }
            thoughts = brainItems.compactMap { item in
                if case .thought(let thought) = item { return thought } else { return nil }
            }.sorted { $0.updatedAt > $1.updatedAt }
            questions = brainItems.compactMap { item in
                if case .question(let question) = item { return question } else { return nil }
            }.sorted { $0.updatedAt > $1.updatedAt }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Memory mutations (brain store)

    /// User agrees with this memory: active + high confidence.
    func confirm(_ memory: BrainMemory) async {
        var updated = memory
        updated.state = .active
        updated.confidence = .high
        updated.updatedAt = Date()
        await persistBrainItem(.memory(updated))
    }

    /// User says this memory is inaccurate → superseded (audit trail, not a delete).
    /// A user-driven supersede is one of the two "Changed My Mind" signals (FIX-03).
    func markInaccurate(_ memory: BrainMemory) async {
        var updated = memory
        updated.state = .superseded
        updated.updatedAt = Date()
        await persistBrainItem(.memory(updated))
        await recordChangeOfMind()
    }

    /// User edits the claim: the claim becomes user-explicit knowledge (and the
    /// old wording lands in revisions when it differs — traceable like any
    /// other update). A user-driven revise is the other "Changed My Mind" signal.
    func edit(_ memory: BrainMemory, newClaim: String) async {
        let trimmed = newClaim.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if memory.content != trimmed {
            try? await brain.recordRevision(itemID: memory.id, content: memory.content, triggerEvidenceID: nil)
        }
        var updated = memory
        updated.content = trimmed
        updated.origin = .userExplicit
        updated.state = .active
        updated.updatedAt = Date()
        await persistBrainItem(.memory(updated))
        await recordChangeOfMind()
    }

    func delete(_ memory: BrainMemory) async {
        await deleteBrainItem(id: memory.id)
    }

    func deleteAllMemories() async {
        for memory in memories {
            try? await brain.delete(id: memory.id)
        }
        await reload()
    }

    /// Resolves a memory's source reflection (provenance or its evidence rows)
    /// so the UI can show the original words and jump to the passage. Nil when
    /// the source no longer exists (soft-dangling) or was never recorded.
    func memoryEvidenceContext(for memory: BrainMemory) async -> (reflectionText: String, book: Book?, locator: BookLocator?)? {
        var reflectionIDs: [String] = []
        if case .reflection(let id) = memory.provenance.originEvidence {
            reflectionIDs.append(id)
        }
        for row in await brainEvidence(for: .memory(memory)) {
            if case .reflection(let id) = row.source, !reflectionIDs.contains(id) {
                reflectionIDs.append(id)
            }
        }
        for id in reflectionIDs {
            guard let uuid = UUID(uuidString: id) else { continue }
            let reflectionID = ReflectionID(rawValue: uuid)
            guard let reflection = try? await reflections.reflection(id: reflectionID) else { continue }
            let rows = (try? await reflections.evidence(for: reflectionID)) ?? []
            let locator = rows.first(where: { $0.sourceType == .bookLocator })?.locator
            let book = try? await books.book(id: reflection.bookID)
            return (reflection.originalText, book, locator)
        }
        return nil
    }

    // MARK: - 继续想想(phase 19,形态 C)

    /// 讨论挂书规则:item 最近一条反思证据的书;无证据回退最近打开的书;
    /// 书架空 → nil(按钮隐藏/禁用)。
    func discussionBook(for item: BrainItem) async -> Book? {
        let evidence = await brainEvidence(for: item)
        for row in evidence.reversed() {
            if case .reflection(let id) = row.source, let uuid = UUID(uuidString: id) {
                let reflectionID = ReflectionID(rawValue: uuid)
                if let reflection = try? await reflections.reflection(id: reflectionID),
                   let book = try? await books.book(id: reflection.bookID) {
                    return book
                }
            }
        }
        let library = (try? await books.allBooks()) ?? []
        return library.sorted {
            ($0.lastOpenedAt ?? $0.importedAt) > ($1.lastOpenedAt ?? $1.importedAt)
        }.first
    }

    /// 继续想想:用户文字存为新反思(原文永远是用户的话),Agent 带
    /// pinned 上下文回复。反思先持久化,再走主链——投影服务会自然观察它。
    func continueThinking(item: BrainItem, text: String) async throws -> AsyncStream<ReaderAgentEvent> {
        guard let readerAgent else { throw ReflectionAgentUnavailable() }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ReflectionAgentUnavailable() }
        guard let book = await discussionBook(for: item) else { throw ReflectionAgentUnavailable() }
        let reflection = Reflection(bookID: book.id, originalText: trimmed, inputKind: .text)
        try await reflections.insert(reflection, linkedHighlightIDs: [], evidence: [])
        return readerAgent.respond(to: reflection.id, activeBrain: item)
    }

    // MARK: - Brain evidence / revisions

    /// Brain-evidence rows for one item. Best-effort: a lookup failure yields
    /// an empty list, never an error state.
    func brainEvidence(for item: BrainItem) async -> [BrainEvidence] {
        guard let evidence = try? await brain.evidence(for: item.id) else { return [] }
        return evidence
    }

    /// Rewrite history for a brain item (phase 18). Best-effort like evidence.
    func brainRevisions(for item: BrainItem) async -> [BrainItemRevision] {
        (try? await brain.revisions(for: item.id)) ?? []
    }

    /// Resolves a reflection-sourced brain evidence row into displayable
    /// context (original words + book + jump target). Nil for non-reflection
    /// sources and for soft-dangling rows whose reflection was deleted.
    func brainEvidenceContext(for evidence: BrainEvidence) async -> (reflectionText: String, book: Book?, locator: BookLocator?)? {
        guard case .reflection(let id) = evidence.source,
              let uuid = UUID(uuidString: id) else { return nil }
        let reflectionID = ReflectionID(rawValue: uuid)
        guard let reflection = try? await reflections.reflection(id: reflectionID) else { return nil }
        let rows = (try? await reflections.evidence(for: reflectionID)) ?? []
        let locator = rows.first(where: { $0.sourceType == .bookLocator })?.locator
        let book = try? await books.book(id: reflection.bookID)
        return (reflection.originalText, book, locator)
    }

    // MARK: - Thoughts / Questions

    /// Edits an existing thought. No manual creation: thoughts form through
    /// reading, never through a form (brain.md §14 — the homepage is not a
    /// database manager). The replaced statement is recorded as a revision so
    /// the user's own edits stay traceable (phase 18).
    func editThought(_ thought: Thought, title: String, statement: String, stage: ThoughtStage) async {
        if thought.statement != statement {
            try? await brain.recordRevision(itemID: thought.id, content: thought.statement, triggerEvidenceID: nil)
        }
        var updated = thought
        updated.title = title
        updated.statement = statement
        updated.stage = stage
        updated.updatedAt = Date()
        await persistBrainItem(.thought(updated))
    }

    func editQuestion(_ question: Question, text: String, state: QuestionState) async {
        var updated = question
        updated.question = text
        updated.state = state
        updated.updatedAt = Date()
        await persistBrainItem(.question(updated))
    }

    func deleteThought(_ thought: Thought) async {
        await deleteBrainItem(id: thought.id)
    }

    func deleteQuestion(_ question: Question) async {
        await deleteBrainItem(id: question.id)
    }

    private func persistBrainItem(_ item: BrainItem) async {
        do {
            try await brain.save(item)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteBrainItem(id: BrainItemID) async {
        do {
            try await brain.delete(id: id)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Emits the Changed My Mind achievement moment (FIX-03). An achievement miss
    /// must never disturb the memory flow, mirroring the reflection path.
    private func recordChangeOfMind() async {
        await achievements?.handle(.userMemoryRevision(now: Date()))
    }
}

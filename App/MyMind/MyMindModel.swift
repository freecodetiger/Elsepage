import AchievementCore
import BrainCore
import Foundation
import LibraryCore
import Observation
import ReaderCore
import ReflectionCore

/// Presentation state for the "我的大脑" surface (docs/brain.md §14): Thoughts /
/// Questions come from the Brain store (brainItems), Memories keep reading the
/// legacy memory store until BrainProjectionService (phase 17) becomes the
/// single writer. Every memory is traceable to its source reflection and
/// mutable (准确 / 不准确 / 修改 / 忘记 / 一键清除); Thought/Question are
/// editable but never manually created — they form through reading (phase 17).
@MainActor @Observable
final class MyMindModel {
    private let memories: any MemoryRepository
    private let brain: any BrainRepository
    private let reflections: any ReflectionRepository
    private let books: any BookRepository
    /// FIX-03: 修改/不准确 are the deterministic "Changed My Mind" signals —
    /// fired only on the user's own action, never on Agent inference.
    let achievements: AchievementModel?

    private(set) var allMemories: [ReaderMemory] = []
    private(set) var thoughts: [Thought] = []
    private(set) var questions: [Question] = []
    private(set) var isLoading = false
    var errorMessage: String?

    init(
        memories: any MemoryRepository,
        brain: any BrainRepository,
        reflections: any ReflectionRepository,
        books: any BookRepository,
        achievements: AchievementModel? = nil
    ) {
        self.memories = memories
        self.brain = brain
        self.reflections = reflections
        self.books = books
        self.achievements = achievements
    }

    /// The deterministic "AI 眼中的我" projection of the current store.
    var projection: ReaderProfileProjection {
        ReaderProfileProjection(memories: allMemories)
    }

    /// Brain items form only through reading (phase 17); before that the two
    /// sections stay intentionally empty instead of offering a manager UI.
    var hasBrainItems: Bool { !thoughts.isEmpty || !questions.isEmpty }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            allMemories = try await memories.memories()
            let brainItems = try await brain.items()
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

    /// User agrees with this memory: promote it out of provisional and raise confidence.
    func confirm(_ memory: ReaderMemory) async {
        var updated = memory
        updated.status = .active
        updated.confidence = max(updated.confidence, 0.85)
        updated.updatedAt = Date()
        await persist(updated)
    }

    /// User says this memory is inaccurate → superseded (audit trail, not a delete).
    /// A user-driven supersede is one of the two "Changed My Mind" signals (FIX-03).
    func markInaccurate(_ memory: ReaderMemory) async {
        do {
            try await memories.markInaccurate(id: memory.id)
            await reload()
            await recordChangeOfMind()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// User edits the claim. Marked `userEdited` so the pipeline never overwrites it.
    /// A user-driven revise is one of the two "Changed My Mind" signals (FIX-03).
    func edit(_ memory: ReaderMemory, newClaim: String) async {
        var updated = memory
        updated.claim = newClaim
        updated.userEdited = true
        updated.updatedAt = Date()
        if await persist(updated) {
            await recordChangeOfMind()
        }
    }

    func delete(_ memory: ReaderMemory) async {
        do {
            try await memories.delete(id: memory.id)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAll() async {
        do {
            try await memories.deleteAll()
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Resolves a memory back to the source reflection it was derived from, so the
    /// UI can show the original words and jump to the passage. Returns nil when the
    /// source reflection no longer exists (cascade-deleted) or was never recorded.
    func evidenceContext(for memory: ReaderMemory) async -> (reflectionText: String, book: Book?, locator: BookLocator?)? {
        guard let sourceID = memory.sourceReflectionID,
              let reflection = try? await reflections.reflection(id: sourceID) else { return nil }
        let evidence = (try? await reflections.evidence(for: sourceID)) ?? []
        let locator = evidence.first(where: { $0.sourceType == .bookLocator })?.locator
        let book = try? await books.book(id: reflection.bookID)
        return (reflection.originalText, book, locator)
    }

    @discardableResult
    private func persist(_ memory: ReaderMemory) async -> Bool {
        do {
            try await memories.save(memory)
            await reload()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Emits the Changed My Mind achievement moment (FIX-03). An achievement miss
    /// must never disturb the memory flow, mirroring the reflection path.
    private func recordChangeOfMind() async {
        await achievements?.handle(.userMemoryRevision(now: Date()))
    }

    // MARK: - Thoughts / Questions (brainItems)

    /// Edits an existing thought. No manual creation: thoughts form through
    /// reading, never through a form (brain.md §14 — the homepage is not a
    /// database manager).
    func editThought(_ thought: Thought, title: String, statement: String, stage: ThoughtStage) async {
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
}

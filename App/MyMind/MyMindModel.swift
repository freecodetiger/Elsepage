import Foundation
import LibraryCore
import Observation
import ReaderCore
import ReflectionCore

/// Presentation state for the "My Mind" surface. Loads the memory store, computes
/// the evidence-based profile projection, and owns every mutation the user can
/// make (准确 / 不准确 / 修改 / 忘记 / 一键清除). User edits are marked
/// `userEdited` so the automatic pipeline never overwrites them (P7).
@MainActor @Observable
final class MyMindModel {
    private let memories: any MemoryRepository
    private let reflections: any ReflectionRepository
    private let books: any BookRepository

    private(set) var allMemories: [ReaderMemory] = []
    private(set) var isLoading = false
    var errorMessage: String?

    init(
        memories: any MemoryRepository,
        reflections: any ReflectionRepository,
        books: any BookRepository
    ) {
        self.memories = memories
        self.reflections = reflections
        self.books = books
    }

    /// The deterministic "AI 眼中的我" projection of the current store.
    var projection: ReaderProfileProjection {
        ReaderProfileProjection(memories: allMemories)
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            allMemories = try await memories.memories()
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
    func markInaccurate(_ memory: ReaderMemory) async {
        do {
            try await memories.markInaccurate(id: memory.id)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// User edits the claim. Marked `userEdited` so the pipeline never overwrites it.
    func edit(_ memory: ReaderMemory, newClaim: String) async {
        var updated = memory
        updated.claim = newClaim
        updated.userEdited = true
        updated.updatedAt = Date()
        await persist(updated)
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

    private func persist(_ memory: ReaderMemory) async {
        do {
            try await memories.save(memory)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

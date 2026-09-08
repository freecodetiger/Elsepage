import Foundation

/// docs/brain.md §18 lifecycle actions. Deterministic: user action in,
/// repository writes out. Idempotent via the relation triple PK — calling twice
/// never duplicates a memory or a relation. These are RELATIONS, not data
/// conversion: both records keep existing ("两条记录仍然存在", §18).
public enum BrainLifecycle {
    /// Stable/confirmed Thought → Memory via `derivedMemory`. No-op when this
    /// thought already has a derivedMemory relation (idempotent per thought) or
    /// is archived. The derived memory inherits the thought's provenance and
    /// wording, but carries its own origin (`.derivedFromThought`), state
    /// `.active`, confidence `.high`. Returns the new memory id, or nil if no-op.
    public static func archiveAsMemory(_ thought: Thought, brain: any BrainRepository) async throws -> BrainItemID? {
        guard thought.stage != .archived else { return nil }
        let existing = try await brain.relations(of: thought.id)
        let alreadyDerived = existing.contains { $0.sourceItemID == thought.id && $0.relation == .derivedMemory }
        guard !alreadyDerived else { return nil }
        let memory = BrainMemory(
            id: BrainItemID(rawValue: UUID().uuidString.lowercased()),
            content: thought.statement,
            origin: .derivedFromThought,
            confidence: .high,
            state: .active,
            provenance: thought.provenance,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await brain.save(.memory(memory))
        try await brain.relate(source: thought.id, target: memory.id, relation: .derivedMemory, weight: 1)
        return memory.id
    }

    /// Resolved Question → answering Thought via `addresses`, and marks the
    /// question `.resolved`. Idempotent per (question, thought, addresses); safe
    /// to call more than once.
    public static func resolveQuestion(_ question: Question, answeredBy thoughtID: BrainItemID, brain: any BrainRepository) async throws {
        try await brain.relate(source: question.id, target: thoughtID, relation: .addresses, weight: 1)
        var updated = question
        updated.state = .resolved
        updated.updatedAt = Date()
        try await brain.save(.question(updated))
    }
}

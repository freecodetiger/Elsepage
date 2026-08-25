import Foundation

/// Applies a derived `JournalMemoryChange` to the long-term Memory store.
///
/// Semantics:
/// - `store` creates a new provisional memory (confidence 0.6) carrying the
///   originating evidence IDs. Re-applying the same claim for the same source
///   reflection is a no-op, so materialization stays idempotent.
/// - `reinforce` raises confidence (+0.15, capped at 0.95) and touches
///   `updatedAt`. User-edited or superseded memories are never touched.
/// - `revise` overwrites the claim. User-edited or superseded memories are
///   never overwritten (P2: AI must not overwrite a user's edit or resurrect
///   a retired memory).
///
/// Target matching is summary-based: the change's `summary` is matched against
/// the claims of memories derived from the same source Reflection, preferring
/// the most recently updated one. The Agent's `memoryID` is advisory only and
/// not persisted, so summary is the reliable key.
public struct MemoryApplicationService: Sendable {
    private let repository: any MemoryRepository

    public init(repository: any MemoryRepository) {
        self.repository = repository
    }

    public func apply(
        _ change: JournalMemoryChange,
        sourceReflectionID: ReflectionID,
        evidence: [String]
    ) async throws {
        switch change.changeType {
        case .store:
            try await store(change, sourceReflectionID: sourceReflectionID, evidence: evidence)
        case .reinforce:
            try await reinforce(change, sourceReflectionID: sourceReflectionID)
        case .revise:
            try await revise(change, sourceReflectionID: sourceReflectionID)
        }
    }

    // MARK: - Private

    private func store(
        _ change: JournalMemoryChange, sourceReflectionID: ReflectionID, evidence: [String]
    ) async throws {
        let existing = try await repository.memories().first {
            $0.sourceReflectionID == sourceReflectionID && $0.claim == change.summary
        }
        guard existing == nil else { return }
        let now = Date()
        try await repository.save(ReaderMemory(
            sourceReflectionID: sourceReflectionID,
            kind: .semantic,
            claim: change.summary,
            confidence: 0.6,
            status: .provisional,
            evidenceIDs: evidence,
            createdAt: now,
            updatedAt: now
        ))
    }

    private func reinforce(_ change: JournalMemoryChange, sourceReflectionID: ReflectionID) async throws {
        guard let target = try await target(for: change, sourceReflectionID: sourceReflectionID),
              !target.userEdited, target.status != .superseded else { return }
        var updated = target
        updated.confidence = min(0.95, target.confidence + 0.15)
        updated.updatedAt = Date()
        try await repository.save(updated)
    }

    private func revise(_ change: JournalMemoryChange, sourceReflectionID: ReflectionID) async throws {
        guard let target = try await target(for: change, sourceReflectionID: sourceReflectionID),
              !target.userEdited, target.status != .superseded else { return }
        var updated = target
        updated.claim = change.summary
        updated.updatedAt = Date()
        try await repository.save(updated)
    }

    private func target(
        for change: JournalMemoryChange, sourceReflectionID: ReflectionID
    ) async throws -> ReaderMemory? {
        let candidates = try await repository.memories().filter {
            $0.sourceReflectionID == sourceReflectionID
                && ($0.claim == change.summary
                    || $0.claim.contains(change.summary)
                    || change.summary.contains($0.claim))
        }
        return candidates.max { $0.updatedAt < $1.updatedAt }
    }
}

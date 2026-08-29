import Foundation

/// Persists brain items. The protocol lives in BrainCore so the domain never
/// depends on GRDB or Persistence; the concrete repository is the integration
/// point (and later, so does BrainContextProvider — Phase 16).
public protocol BrainRepository: Sendable {
    /// All items, oldest first (createdAt, then id — deterministic).
    func items() async throws -> [BrainItem]
    /// All items of one kind, same ordering.
    func items(kind: BrainItemKind) async throws -> [BrainItem]
    func item(id: BrainItemID) async throws -> BrainItem?
    /// Upsert. Content must be non-empty after trimming.
    func save(_ item: BrainItem) async throws
    func delete(id: BrainItemID) async throws

    // MARK: Evidence (docs/brain.md §4)

    /// Evidence attached to one item, oldest first, then by source identity —
    /// deterministic for stable UI.
    func evidence(for itemID: BrainItemID) async throws -> [BrainEvidence]
    /// Attaches evidence. Idempotent: the same (item, source, relation) pair
    /// never produces a second row. `weight` is 0...1.
    func attachEvidence(_ itemID: BrainItemID, source: BrainEvidenceSource, relation: EvidenceRelation, weight: Double) async throws

    // MARK: Relations (docs/brain.md §5)

    /// All relations touching `itemID`, normalized source→target regardless of
    /// stored direction.
    func relations(of itemID: BrainItemID) async throws -> [BrainRelation]
    /// Creates or refreshes a directed relation. Idempotent per
    /// (source, target, relation). `source` must differ from `target`.
    func relate(source: BrainItemID, target: BrainItemID, relation: BrainRelationType, weight: Double) async throws
}

public enum BrainItemValidationError: Error, Equatable {
    case emptyContent
    /// A persisted row violated the per-kind invariants (unknown kind/state
    /// combination). Database CHECKs are the first line of defense; this is the
    /// decode-time guard so a bad row can never surface as a wrong-typed value.
    case stateMismatch
    /// A self-relation (source == target) is not representable — relations
    /// connect distinct brain items.
    case selfRelation
}

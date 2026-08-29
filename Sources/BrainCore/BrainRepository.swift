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
}

public enum BrainItemValidationError: Error, Equatable {
    case emptyContent
    /// A persisted row violated the per-kind invariants (unknown kind/state
    /// combination). Database CHECKs are the first line of defense; this is the
    /// decode-time guard so a bad row can never surface as a wrong-typed value.
    case stateMismatch
}

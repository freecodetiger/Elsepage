import Foundation

/// One historical version of a brain item's distilled content (docs/brain.md
/// §10): written whenever an update REPLACES the statement — by the projection
/// service or by the user's own edit. `update` never overwrites silently; the
/// old wording lands here so the evolution timeline is traceable.
public struct BrainItemRevision: Hashable, Sendable {
    public let itemID: BrainItemID
    /// Per-item sequence number starting at 1 (the item's first rewrite).
    public let revision: Int
    public let content: String
    /// Reflection that triggered the rewrite; nil for user edits.
    public let triggerEvidenceID: String?
    public let createdAt: Date

    public init(itemID: BrainItemID, revision: Int, content: String, triggerEvidenceID: String?, createdAt: Date) {
        self.itemID = itemID
        self.revision = revision
        self.content = content
        self.triggerEvidenceID = triggerEvidenceID
        self.createdAt = createdAt
    }
}

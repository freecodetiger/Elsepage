import Foundation

/// A persisted embedding for one brain item under one embedding model.
/// Vectors are created once and reused across queries (docs/brain.md §6) —
/// `contentHash` guards against re-embedding unchanged content.
public struct BrainItemVector: Hashable, Sendable {
    public let itemID: BrainItemID
    public let model: String
    public let dimensions: Int
    public let contentHash: String
    public let vector: [Float]
    public let updatedAt: Date

    public init(itemID: BrainItemID, model: String, dimensions: Int, contentHash: String, vector: [Float], updatedAt: Date) {
        self.itemID = itemID
        self.model = model
        self.dimensions = dimensions
        self.contentHash = contentHash
        self.vector = vector
        self.updatedAt = updatedAt
    }
}

/// Persists brain-item vectors. The protocol lives in BrainCore next to the
/// domain; the GRDB implementation is the integration point. Rows are keyed by
/// (item, model): switching models keeps old rows (same policy as
/// bookChunkEmbeddings), and item deletion cascades its vectors.
public protocol BrainEmbeddingStore: Sendable {
    func vectors(model: String) async throws -> [BrainItemVector]
    func save(_ vectors: [BrainItemVector]) async throws
}

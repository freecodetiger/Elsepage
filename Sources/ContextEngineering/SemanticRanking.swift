import Foundation

/// Semantic recall seam for reflection/memory retrieval. Upper-level retrieval
/// depends only on this protocol; a query-time embed+cache implementation and a
/// future persistent vector index both conform without rewriting retrieval
/// semantics. Absence (nil / empty scores) degrades to the existing lexical path.
public protocol SemanticRanking: Sendable {
    /// Cosine similarity of every eligible item to the query. Returns nil when no
    /// provider is available or embedding fails — callers fall back to lexical-only.
    func scores(query: String, items: [(id: String, text: String)], source: ContextSource) async -> SemanticScores?
    /// Cumulative process-local cache hit/miss counts across calls (for traces).
    var cacheHitMiss: (hits: Int, misses: Int) { get }
}

/// Result of a semantic pass: per-item similarity plus observability counts.
public struct SemanticScores: Sendable {
    public let scores: [String: Double]
    public let stats: SemanticVectorStats

    public init(scores: [String: Double], stats: SemanticVectorStats) {
        self.scores = scores
        self.stats = stats
    }
}

/// Observability for one semantic retrieval pass.
public struct SemanticVectorStats: Hashable, Sendable {
    public let eligibleCount: Int
    /// Texts actually sent to the embedding provider this pass (query + misses).
    public let embeddedCount: Int
    public let cacheHits: Int
    public let cacheMisses: Int
    public let durationSeconds: Double

    public init(eligibleCount: Int, embeddedCount: Int, cacheHits: Int, cacheMisses: Int, durationSeconds: Double) {
        self.eligibleCount = eligibleCount
        self.embeddedCount = embeddedCount
        self.cacheHits = cacheHits
        self.cacheMisses = cacheMisses
        self.durationSeconds = durationSeconds
    }

    public static let zero = SemanticVectorStats(eligibleCount: 0, embeddedCount: 0, cacheHits: 0, cacheMisses: 0, durationSeconds: 0)
}

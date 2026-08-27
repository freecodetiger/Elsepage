import Foundation

/// A context unit selected for the prompt, after ranking/dedup/budgeting. The
/// assembly layer packs candidates into a `ContextBundle`. Scores are simple and
/// deterministic in the first version; the shape leaves room for richer modeling.
public struct ContextCandidate: Hashable, Sendable {
    public let id: String
    public let source: ContextSource
    public let content: String
    public let relevance: Double
    public let confidence: Double?
    public let tokenCost: Int
    public let importance: Double?
    /// Provenance forwarded to citation validation / persistence.
    public let metadata: [String: String]

    public init(
        id: String,
        source: ContextSource,
        content: String,
        relevance: Double,
        confidence: Double? = nil,
        tokenCost: Int = 0,
        importance: Double? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.source = source
        self.content = content
        self.relevance = relevance
        self.confidence = confidence
        self.tokenCost = tokenCost
        self.importance = importance
        self.metadata = metadata
    }

    /// Rough char-based cost approximation; sources supply the real budget later.
    public var estimatedCharacterCount: Int { content.count }
}

/// The bounded, ranked set of context candidates handed to ReaderAgent after the
/// planner's intent, source selection, dedup, and token budgeting have run.
public struct ContextBundle: Hashable, Sendable {
    public let candidates: [ContextCandidate]

    public init(candidates: [ContextCandidate]) { self.candidates = candidates }

    public static let empty = ContextBundle(candidates: [])
}

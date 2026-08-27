import Foundation
import ReflectionCore

/// Source-specific past-reflection retrieval. Lexical-only by default (the
/// existing `ReflectionLexicalMatcher` behavior); when a `SemanticRanking` is
/// injected, the lexical lane is fused with an INDEPENDENT semantic recall lane
/// over the bounded eligible set — so a reflection the lexical matcher misses can
/// still be recalled semantically. Same-book-first preference and connection
/// persistence stay with the caller.
public struct ReflectionRetriever: Sendable {
    private let semantic: (any SemanticRanking)?
    /// Cosine floor for the semantic lane; below it a candidate isn't recalled.
    private let semanticThreshold: Double
    /// Bound on the eligible set per call (most recent first) so the query-time
    /// embed stays cheap; the set is the source-scope policy, NOT the lexical top-N.
    private let maxEligibleCandidates: Int

    public init(
        semantic: (any SemanticRanking)? = nil,
        semanticThreshold: Double = 0.2,
        maxEligibleCandidates: Int = 30
    ) {
        self.semantic = semantic
        self.semanticThreshold = semanticThreshold
        self.maxEligibleCandidates = max(1, maxEligibleCandidates)
    }

    public func strongestMatch(for query: String, among candidates: [Reflection]) async -> ReflectionLexicalMatcher.Match? {
        let lexical = ReflectionLexicalMatcher.strongestMatch(for: query, among: candidates)
        guard let semantic else { return lexical }
        let eligible = Array(candidates.sorted { $0.createdAt > $1.createdAt }.prefix(maxEligibleCandidates))
        guard let result = await semantic.scores(
            query: query,
            items: eligible.map { (id: $0.id.description, text: $0.originalText) },
            source: .pastReflection
        ), !result.scores.isEmpty else { return lexical }

        let lexicalList = eligible.compactMap { ref -> (Reflection, Double)? in
            ReflectionLexicalMatcher.lexicalRelevance(query: query, candidate: ref).map { (ref, $0) }
        }.sorted { $0.1 > $1.1 }
        let semanticList = eligible.compactMap { ref -> (Reflection, Double)? in
            guard let score = result.scores[ref.id.description], score > semanticThreshold else { return nil }
            return (ref, score)
        }.sorted { $0.1 > $1.1 }
        guard let best = HybridFusion.ranked(id: { $0.id }, lexical: lexicalList, semantic: semanticList).first else { return lexical }
        return ReflectionLexicalMatcher.Match(reflection: best.item, relevance: best.score)
    }
}

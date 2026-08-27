import Foundation
import ReflectionCore

/// Source-specific long-term memory retrieval. Lexical-only by default (the
/// prior ReaderAgent behavior); with a `SemanticRanking` the lexical lane fuses
/// with an INDEPENDENT semantic recall lane over the bounded eligible set, so a
/// semantically related memory the lexical matcher misses can still be recalled.
/// Memories surface as evidence only and never create a connection — the
/// memory/reflection semantic boundary is structural (separate retrievers).
public struct MemoryRetriever: Sendable {
    private let semantic: (any SemanticRanking)?
    /// Cosine floor for the semantic lane.
    private let semanticThreshold: Double
    /// Bound on the eligible set (most recent active memories first).
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

    /// Matches the routing text against long-term memory claims using the same
    /// CJK-aware tokenization as `ReflectionLexicalMatcher`. A lighter lexical
    /// relevance bar than the reflection matcher (memory claims are distilled and
    /// short); non-active memories are ignored.
    public func matchingMemories(
        routingText: String,
        in repository: (any MemoryRepository)?,
        topN: Int
    ) async -> [ReaderMemory] {
        guard let repository, !routingText.isEmpty else { return [] }
        let queryTokens = ReflectionLexicalMatcher.tokens(in: routingText)
        guard queryTokens.count >= 2 else { return [] }
        let all = (try? await repository.memories()) ?? []
        let eligible = Array(
            all.filter { $0.status != .superseded }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(maxEligibleCandidates)
        )
        let lexicalList = eligible.compactMap { memory -> (ReaderMemory, Double)? in
            let claimTokens = ReflectionLexicalMatcher.tokens(in: memory.claim)
            let overlap = queryTokens.intersection(claimTokens).count
            guard overlap >= 2 else { return nil }
            let relevance = Double(overlap) / Double(max(1, min(queryTokens.count, claimTokens.count)))
            guard relevance >= 0.30 else { return nil }
            return (memory, relevance)
        }.sorted { $0.1 > $1.1 }

        guard let semantic else { return Array(lexicalList.prefix(topN).map(\.0)) }
        guard let result = await semantic.scores(
            query: routingText,
            items: eligible.map { (id: $0.id.uuidString.lowercased(), text: $0.claim) },
            source: .memory
        ), !result.scores.isEmpty else { return Array(lexicalList.prefix(topN).map(\.0)) }

        let semanticList = eligible.compactMap { memory -> (ReaderMemory, Double)? in
            guard let score = result.scores[memory.id.uuidString.lowercased()], score > semanticThreshold else { return nil }
            return (memory, score)
        }.sorted { $0.1 > $1.1 }
        let fused = HybridFusion.ranked(id: { $0.id }, lexical: lexicalList, semantic: semanticList)
        return Array(fused.prefix(topN).map(\.0))
    }
}

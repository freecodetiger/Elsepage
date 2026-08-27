import Foundation
import ReflectionCore

/// Source-specific long-term memory retrieval. Phase 2: lexical-only (the prior
/// ReaderAgent behavior, relocated). Phase 5 adds bounded semantic recall behind
/// the same surface, preserving the memory/reflection semantic boundary.
public struct MemoryRetriever: Sendable {
    public init() {}

    /// Lexically matches the routing text against long-term memory claims using
    /// the same CJK-aware tokenization as `ReflectionLexicalMatcher`. A lighter
    /// relevance bar than the reflection matcher because memory claims are
    /// distilled and short; ranking picks the strongest matches and non-active
    /// memories are ignored. Memories surface as evidence only (no connection).
    public func matchingMemories(
        routingText: String,
        in repository: (any MemoryRepository)?,
        topN: Int
    ) async -> [ReaderMemory] {
        guard let repository, !routingText.isEmpty else { return [] }
        let queryTokens = ReflectionLexicalMatcher.tokens(in: routingText)
        guard queryTokens.count >= 2 else { return [] }
        let all = (try? await repository.memories()) ?? []
        return all
            .filter { $0.status != .superseded }
            .compactMap { memory -> (memory: ReaderMemory, relevance: Double)? in
                let claimTokens = ReflectionLexicalMatcher.tokens(in: memory.claim)
                let overlap = queryTokens.intersection(claimTokens).count
                guard overlap >= 2 else { return nil }
                let relevance = Double(overlap) / Double(max(1, min(queryTokens.count, claimTokens.count)))
                guard relevance >= 0.30 else { return nil }
                return (memory, relevance)
            }
            .sorted { $0.relevance > $1.relevance }
            .prefix(topN)
            .map(\.memory)
    }
}

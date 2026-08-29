import Foundation

/// Per-source character caps for context assembly. Mirrors the intent budgets the
/// Context Plan validates, split by source so no single source can crowd out the
/// others (the total is the final ceiling).
public struct ContextBudgetProfile: Hashable, Sendable {
    public let totalCharacters: Int
    public let perSource: [ContextSource: Int]

    public init(totalCharacters: Int, perSource: [ContextSource: Int]) {
        self.totalCharacters = totalCharacters
        self.perSource = perSource
    }

    public func budget(for source: ContextSource) -> Int { perSource[source] ?? 0 }
}

/// Derived observability for one assembly pass.
public struct ContextAssemblyStats: Hashable, Sendable {
    public let inputCandidateCount: Int
    public let deduplicatedCount: Int
    public let emittedCandidateCount: Int
    public let usedCharacters: Int
}

public struct ContextAssemblyResult: Hashable, Sendable {
    public let bundle: ContextBundle
    public let stats: ContextAssemblyStats
}

/// Deterministic dedup → rank → budget-pack pipeline that turns raw context
/// candidates into a bounded `ContextBundle`. No LLM involvement: source priority,
/// relevance, confidence and token cost decide deterministically.
public struct ContextCandidateRanker: Sendable {
    /// Default source priority (mirrors today's evidence order):
    /// pinnedBrain > nearbyPassage > bookPassage > pastReflection = brain > memory > conversation.
    public static let defaultPriority: [ContextSource: Int] = [
        .nearbyPassage: 5, .bookPassage: 4, .pastReflection: 3, .brain: 3,
        .pinnedBrain: 6, .memory: 2, .conversation: 1,
    ]
    /// Metadata key linking a book candidate to its parent chunk (for merging).
    public static let parentIDKey = "parentID"
    /// Metadata key for the sibling ordinal inside the parent (stable merge order).
    public static let ordinalKey = "ordinal"

    public init() {}

    public func build(
        from candidates: [ContextCandidate],
        budget: ContextBudgetProfile,
        sourcePriority: [ContextSource: Int] = ContextCandidateRanker.defaultPriority
    ) -> ContextAssemblyResult {
        let deduped = deduplicate(candidates)
        let ranked = deduped.sorted { Self.order($0, $1, sourcePriority: sourcePriority) }

        var bundle: [ContextCandidate] = []
        var spentTotal = 0
        var spentBySource: [ContextSource: Int] = [:]
        for candidate in ranked {
            let sourceRemaining = budget.budget(for: candidate.source) - (spentBySource[candidate.source] ?? 0)
            let totalRemaining = budget.totalCharacters - spentTotal
            let take = max(0, min(candidate.content.count, sourceRemaining, totalRemaining))
            guard take > 0 else { continue }
            let kept = take == candidate.content.count
                ? candidate
                : ContextCandidate(
                    id: candidate.id, source: candidate.source,
                    content: String(candidate.content.prefix(take)), relevance: candidate.relevance,
                    confidence: candidate.confidence, tokenCost: take, importance: candidate.importance,
                    metadata: candidate.metadata
                )
            bundle.append(kept)
            spentTotal += take
            spentBySource[candidate.source, default: 0] += take
        }
        return ContextAssemblyResult(
            bundle: ContextBundle(candidates: bundle),
            stats: ContextAssemblyStats(
                inputCandidateCount: candidates.count,
                deduplicatedCount: candidates.count - deduped.count,
                emittedCandidateCount: bundle.count,
                usedCharacters: spentTotal
            )
        )
    }

    /// Same (source, id) collapses to the highest-relevance entry; candidates
    /// sharing a parent chunk merge into one continuous window (ordered by ordinal).
    private func deduplicate(_ candidates: [ContextCandidate]) -> [ContextCandidate] {
        var byKey: [String: ContextCandidate] = [:]
        for candidate in candidates {
            let key = "\(candidate.source.rawValue):\(candidate.id)"
            if let existing = byKey[key] {
                if candidate.relevance > existing.relevance { byKey[key] = candidate }
            } else {
                byKey[key] = candidate
            }
        }
        var groups: [String: [ContextCandidate]] = [:]
        var result: [ContextCandidate] = []
        for candidate in byKey.values.sorted(by: { ($0.source.rawValue, $0.id) < ($1.source.rawValue, $1.id) }) {
            if let parent = candidate.metadata[Self.parentIDKey] {
                groups[parent, default: []].append(candidate)
            } else {
                result.append(candidate)
            }
        }
        for parent in groups.keys.sorted() {
            let group = groups[parent]!.sorted { ordinal($0) < ordinal($1) }
            result.append(group.dropFirst().reduce(group[0]) { merge($0, $1) })
        }
        return result
    }

    private func merge(_ a: ContextCandidate, _ b: ContextCandidate) -> ContextCandidate {
        ContextCandidate(
            id: a.id, source: a.source,
            content: a.content + "\n\n" + b.content,
            relevance: max(a.relevance, b.relevance),
            confidence: max(a.confidence ?? 0, b.confidence ?? 0),
            tokenCost: a.content.count + 2 + b.content.count,
            importance: max(a.importance ?? 0, b.importance ?? 0),
            metadata: a.metadata
        )
    }

    private func ordinal(_ candidate: ContextCandidate) -> Int {
        candidate.metadata[Self.ordinalKey].flatMap(Int.init) ?? 0
    }

    private static func order(_ lhs: ContextCandidate, _ rhs: ContextCandidate, sourcePriority: [ContextSource: Int]) -> Bool {
        let lp = sourcePriority[lhs.source] ?? 0
        let rp = sourcePriority[rhs.source] ?? 0
        if lp != rp { return lp > rp }
        if lhs.relevance != rhs.relevance { return lhs.relevance > rhs.relevance }
        let lc = lhs.confidence ?? 0, rc = rhs.confidence ?? 0
        if lc != rc { return lc > rc }
        return lhs.tokenCost < rhs.tokenCost
    }
}

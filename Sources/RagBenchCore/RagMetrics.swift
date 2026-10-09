import Foundation

/// Retrieval metrics for one arm over one query set.
///
/// Every rate carries its own denominator. The previous round's headline number
/// came from the same recall computed against two different denominators, and
/// the two tables disagreed; slicing by `split` while forgetting to re-filter
/// the denominator is how that happens. So a slice reports `queries`,
/// `goldBearing` and `evaluable` explicitly, and a rate whose denominator is
/// zero is `nil` rather than `0`.
public struct RagSlice: Codable, Sendable {
    public var name: String
    /// Every query in this slice — the denominator for leak and reachability.
    public var queries: Int
    /// Queries with at least one gold chunk — the denominator for recall, MRR
    /// and nDCG. Adversarial queries have none: their correct answer is nothing.
    public var goldBearing: Int

    public var recallAtK: Double?
    public var parentRecallAtK: Double?
    public var mrr: Double?
    public var ndcgAtK: Double?

    public var leakTotal: Int
    public var leakFreeQueries: Double?

    public var meanReturned: Double?
    /// Mean characters of returned evidence. This is the only metric that moves
    /// when small-to-big is toggled: expansion changes what the window *says*,
    /// not which parent it belongs to.
    public var meanEvidenceCharacters: Double?
    /// Denominator: queries that carry an edge verdict (edge-intent only).
    public var edgeCorrect: Double?

    public init(name: String) {
        self.name = name
        self.queries = 0
        self.goldBearing = 0
        self.recallAtK = nil
        self.parentRecallAtK = nil
        self.mrr = nil
        self.ndcgAtK = nil
        self.leakTotal = 0
        self.leakFreeQueries = nil
        self.meanReturned = nil
        self.meanEvidenceCharacters = nil
        self.edgeCorrect = nil
    }
}

/// One query's outcome under one arm.
public struct RagQueryScore: Codable, Sendable {
    public var queryID: String
    public var split: String
    public var intent: String
    public var goldCount: Int
    /// Child-level: the ranking `rankedChildren` produced.
    public var recallAtK: Double?
    public var reciprocalRank: Double?
    public var ndcgAtK: Double?
    /// Parent-level: the evidence `retrieve` produced after small-to-big.
    public var parentRecallAtK: Double?
    /// Chunks the boundary denies that still showed up in a returned excerpt.
    public var leak: Int
    /// Adversarial targets that were returned when they should not be.
    public var forbiddenReturned: Int
    public var returnedChildren: Int
    public var returnedEvidence: Int
    public var evidenceCharacters: Int
    /// Edge queries are correct when the boundary mechanics produced the
    /// expected answer with nothing leaking past the cursor. Nil elsewhere.
    public var edgeCorrect: Bool?
}

public enum RagMetrics {
    /// Fraction of gold chunks present in the top-k ranking.
    public static func recall(gold: Set<String>, ranked: [String], k: Int) -> Double {
        guard !gold.isEmpty else { return 0 }
        return Double(Set(ranked.prefix(k)).intersection(gold).count) / Double(gold.count)
    }

    /// 1/rank of the highest-ranked gold chunk; 0 when none was retrieved.
    public static func reciprocalRank(gold: Set<String>, ranked: [String], k: Int) -> Double {
        for (index, id) in ranked.prefix(k).enumerated() where gold.contains(id) {
            return 1 / Double(index + 1)
        }
        return 0
    }

    /// Graded nDCG. `grades` is chunk id → relevance (2 for the query's own
    /// wording, 1 for the paraphrase twin), so a hit on the wording the query
    /// echoes outranks a hit on the same idea in different words.
    public static func ndcg(grades: [String: Int], ranked: [String], k: Int) -> Double {
        guard !grades.isEmpty else { return 0 }
        func gain(_ grade: Int) -> Double { pow(2, Double(grade)) - 1 }
        func discount(_ rank: Int) -> Double { 1 / log2(Double(rank) + 1) }

        let dcg = ranked.prefix(k).enumerated()
            .reduce(0.0) { $0 + gain(grades[$1.element] ?? 0) * discount($1.offset + 1) }
        let ideal = grades.values.sorted(by: >).prefix(k).enumerated()
            .reduce(0.0) { $0 + gain($1.element) * discount($1.offset + 1) }
        return ideal > 0 ? dcg / ideal : 0
    }

    /// A leak is a returned excerpt that carries the text of a chunk the
    /// boundary denies — the reader seeing text from ahead of the cursor.
    ///
    /// The two predicates the corpus checks are the production policy
    /// (`ResolvedReadingBoundary.contains`, which keys off a chunk's *end*) and
    /// the storage filter (`startProgression <= cursor`). They are computed by
    /// the same function here and differ only in which chunks they hand in, so
    /// a disagreement between them shows up as a leak instead of hiding.
    public static func leaks(excerpts: [String], deniedTexts: [String]) -> Int {
        guard !deniedTexts.isEmpty else { return 0 }
        var count = 0
        for excerpt in excerpts where deniedTexts.contains(where: { excerpt.contains($0) }) {
            count += 1
        }
        return count
    }
}

public enum RagAggregate {
    public static func slice(
        name: String,
        scores: [RagQueryScore],
        k: Int
    ) -> RagSlice {
        var slice = RagSlice(name: name)
        slice.queries = scores.count
        guard !scores.isEmpty else { return slice }

        let goldBearing = scores.filter { $0.goldCount > 0 }
        slice.goldBearing = goldBearing.count

        if !goldBearing.isEmpty {
            slice.recallAtK = goldBearing.compactMap(\.recallAtK).mean
            slice.parentRecallAtK = goldBearing.compactMap(\.parentRecallAtK).mean
            slice.mrr = goldBearing.compactMap(\.reciprocalRank).mean
            slice.ndcgAtK = goldBearing.compactMap(\.ndcgAtK).mean
        }
        slice.leakTotal = scores.map(\.leak).reduce(0, +)
        slice.leakFreeQueries = Double(scores.filter { $0.leak == 0 }.count) / Double(scores.count)
        slice.meanReturned = Double(scores.map(\.returnedEvidence).reduce(0, +)) / Double(scores.count)
        slice.meanEvidenceCharacters = Double(scores.map(\.evidenceCharacters).reduce(0, +)) / Double(scores.count)
        let edgeVerdicts = scores.compactMap(\.edgeCorrect)
        if !edgeVerdicts.isEmpty {
            slice.edgeCorrect = Double(edgeVerdicts.filter { $0 }.count) / Double(edgeVerdicts.count)
        }
        return slice
    }

    /// Slice a score set by one field, one slice per distinct value.
    public static func by(
        _ label: String,
        _ field: KeyPath<RagQueryScore, String>,
        _ scores: [RagQueryScore],
        k: Int
    ) -> [RagSlice] {
        Dictionary(grouping: scores, by: { $0[keyPath: field] })
            .sorted { $0.key < $1.key }
            .map { slice(name: "\(label)_\($0.key)", scores: $0.value, k: k) }
    }
}

extension Array where Element == Double {
    var mean: Double? { isEmpty ? nil : reduce(0, +) / Double(count) }
}

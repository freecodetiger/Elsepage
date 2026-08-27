/// Reciprocal-rank fusion over two independently scored lanes (lexical + semantic).
/// Independent recall lanes each produce a ranked list; RRF merges them without
/// comparing raw score scales, and an item hit by both lanes is boosted, not
/// duplicated.
public enum HybridFusion {
    public static func ranked<T, ID: Hashable>(
        id: (T) -> ID,
        lexical: [(item: T, score: Double)],
        semantic: [(item: T, score: Double)],
        k: Double = 60
    ) -> [(item: T, score: Double)] {
        var scores: [ID: (T, Double)] = [:]
        for (rank, entry) in lexical.enumerated() {
            let key = id(entry.item)
            scores[key] = (entry.item, (scores[key]?.1 ?? 0) + 1 / (k + Double(rank + 1)))
        }
        for (rank, entry) in semantic.enumerated() {
            let key = id(entry.item)
            scores[key] = (entry.item, (scores[key]?.1 ?? 0) + 1 / (k + Double(rank + 1)))
        }
        return scores.values.sorted { $0.1 > $1.1 }
    }
}

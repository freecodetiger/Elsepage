import Foundation
import RetrievalCore

/// Query-time semantic ranking: embeds the query plus the bounded eligible item
/// set in one provider batch, scores with cosine, and caches item vectors in a
/// process-local `SemanticVectorCache`. Provider absence or embed failure yields
/// nil so callers degrade to lexical-only — never a crash, never a partial result.
///
/// This is the only `SemanticRanking` today; a future persistent vector index can
/// conform without touching upper retrieval semantics.
public struct QueryTimeSemanticRanking: SemanticRanking {
    private let embeddingFactory: @Sendable () async -> (any EmbeddingProvider)?
    private let cache: SemanticVectorCache

    public init(
        embeddingFactory: @escaping @Sendable () async -> (any EmbeddingProvider)?,
        cache: SemanticVectorCache = SemanticVectorCache()
    ) {
        self.embeddingFactory = embeddingFactory
        self.cache = cache
    }

    public func scores(query: String, items: [(id: String, text: String)], source: ContextSource) async -> SemanticScores? {
        guard let provider = await embeddingFactory() else { return nil }
        let start = ContinuousClock.now
        let keys = items.map {
            SemanticVectorCache.Key(source: source, itemID: $0.id, contentHash: Self.contentHash($0.text), model: provider.modelIdentifier)
        }
        var vectors: [String: [Float]] = [:]
        var missing: [(index: Int, id: String, text: String)] = []
        for (index, item) in items.enumerated() {
            if let vector = cache.vector(for: keys[index]) {
                vectors[item.id] = vector
            } else {
                missing.append((index, item.id, item.text))
            }
        }
        // The query is always embedded (never cached); missing eligible items are
        // embedded in the SAME batch — the eligible set is not the lexical top-N,
        // so this is true semantic recall, not a rerank.
        let inputs = [query] + missing.map(\.text)
        do {
            let embedded = try await provider.embed(inputs)
            let queryVector = embedded[0]
            for (offset, item) in missing.enumerated() {
                vectors[item.id] = embedded[offset + 1]
                cache.store(embedded[offset + 1], for: keys[item.index])
            }
            let scores = items.compactMap { item -> (String, Double)? in
                guard let vector = vectors[item.id] else { return nil }
                return (item.id, VectorMath.cosine(queryVector, vector))
            }
            let counts = cache.hitMissCounts
            let elapsed = start.duration(to: .now).seconds
            return SemanticScores(
                scores: Dictionary(uniqueKeysWithValues: scores),
                stats: SemanticVectorStats(eligibleCount: items.count, embeddedCount: inputs.count, cacheHits: counts.hits, cacheMisses: counts.misses, durationSeconds: elapsed)
            )
        } catch {
            return nil
        }
    }

    /// Stable FNV-1a 64-bit content hash so the cache key never collides across
    /// edited claim text within a session.
    static func contentHash(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

private extension Duration {
    var seconds: Double {
        let components = self.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

import BrainCore
import CryptoKit
import Foundation
import RetrievalCore

/// One retrieval hit: the brain item plus each lane's score (nil when that
/// lane didn't fire). Scores are lane-internal relevance values; ordering is
/// decided by RRF, not by raw score comparison.
public struct BrainCandidate: Hashable, Sendable {
    public let item: BrainItem
    public let lexicalScore: Double?
    public let semanticScore: Double?

    public init(item: BrainItem, lexicalScore: Double?, semanticScore: Double?) {
        self.item = item
        self.lexicalScore = lexicalScore
        self.semanticScore = semanticScore
    }
}

/// Brain 检索 primitive(docs/brain.md §12):lexical + persistent embedding +
/// RRF over one eligible set, filterable by kind. Mirrors the MemoryRetriever
/// lane pattern; the semantic lane reads PERSISTED item vectors
/// (`BrainEmbeddingStore`) instead of re-embedding items every query —
/// contentHash guards make "create once, retrieve many" real, and a bounded
/// refresh batch keeps worst-case query latency finite. Missing provider or
/// store degrade to lexical-only, like every retrieval lane in this app.
public struct BrainRetriever: Sendable {
    private let items: any BrainRepository
    private let store: (any BrainEmbeddingStore)?
    /// Resolved at query time so a Settings model switch takes effect without
    /// rebuilding the graph (same pattern as LocalBookRetriever).
    private let embeddingProvider: (@Sendable () async -> (any EmbeddingProvider)?)?
    private let semanticThreshold: Double
    private let lexicalThreshold: Double
    private let maxEligibleCandidates: Int
    /// Upper bound on item embeddings performed per query — the lazy refresh
    /// budget. Items beyond it stay un-vectorized until a later query.
    private let maxRefreshPerQuery: Int

    public init(
        items: any BrainRepository,
        store: (any BrainEmbeddingStore)? = nil,
        embeddingProvider: (@Sendable () async -> (any EmbeddingProvider)?)? = nil,
        semanticThreshold: Double = 0.2,
        lexicalThreshold: Double = 0.3,
        maxEligibleCandidates: Int = 30,
        maxRefreshPerQuery: Int = 16
    ) {
        self.items = items
        self.store = store
        self.embeddingProvider = embeddingProvider
        self.semanticThreshold = semanticThreshold
        self.lexicalThreshold = lexicalThreshold
        self.maxEligibleCandidates = max(1, maxEligibleCandidates)
        self.maxRefreshPerQuery = max(1, maxRefreshPerQuery)
    }

    public func retrieve(
        query: String,
        kinds: Set<BrainItemKind> = [.thought, .question, .memory],
        limit: Int = 5
    ) async -> [BrainCandidate] {
        let all = (try? await items.items()) ?? []
        let eligible = all
            .filter { kinds.contains($0.kind) && isEligible($0) }
            .sorted { lhs, rhs in
                let lhsDate = Self.updatedAt(of: lhs), rhsDate = Self.updatedAt(of: rhs)
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return lhs.id.rawValue < rhs.id.rawValue
            }
            .prefix(maxEligibleCandidates)

        let lexicalLane = lexicalScores(for: eligible, query: query)
        let semanticLane = await semanticScores(for: Array(eligible), query: query)

        let fused = HybridFusion.ranked(
            id: { $0.id.rawValue },
            lexical: lexicalLane.map { (item: $0.0, score: $0.1) },
            semantic: semanticLane.map { (item: $0.0, score: $0.1) }
        )
        let lexicalByItem = Dictionary(lexicalLane.map { ($0.0.id.rawValue, $0.1) }, uniquingKeysWith: { a, _ in a })
        let semanticByItem = Dictionary(semanticLane.map { ($0.0.id.rawValue, $0.1) }, uniquingKeysWith: { a, _ in a })
        return fused.prefix(max(1, limit)).map { entry in
            BrainCandidate(
                item: entry.item,
                lexicalScore: lexicalByItem[entry.item.id.rawValue],
                semanticScore: semanticByItem[entry.item.id.rawValue]
            )
        }
    }

    // MARK: - Lexical lane (same contract as MemoryRetriever)

    private func lexicalScores(for candidates: some Collection<BrainItem>, query: String) -> [(BrainItem, Double)] {
        let queryTokens = ReflectionLexicalMatcher.tokens(in: query)
        guard queryTokens.count >= 2 else { return [] }
        return candidates.compactMap { item -> (BrainItem, Double)? in
            let itemTokens = ReflectionLexicalMatcher.tokens(in: Self.contentText(of: item))
            let overlap = queryTokens.intersection(itemTokens).count
            guard overlap >= 2 else { return nil }
            let relevance = Double(overlap) / Double(max(1, min(queryTokens.count, itemTokens.count)))
            guard relevance >= lexicalThreshold else { return nil }
            return (item, relevance)
        }
        .sorted { $0.1 > $1.1 }
    }

    // MARK: - Semantic lane over persisted vectors

    private func semanticScores(for candidates: [BrainItem], query: String) async -> [(BrainItem, Double)] {
        guard let store, let embeddingProvider,
              let provider = await embeddingProvider() else { return [] }
        let queryVector: [Float]
        do { queryVector = try await provider.embed([query]).first ?? [] } catch { return [] }
        guard queryVector.count == provider.dimensions else { return [] }

        var stored: [String: BrainItemVector] = [:]
        if let records = try? await store.vectors(model: provider.modelIdentifier) {
            stored = Dictionary(records.map { ($0.itemID.rawValue, $0) }, uniquingKeysWith: { a, _ in a })
        }

        // Lazy refresh: only missing/stale items, bounded per query.
        let stale = candidates.filter { candidate in
            guard let vector = stored[candidate.id.rawValue] else { return true }
            return vector.contentHash != Self.contentHash(Self.contentText(of: candidate))
                || vector.vector.count != provider.dimensions
        }
        if !stale.isEmpty {
            let refresh = stale.prefix(maxRefreshPerQuery)
            let texts = refresh.map { Self.contentText(of: $0) }
            if let vectors = try? await provider.embed(texts), vectors.count == texts.count {
                let rows = zip(refresh, vectors).map { item, vector in
                    BrainItemVector(
                        itemID: item.id, model: provider.modelIdentifier,
                        dimensions: provider.dimensions,
                        contentHash: Self.contentHash(Self.contentText(of: item)),
                        vector: vector, updatedAt: Date()
                    )
                }
                try? await store.save(rows)
                for row in rows { stored[row.itemID.rawValue] = row }
            }
        }

        return candidates.compactMap { item -> (BrainItem, Double)? in
            guard let vector = stored[item.id.rawValue],
                  vector.vector.count == provider.dimensions,
                  vector.contentHash == Self.contentHash(Self.contentText(of: item)) else { return nil }
            let score = VectorMath.cosine(queryVector, vector.vector)
            guard score > semanticThreshold else { return nil }
            return (item, score)
        }
        .sorted { $0.1 > $1.1 }
    }

    // MARK: - Eligibility & content

    private func isEligible(_ item: BrainItem) -> Bool {
        switch item {
        case .thought(let thought):
            thought.stage != .archived
        case .question:
            true
        case .memory(let memory):
            memory.state != .superseded && memory.state != .forgotten
        }
    }

    private static func contentText(of item: BrainItem) -> String {
        switch item {
        case .thought(let item): item.statement
        case .question(let item): item.question
        case .memory(let item): item.content
        }
    }

    private static func updatedAt(of item: BrainItem) -> Date {
        switch item {
        case .thought(let item): item.updatedAt
        case .question(let item): item.updatedAt
        case .memory(let item): item.updatedAt
        }
    }

    /// SHA-256 of the retrieval text — the same hash the store's `contentHash`
    /// guards compare against. Public because the projection service (phase 17)
    /// must compute identical hashes when it refreshes embeddings.
    public static func contentHash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

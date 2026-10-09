import Foundation
import LibraryCore
import Persistence
import ReaderCore
import RetrievalCore

/// One arm: a configuration of the production retriever, nothing more.
///
/// The arms are stages of `LocalBookRetriever`, so a change to one stage cannot
/// touch another. That is what makes the baseline a usable in-corpus control
/// rather than a number to compare against a remembered one.
public struct RagArm: Codable, Hashable, Sendable {
    public var name: String
    /// Fuse the embedding lane into the ranking.
    public var semantic: Bool
    /// Re-score and gate the fused candidates with the cross-encoder.
    public var rerank: Bool
    /// Small-to-big expansion. Off uses the expander's own public budget knob
    /// (a budget of one character admits no sibling), so both settings run
    /// production code rather than a bypass.
    public var expand: Bool

    public init(name: String, semantic: Bool, rerank: Bool, expand: Bool) {
        self.name = name; self.semantic = semantic; self.rerank = rerank; self.expand = expand
    }

    /// The standard ladder. `lexical` is the control: refusion, rerank and
    /// expansion are downstream of it, so it must not move when they change.
    public static let ladder: [RagArm] = [
        RagArm(name: "lexical", semantic: false, rerank: false, expand: false),
        RagArm(name: "lexical+smallToBig", semantic: false, rerank: false, expand: true),
        RagArm(name: "hybrid", semantic: true, rerank: false, expand: true),
        RagArm(name: "hybrid+rerank", semantic: true, rerank: true, expand: true),
    ]
}

public struct RagArmReport: Codable, Sendable {
    public var arm: RagArm
    /// Set when the arm could not run (e.g. no API key). Reported, never
    /// silently dropped — an arm that did not run is a result.
    public var skipped: String?
    public var k: Int
    public var overall: RagSlice
    public var bySplit: [RagSlice]
    public var byIntent: [RagSlice]
    /// Adversarial targets that came back anyway, summed over the arm.
    public var forbiddenReturned: Int
    /// Every query's raw score, so any number in the summary above can be
    /// checked against the queries it came from rather than taken on trust.
    public var perQuery: [RagQueryScore]
}

/// Provenance for one ablation run.
///
/// The lexical arms are reproducible from the repository alone. The semantic
/// and rerank arms are not: they call a remote model, and the same bytes do not
/// embed to the same vector twice. Recording the corpus and query hashes makes
/// a stale report detectable and keeps that distinction explicit instead of
/// implied.
public struct RagAblationReport: Codable, Sendable {
    public var runAt: String
    public var corpusSHA256: String
    public var queriesSHA256: String
    public var k: Int
    public var embeddingModel: String?
    public var rerankModel: String?
    public var arms: [RagArmReport]

    public init(
        runAt: String, corpusSHA256: String, queriesSHA256: String, k: Int,
        embeddingModel: String?, rerankModel: String?, arms: [RagArmReport]
    ) {
        self.runAt = runAt; self.corpusSHA256 = corpusSHA256; self.queriesSHA256 = queriesSHA256
        self.k = k; self.embeddingModel = embeddingModel; self.rerankModel = rerankModel
        self.arms = arms
    }
}

public struct RagProviders: Sendable {
    public var embedding: (@Sendable () async -> (any EmbeddingProvider)?)?
    public var reranker: (@Sendable () async -> (any Reranker)?)?
    public init(
        embedding: (@Sendable () async -> (any EmbeddingProvider)?)? = nil,
        reranker: (@Sendable () async -> (any Reranker)?)? = nil
    ) {
        self.embedding = embedding; self.reranker = reranker
    }
}

public struct RagAblation {
    public let corpus: RagCorpus
    public let database: AppDatabase
    public let k: Int

    public init(corpus: RagCorpus, database: AppDatabase, k: Int = 5) {
        self.corpus = corpus; self.database = database; self.k = k
    }

    /// Embeds every corpus book so the semantic lane has vectors to read.
    ///
    /// Without this the hybrid arm finds no stored embeddings, falls back to
    /// the lexical ranking, and reports a number identical to the control —
    /// a silent no-op that looks like a finding.
    public func embedCorpus(providers: RagProviders) async throws {
        guard let factory = providers.embedding, let provider = await factory() else { return }
        let repository = GRDBBookIndexRepository(database: database)
        for bookKey in corpus.bookKeys {
            guard let bookID = corpus.bookID(forBook: bookKey) else { continue }
            try await BookIndexPipeline(
                repository: repository,
                embeddings: { provider }
            ).embed(bookID: bookID, force: true)
            // A semantic arm that quietly has no vectors reports the lexical
            // numbers under a different name. Refuse to run rather than publish
            // that as a result.
            let stored = try await repository.embeddings(bookID: bookID, model: provider.modelIdentifier)
            guard stored.count >= corpus.chunks(forBook: bookKey).filter({ $0.role == .child }).count else {
                throw RagCorpusError.embeddingEmpty(bookKey, stored: stored.count)
            }
        }
    }

    public func run(
        queries: [RagQueryRecord],
        arms: [RagArm] = RagArm.ladder,
        providers: RagProviders = RagProviders()
    ) async throws -> [RagArmReport] {
        var repositories: [String: GRDBBookIndexRepository] = [:]
        for bookKey in corpus.bookKeys {
            repositories[bookKey] = try await corpus.seed(bookKey: bookKey, database: database)
        }

        var reports: [RagArmReport] = []
        for arm in arms {
            // Until an embedding is actually required, an arm that needs one but
            // has none is reported as skipped rather than scored as zero.
            if arm.semantic, providers.embedding == nil {
                reports.append(skippedReport(arm: arm, reason: "no embedding provider configured"))
                continue
            }
            if arm.rerank, providers.reranker == nil {
                reports.append(skippedReport(arm: arm, reason: "no reranker configured"))
                continue
            }

            // One repository instance is enough: they all wrap the same database,
            // and every call is scoped by the query's own bookID.
            let retriever = LocalBookRetriever(
                repository: GRDBBookIndexRepository(database: database),
                embeddingProvider: arm.semantic ? providers.embedding : nil,
                reranker: arm.rerank ? providers.reranker : nil,
                rerankCandidateCount: max(10, k),
                expander: arm.expand
                    ? SmallToBigExpander()
                    : SmallToBigExpander(windowCharacterBudget: 1, maxSiblingsPerSide: 1)
            )

            var scores: [RagQueryScore] = []
            for query in queries {
                scores.append(try await score(
                    query: query, arm: arm, retriever: retriever, repositories: repositories
                ))
            }

            reports.append(RagArmReport(
                arm: arm,
                skipped: nil,
                k: k,
                overall: RagAggregate.slice(name: "all", scores: scores, k: k),
                bySplit: RagAggregate.by("split", \.split, scores, k: k),
                byIntent: RagAggregate.by("intent", \.intent, scores, k: k),
                forbiddenReturned: scores.map(\.forbiddenReturned).reduce(0, +),
                perQuery: scores
            ))
        }
        return reports
    }

    private func skippedReport(arm: RagArm, reason: String) -> RagArmReport {
        RagArmReport(
            arm: arm, skipped: reason, k: k,
            overall: RagSlice(name: "all"), bySplit: [], byIntent: [],
            forbiddenReturned: 0, perQuery: []
        )
    }

    private func score(
        query: RagQueryRecord,
        arm: RagArm,
        retriever: LocalBookRetriever,
        repositories: [String: GRDBBookIndexRepository]
    ) async throws -> RagQueryScore {
        guard let repository = repositories[query.bookKey],
              let bookID = corpus.bookID(forBook: query.bookKey) else {
            throw RagCorpusError.unknownBook(query.bookKey)
        }
        let children = corpus.chunks(forBook: query.bookKey).filter { $0.role == .child }
        let byID = Dictionary(uniqueKeysWithValues: children.map { ($0.id.rawValue, $0) })

        // Re-resolve the boundary at run time. The query file stores the cursor,
        // not the policy, so a stored boundary cannot go stale against it.
        let boundary = try await repository.readingBoundary(
            bookID: bookID,
            locator: try BookLocator(
                json: try JSONSerialization.data(withJSONObject: ["href": query.cursorHref]),
                href: query.cursorHref,
                progression: query.cursorProgression
            )
        )
        let request = RetrievalQuery(
            bookID: bookID, text: query.text, boundary: boundary, limit: k, scope: .readSoFar
        )

        let ranked = try await retriever.rankedChildren(request)
        let evidence = try await retriever.retrieve(request)

        let goldIDs = Set(query.gold.map(\.chunkID))
        let grades = Dictionary(uniqueKeysWithValues: query.gold.map { ($0.chunkID, $0.grade) })
        let goldParents = Set(query.gold.compactMap { byID[$0.chunkID]?.parentID?.rawValue })
        let returnedParents = evidence.map(\.id.rawValue)

        // Leak under both predicates. `deniedByPolicy` is the production
        // `contains`. `deniedByStorage` is the negation of the WHERE clause
        // `lexicalSearch` applies — note that it compares progressions only
        // *within* one resource, because a progression is a fraction of its own
        // resource and means nothing across resources. Getting that wrong is
        // how a first version of this check reported 43 leaks that did not
        // exist.
        let deniedByPolicy = children.filter { !(boundary?.contains($0) ?? true) }
        let deniedByStorage = children.filter { chunk in
            guard let boundary else { return false }
            if chunk.resourceOrdinal < boundary.resourceOrdinal { return false }
            if chunk.resourceOrdinal > boundary.resourceOrdinal { return true }
            guard let progression = boundary.progression else { return false }
            return (chunk.startLocator.progression ?? 0) > progression
        }
        let excerpts = evidence.map(\.excerpt)
        let leak = RagMetrics.leaks(excerpts: excerpts, deniedTexts: deniedByPolicy.map(\.text))
            + RagMetrics.leaks(excerpts: excerpts, deniedTexts: deniedByStorage.map(\.text))

        let forbiddenTexts = query.mustStayUnreachable.compactMap { byID[$0]?.text }
        let forbiddenReturned = excerpts.filter { excerpt in
            forbiddenTexts.contains { excerpt.contains($0) }
        }.count

        return RagQueryScore(
            queryID: query.id,
            split: query.split,
            intent: query.intent,
            goldCount: query.gold.count,
            recallAtK: query.gold.isEmpty ? nil
                : RagMetrics.recall(gold: goldIDs, ranked: ranked.map(\.0.id.rawValue), k: k),
            reciprocalRank: query.gold.isEmpty ? nil
                : RagMetrics.reciprocalRank(gold: goldIDs, ranked: ranked.map(\.0.id.rawValue), k: k),
            ndcgAtK: query.gold.isEmpty ? nil
                : RagMetrics.ndcg(grades: grades, ranked: ranked.map(\.0.id.rawValue), k: k),
            parentRecallAtK: goldParents.isEmpty ? nil
                : Double(Set(returnedParents).intersection(goldParents).count) / Double(goldParents.count),
            leak: leak,
            forbiddenReturned: forbiddenReturned,
            returnedChildren: ranked.count,
            returnedEvidence: evidence.count,
            evidenceCharacters: evidence.map(\.excerpt.count).reduce(0, +),
            edgeCorrect: query.intent == "edge"
                ? (leak == 0 && !query.gold.isEmpty
                    && RagMetrics.recall(gold: goldIDs, ranked: ranked.map(\.0.id.rawValue), k: k) == 1)
                : nil
        )
    }
}

import ContextEngineering
import Foundation
import LibraryCore
import ReflectionCore
import RetrievalCore
import Testing

// MARK: - Reflection hybrid retrieval

@Test func reflectionRetrieverRecallsLexicallyMissedButSemanticallyRelated() async {
    // The query shares ZERO lexical tokens with the target — the pure lexical
    // matcher cannot recall it. The independent semantic lane must.
    let query = "春夜的寒意让人想起失去"
    let target = Reflection(bookID: BookID(), originalText: "读完书第三章,我对主角的决断印象深刻", inputKind: .text)
    let unrelated = Reflection(bookID: BookID(), originalText: "和朋友讨论了很多与书无关的话题", inputKind: .text)
    let semantic = TextDrivenSemanticRanking(scores: [target.originalText: 0.85, unrelated.originalText: 0.05])

    let match = await ReflectionRetriever(semantic: semantic, semanticThreshold: 0.2).strongestMatch(for: query, among: [unrelated, target])
    #expect(match?.reflection.id == target.id)
}

@Test func reflectionRetrieverFusesBothHitCandidatesWithoutDuplication() async {
    let query = "制度结构影响个人选择"
    let both = Reflection(bookID: BookID(), originalText: "个人选择往往受到制度结构的影响", inputKind: .text)
    let other = Reflection(bookID: BookID(), originalText: "今天天气很好适合散步", inputKind: .text)
    let semantic = TextDrivenSemanticRanking(scores: [both.originalText: 0.9, other.originalText: 0.1])

    let match = await ReflectionRetriever(semantic: semantic).strongestMatch(for: query, among: [other, both])
    #expect(match?.reflection.id == both.id)
    // One entry per item across both lanes: RRF score 1/61 + 1/61 (rank 1 in each).
    let expected = 2.0 / 61.0
    #expect(abs((match?.relevance ?? 0) - expected) < 0.0001)
}

@Test func reflectionRetrieverFallsBackToLexicalWhenSemanticUnavailable() async {
    let query = "制度结构影响个人选择"
    let lexicalHit = Reflection(bookID: BookID(), originalText: "个人选择往往受到制度结构的影响", inputKind: .text)
    let other = Reflection(bookID: BookID(), originalText: "春夜的寒意", inputKind: .text)

    // Semantic provider absent → identical to the pure lexical matcher.
    let without = await ReflectionRetriever().strongestMatch(for: query, among: [lexicalHit, other])
    let withNilProvider = await ReflectionRetriever(semantic: NilSemanticRanking()).strongestMatch(for: query, among: [lexicalHit, other])
    #expect(without?.reflection.id == lexicalHit.id)
    #expect(withNilProvider?.reflection.id == lexicalHit.id)
}

// MARK: - Memory hybrid retrieval

@Test func memoryRetrieverSemanticRecallPreservesSourcePolicyAndTopN() async {
    let repository = MemoryRepositoryFake(memories: [
        ReaderMemory(kind: .semantic, claim: "用户偏好简洁直接的回答风格", confidence: 0.9, status: .active),
        ReaderMemory(kind: .episodic, claim: "上周去看了海边的日落", confidence: 0.8, status: .active),
        ReaderMemory(kind: .preference, claim: "已经过时的旧记忆", confidence: 0.7, status: .superseded),
    ])
    // Semantic lane rescues the style memory even if lexical overlap were weak;
    // the superseded memory never enters the eligible set (source policy intact).
    let semantic = TextDrivenSemanticRanking(scores: ["用户偏好简洁直接的回答风格": 0.8, "上周去看了海边的日落": 0.05])
    let retriever = MemoryRetriever(semantic: semantic)

    let results = await retriever.matchingMemories(routingText: "回答风格简洁直接", in: repository, topN: 2)
    #expect(results.count == 1)
    #expect(results[0].claim == "用户偏好简洁直接的回答风格")
    // Evidence-only: the result is plain memories — no connection concept.
    #expect(results.map(\.id).filter { $0 == results[0].id }.count == 1)
}

@Test func memoryRetrieverWithoutSemanticKeepsLexicalBehavior() async {
    let repository = MemoryRepositoryFake(memories: [
        ReaderMemory(kind: .semantic, claim: "用户偏好简洁直接的回答风格", confidence: 0.9, status: .active),
        ReaderMemory(kind: .episodic, claim: "上周去看了海边的日落", confidence: 0.8, status: .active),
    ])
    let results = await MemoryRetriever().matchingMemories(routingText: "回答风格简洁直接", in: repository, topN: 2)
    #expect(results.map(\.claim) == ["用户偏好简洁直接的回答风格"])
}

// MARK: - Fusion unit

@Test func hybridFusionMergesBothLanesWithoutDuplicatingSharedItems() {
    let a = "A", b = "B"
    let fused = HybridFusion.ranked(id: { $0 }, lexical: [(a, 0.9), (b, 0.7)], semantic: [(a, 0.8), (b, 0.6)])
    #expect(fused.map(\.item) == [a, b]) // each item appears exactly once
    #expect(abs((fused[0].score) - (2.0 / 61.0)) < 0.0001) // rank 0 in both lanes → 1/61 + 1/61
}

// MARK: - Query-time semantic ranking

@Test func queryTimeSemanticRankingEmbedsEligibleSetOnceAndCaches() async throws {
    let recorder = EmbeddingRecorder()
    let provider = SeededEmbeddingProvider(recorder: recorder) { text in
        // Deterministic seeded vector per text; cosine ordering is irrelevant here.
        let seed = text.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) }
        return [Float(seed % 7), 1, 0, 0]
    }
    let cache = SemanticVectorCache()
    let ranking = QueryTimeSemanticRanking(embeddingFactory: { provider }, cache: cache)
    let items = [(id: "r1", text: "第一段反思"), (id: "r2", text: "第二段反思"), (id: "r3", text: "第三段反思")]

    let first = try #require(await ranking.scores(query: "当前反思", items: items, source: .pastReflection))
    // Query + the FULL eligible set embedded in one call (true recall, not top-N).
    let calls = await recorder.calls
    #expect(calls.count == 1)
    #expect(Set(calls[0]) == Set(["当前反思", "第一段反思", "第二段反思", "第三段反思"]))
    #expect(first.stats.eligibleCount == 3)
    #expect(first.stats.embeddedCount == 4)

    // Second pass hits the cache: only the query is embedded again.
    let second = try #require(await ranking.scores(query: "当前反思", items: items, source: .pastReflection))
    let callsAfter = await recorder.calls
    #expect(callsAfter.count == 2)
    #expect(callsAfter[1] == ["当前反思"])
    let counts = cache.hitMissCounts
    #expect(counts.hits == 3)
    #expect(counts.misses == 3)
}

@Test func queryTimeSemanticRankingReturnsNilWhenProviderUnavailable() async {
    let ranking = QueryTimeSemanticRanking(embeddingFactory: { nil })
    let result = await ranking.scores(query: "q", items: [(id: "a", text: "x")], source: .memory)
    #expect(result == nil) // caller degrades to lexical
}

// MARK: - Fakes

private struct TextDrivenSemanticRanking: SemanticRanking {
    let scores: [String: Double]
    var cacheHitMiss: (hits: Int, misses: Int) { (0, 0) }
    func scores(query: String, items: [(id: String, text: String)], source: ContextSource) async -> SemanticScores? {
        SemanticScores(
            scores: Dictionary(uniqueKeysWithValues: items.map { ($0.id, scores[$0.text] ?? 0) }),
            stats: .zero
        )
    }
}

private struct NilSemanticRanking: SemanticRanking {
    var cacheHitMiss: (hits: Int, misses: Int) { (0, 0) }
    func scores(query: String, items: [(id: String, text: String)], source: ContextSource) async -> SemanticScores? { nil }
}

private actor EmbeddingRecorder {
    private(set) var calls: [[String]] = []
    func record(_ batch: [String]) { calls.append(batch) }
}

private struct SeededEmbeddingProvider: EmbeddingProvider {
    let modelIdentifier = "seed-model"
    let dimensions = 4
    let recorder: EmbeddingRecorder
    let vectorFor: @Sendable (String) -> [Float]
    func embed(_ texts: [String]) async throws -> [[Float]] {
        await recorder.record(texts)
        return texts.map(vectorFor)
    }
}

private actor MemoryRepositoryFake: MemoryRepository {
    let stored: [ReaderMemory]
    init(memories: [ReaderMemory]) { stored = memories }
    func memories() async throws -> [ReaderMemory] { stored }
    func memories(kind: MemoryKind) async throws -> [ReaderMemory] { stored.filter { $0.kind == kind } }
    func save(_ memory: ReaderMemory) async throws {}
    func delete(id: UUID) async throws {}
    func deleteAll() async throws {}
    func markInaccurate(id: UUID) async throws {}
}

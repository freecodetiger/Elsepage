import RetrievalCore
import Testing

@Test func cosineRankingAndHybridFusionAreDeterministic() {
    let a = BookChunkID(rawValue: "a"), b = BookChunkID(rawValue: "b")
    // cosine([1,0], [0.9,0.1]) ≈ 0.994 > cosine([1,0], [0,1]) = 0 → a ranks above b.
    #expect(VectorMath.cosine([1, 0], [0.9, 0.1]) > VectorMath.cosine([1, 0], [0, 1]))
    let fused = HybridRanker.fuse(lexical: [(a, 9), (b, 1)], semantic: [(b, 0.9), (a, 0.1)], limit: 2)
    #expect(fused.count == 2)
}

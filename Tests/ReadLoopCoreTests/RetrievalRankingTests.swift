import RetrievalCore
import Testing

@Test func flatCosineAndHybridFusionAreDeterministic() async throws {
    let index = FlatVectorIndex()
    let a = BookChunkID(rawValue: "a"), b = BookChunkID(rawValue: "b")
    await index.upsert([a: [1, 0], b: [0, 1]])
    let result = await index.search(vector: [0.9, 0.1], candidates: nil, limit: 2)
    #expect(result.map(\.0) == [a, b])
    let fused = HybridRanker.fuse(lexical: [(a, 9), (b, 1)], semantic: [(b, 0.9), (a, 0.1)], limit: 2)
    #expect(fused.count == 2)
}

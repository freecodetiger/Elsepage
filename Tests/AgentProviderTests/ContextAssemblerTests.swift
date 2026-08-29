import ContextEngineering
import ContextRouting
import Foundation
import LibraryCore
import ReaderCore
import ReflectionCore
import RetrievalCore
import Testing

@Test func assemblerPrioritizesSourcesAndDerivesMemoryBudget() throws {
    let reflection = Reflection(bookID: BookID(), originalText: "过去的想法正文", inputKind: .text)
    let memory = ReaderMemory(kind: .semantic, claim: "用户长期思考自由与责任", confidence: 0.8, status: .active)
    let locator = try locator(0.5)
    let book = BookEvidence(id: .init(rawValue: "parent-1"), bookID: reflection.bookID, chapterTitle: "第三章", sectionTitle: "自由",
        excerpt: "书的段落内容", locator: locator, score: 0.9)
    let nearby = NearbyPassageCandidate(text: "当前读到的原文片段", sourceID: "nearby-source", locator: locator)

    let budget = ContextBudget(totalCharacters: 6_000, nearbyCharacters: 1_400, bookEvidenceCharacters: 2_800, pastThoughtCharacters: 600, conversationCharacters: 1_200)
    let result = ContextAssembler().assemble(
        nearby: nearby, bookEvidence: [book], previousReflection: reflection, memories: [memory],
        reflectionBookID: reflection.bookID, budget: budget
    )
    // Source priority: nearby > bookPassage > pastReflection > memory.
    #expect(result.evidence.map(\.kind) == [.nearbyPassage, .bookPassage, .pastReflection, .pastReflection])
    #expect(result.evidence.map(\.title) == ["当前阅读位置", "第三章 / 自由", "过去的想法", "长期记忆"])
    // Memory budget derived as pastThought/2 = 300; claim (short) survives intact.
    #expect(result.evidence.last?.excerpt == memory.claim)
}

@Test func assemblerDropsSourcesWithZeroBudget() throws {
    let reflection = Reflection(bookID: BookID(), originalText: "过去的想法", inputKind: .text)
    let memory = ReaderMemory(kind: .semantic, claim: "长期记忆", confidence: 0.8, status: .active)
    // emotionalRecord: pastThought budget 0 → reflection + memory candidates are skipped.
    let budget = ContextBudget(totalCharacters: 6_000, nearbyCharacters: 600, bookEvidenceCharacters: 0, pastThoughtCharacters: 0, conversationCharacters: 1_800)
    let result = ContextAssembler().assemble(
        nearby: nil, bookEvidence: [], previousReflection: reflection, memories: [memory],
        reflectionBookID: reflection.bookID, budget: budget
    )
    #expect(result.evidence.isEmpty)
    #expect(result.stats.usedCharacters == 0)
}

private func locator(_ progression: Double) throws -> BookLocator {
    let data = try JSONSerialization.data(withJSONObject: ["href": "0.xhtml", "locations": ["progression": progression]])
    return try BookLocator(json: data, href: "0.xhtml", progression: progression)
}

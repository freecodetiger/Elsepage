import ContextEngineering
import ContextRouting
import Foundation
import LibraryCore
import ReaderCore
import ReflectionCore
import RetrievalCore
import Testing

@Test func assemblerPrioritizesEvidenceSources() throws {
    let reflection = Reflection(bookID: BookID(), originalText: "过去的想法正文", inputKind: .text)
    let locator = try locator(0.5)
    let book = BookEvidence(id: .init(rawValue: "parent-1"), bookID: reflection.bookID, chapterTitle: "第三章", sectionTitle: "自由",
        excerpt: "书的段落内容", locator: locator, score: 0.9)
    let nearby = NearbyPassageCandidate(text: "当前读到的原文片段", sourceID: "nearby-source", locator: locator)

    let budget = ContextBudget(totalCharacters: 6_000, nearbyCharacters: 1_400, bookEvidenceCharacters: 2_800, pastThoughtCharacters: 600, conversationCharacters: 1_200)
    let result = ContextAssembler().assemble(
        nearby: nearby, bookEvidence: [book], previousReflection: reflection,
        reflectionBookID: reflection.bookID, budget: budget
    )
    // Source priority: nearby > bookPassage > pastReflection.
    #expect(result.evidence.map(\.kind) == [.nearbyPassage, .bookPassage, .pastReflection])
    #expect(result.evidence.map(\.title) == ["当前阅读位置", "第三章 / 自由", "过去的想法"])
}

@Test func assemblerDropsSourcesWithZeroBudget() throws {
    let reflection = Reflection(bookID: BookID(), originalText: "过去的想法", inputKind: .text)
    // emotionalRecord: pastThought budget 0 → reflection candidates are skipped.
    let budget = ContextBudget(totalCharacters: 6_000, nearbyCharacters: 600, bookEvidenceCharacters: 0, pastThoughtCharacters: 0, conversationCharacters: 1_800)
    let result = ContextAssembler().assemble(
        nearby: nil, bookEvidence: [], previousReflection: reflection,
        reflectionBookID: reflection.bookID, budget: budget
    )
    #expect(result.evidence.isEmpty)
    #expect(result.stats.usedCharacters == 0)
}

@Test func assemblerKeepsBrainCandidatesSeparateFromEvidence() throws {
    let reflection = Reflection(bookID: BookID(), originalText: "过去的想法", inputKind: .text)
    let budget = ContextBudget(totalCharacters: 6_000, nearbyCharacters: 600, bookEvidenceCharacters: 0, pastThoughtCharacters: 600, conversationCharacters: 1_800)
    let brainCandidate = ContextCandidate(
        id: "brain-1", source: .brain, content: "我一直在想自由与责任", relevance: 0.9,
        metadata: ["brainKind": "memory"]
    )
    let result = ContextAssembler().assemble(
        nearby: nil, bookEvidence: [], previousReflection: nil,
        reflectionBookID: reflection.bookID, budget: budget,
        brainCandidates: [brainCandidate]
    )
    // Brain items are never [E]-citable evidence; they surface as brainCandidates.
    #expect(result.evidence.isEmpty)
    #expect(result.brainCandidates.map(\.id) == ["brain-1"])
}

private func locator(_ progression: Double) throws -> BookLocator {
    let data = try JSONSerialization.data(withJSONObject: ["href": "0.xhtml", "locations": ["progression": progression]])
    return try BookLocator(json: data, href: "0.xhtml", progression: progression)
}

import ContextEngineering
import Testing

@Test func rankerDeduplicatesSameSourceAndID() {
    let c1 = candidate("c1", source: .bookPassage, content: "制度结构", relevance: 0.9)
    let c1low = candidate("c1", source: .bookPassage, content: "制度结构", relevance: 0.4)
    let result = ranker.build(from: [c1, c1low], budget: unlimited)
    #expect(result.stats.deduplicatedCount == 1)
    #expect(result.bundle.candidates.count == 1)
    #expect(result.bundle.candidates[0].relevance == 0.9)
}

@Test func rankerMergesCandidatesSharingParentIntoOneWindow() {
    let c1 = candidate("c1", source: .bookPassage, content: "甲段", relevance: 0.8, parent: "P", ordinal: 0)
    let c2 = candidate("c2", source: .bookPassage, content: "乙段", relevance: 0.7, parent: "P", ordinal: 1)
    let result = ranker.build(from: [c2, c1], budget: unlimited)
    #expect(result.bundle.candidates.count == 1)
    #expect(result.bundle.candidates[0].content == "甲段\n\n乙段") // ordinal order, not insertion order
}

@Test func rankerPacksBySourcePriorityWithinBudget() {
    let memory = candidate("m1", source: .memory, content: "长期记忆", relevance: 0.9)
    let book = candidate("b1", source: .bookPassage, content: "书的段落内容较长占用预算", relevance: 0.8)
    let budget = ContextBudgetProfile(totalCharacters: 12, perSource: [.bookPassage: 12, .memory: 12])
    let result = ranker.build(from: [memory, book], budget: budget)
    // bookPassage has higher priority than memory and fills the total budget first.
    #expect(result.bundle.candidates.map(\.source) == [.bookPassage])
    #expect(result.bundle.candidates[0].content.count == 12) // truncated to remaining total
}

@Test func rankerTruncatesOverBudgetCandidates() {
    let book = candidate("b1", source: .bookPassage, content: "这一段内容超过了预算很多很多很多", relevance: 0.8)
    let result = ranker.build(from: [book], budget: ContextBudgetProfile(totalCharacters: 100, perSource: [.bookPassage: 5]))
    #expect(result.bundle.candidates.count == 1)
    #expect(result.bundle.candidates[0].content.count == 5)
    #expect(result.stats.usedCharacters == 5)
}

@Test func rankerSkipsCandidatesWhoseSourceBudgetIsExhausted() {
    let book1 = candidate("b1", source: .bookPassage, content: "第一部分", relevance: 0.9)
    let book2 = candidate("b2", source: .bookPassage, content: "第二部分", relevance: 0.8)
    let result = ranker.build(from: [book1, book2], budget: ContextBudgetProfile(totalCharacters: 100, perSource: [.bookPassage: 4]))
    #expect(result.bundle.candidates.count == 1) // b1 takes the whole book budget; b2 skipped
    #expect(result.bundle.candidates[0].id == "b1")
}

@Test func rankerIsDeterministic() {
    let input = [
        candidate("b1", source: .bookPassage, content: "乙", relevance: 0.7),
        candidate("m1", source: .memory, content: "记忆", relevance: 0.9),
        candidate("n1", source: .nearbyPassage, content: "当前", relevance: 0.5),
        candidate("c1", source: .conversation, content: "对话", relevance: 0.8),
    ]
    let budget = ContextBudgetProfile(totalCharacters: 200, perSource: [.nearbyPassage: 50, .bookPassage: 50, .memory: 50, .conversation: 50])
    let a = ranker.build(from: input, budget: budget)
    let b = ranker.build(from: input, budget: budget)
    #expect(a.bundle == b.bundle)
    // Order respects source priority: nearby > book > memory > conversation.
    #expect(a.bundle.candidates.map(\.source) == [.nearbyPassage, .bookPassage, .memory, .conversation])
}

// MARK: - Helpers

private let ranker = ContextCandidateRanker()

private let unlimited = ContextBudgetProfile(totalCharacters: 10_000, perSource: [.nearbyPassage: 10_000, .bookPassage: 10_000, .pastReflection: 10_000, .memory: 10_000, .conversation: 10_000])

private func candidate(_ id: String, source: ContextSource, content: String, relevance: Double, parent: String? = nil, ordinal: Int? = nil) -> ContextCandidate {
    var metadata: [String: String] = [:]
    if let parent { metadata[ContextCandidateRanker.parentIDKey] = parent }
    if let ordinal { metadata[ContextCandidateRanker.ordinalKey] = String(ordinal) }
    return ContextCandidate(id: id, source: source, content: content, relevance: relevance, tokenCost: content.count, metadata: metadata)
}

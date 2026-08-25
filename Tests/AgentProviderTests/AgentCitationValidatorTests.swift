import Foundation
import LibraryCore
import ReaderAgent
import ReflectionCore
import RetrievalCore
import Testing

@Test func citationValidatorAcceptsKnownEvidenceAndDeduplicatesRepeatedMarkers() async {
    let messageID = UUID()
    let evidence = evidenceFixture(id: "E1", messageID: messageID)
    let result = await AgentCitationValidator().validate(
        content: "这一处形成了张力 [E1]，后文仍然延续 [E1]。",
        messageID: messageID,
        evidence: [evidence]
    )
    #expect(result.content == "这一处形成了张力 [E1]，后文仍然延续 [E1]。")
    #expect(result.citations.map(\.evidenceID) == ["E1"])
}

@Test func citationValidatorRemovesUnknownMarkersWithoutAcceptingThem() async {
    let messageID = UUID()
    let result = await AgentCitationValidator().validate(
        content: "有证据的部分 [E1]，不存在的来源 [E9]。",
        messageID: messageID,
        evidence: [evidenceFixture(id: "E1", messageID: messageID)]
    )
    #expect(result.content == "有证据的部分 [E1]，不存在的来源 。")
    #expect(result.citations.map(\.evidenceID) == ["E1"])
}

@Test func citationValidatorAllowsAResponseWithoutCitations() async {
    let messageID = UUID()
    let result = await AgentCitationValidator().validate(
        content: "这次只是接住用户的感受。",
        messageID: messageID,
        evidence: [evidenceFixture(id: "E1", messageID: messageID)]
    )
    #expect(result.content == "这次只是接住用户的感受。")
    #expect(result.citations.isEmpty)
}

@Test func citationValidatorHonorsStructuredBlockAndStripsItFromDisplay() async {
    let messageID = UUID()
    let evidence = [
        evidenceFixture(id: "E1", messageID: messageID),
        evidenceFixture(id: "E2", messageID: messageID, sourceID: "chunk-2"),
    ]
    let content = "依赖第一处 [E1]，也依赖第二处 [E2]。\n---CITATIONS---\n[{\"evidenceID\":\"chunk-1\",\"kind\":\"bookPassage\",\"connectionID\":null}]"
    let result = await AgentCitationValidator().validate(
        content: content,
        messageID: messageID,
        evidence: evidence
    )
    // Only E1's sourceID (chunk-1) is listed in the structured block; E2 is dropped.
    #expect(result.content == "依赖第一处 [E1]，也依赖第二处 。")
    #expect(result.citations.map(\.evidenceID) == ["E1"])
}

@Test func citationValidatorFallsBackToInlineOnlyWhenNoStructuredBlock() async {
    let messageID = UUID()
    let evidence = [
        evidenceFixture(id: "E1", messageID: messageID),
        evidenceFixture(id: "E2", messageID: messageID, sourceID: "chunk-2"),
    ]
    let result = await AgentCitationValidator().validate(
        content: "两处都有效 [E1][E2]。",
        messageID: messageID,
        evidence: evidence
    )
    #expect(result.citations.map(\.evidenceID) == ["E1", "E2"])
}

private func evidenceFixture(id: String, messageID: UUID, sourceID: String = "chunk-1") -> AgentResponseEvidence {
    .init(
        id: id, messageID: messageID, kind: .bookPassage, sourceID: sourceID,
        bookID: BookID(), title: "第一章", excerpt: "被发送给模型的证据"
    )
}

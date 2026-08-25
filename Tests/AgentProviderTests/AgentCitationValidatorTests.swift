import Foundation
import LibraryCore
import ReaderAgent
import ReflectionCore
import Testing

@Test func citationValidatorAcceptsKnownEvidenceAndDeduplicatesRepeatedMarkers() {
    let messageID = UUID()
    let evidence = evidenceFixture(id: "E1", messageID: messageID)
    let result = AgentCitationValidator().validate(
        content: "这一处形成了张力 [E1]，后文仍然延续 [E1]。",
        messageID: messageID,
        evidence: [evidence]
    )
    #expect(result.content == "这一处形成了张力 [E1]，后文仍然延续 [E1]。")
    #expect(result.citations.map(\.evidenceID) == ["E1"])
}

@Test func citationValidatorRemovesUnknownMarkersWithoutAcceptingThem() {
    let messageID = UUID()
    let result = AgentCitationValidator().validate(
        content: "有证据的部分 [E1]，不存在的来源 [E9]。",
        messageID: messageID,
        evidence: [evidenceFixture(id: "E1", messageID: messageID)]
    )
    #expect(result.content == "有证据的部分 [E1]，不存在的来源 。")
    #expect(result.citations.map(\.evidenceID) == ["E1"])
}

@Test func citationValidatorAllowsAResponseWithoutCitations() {
    let messageID = UUID()
    let result = AgentCitationValidator().validate(
        content: "这次只是接住用户的感受。",
        messageID: messageID,
        evidence: [evidenceFixture(id: "E1", messageID: messageID)]
    )
    #expect(result.content == "这次只是接住用户的感受。")
    #expect(result.citations.isEmpty)
}

private func evidenceFixture(id: String, messageID: UUID) -> AgentResponseEvidence {
    .init(
        id: id, messageID: messageID, kind: .bookPassage, sourceID: "chunk-1",
        bookID: BookID(), title: "第一章", excerpt: "被发送给模型的证据"
    )
}

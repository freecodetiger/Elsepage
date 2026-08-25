import Foundation
import GRDB
import LibraryCore
import Persistence
import ReflectionCore
import Testing

@Test func agentResponseEvidenceAndCitationsRoundTripWithExactLocatorJSON() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book(); try await GRDBBookRepository(database: database).insert(book)
    let repository = GRDBReflectionRepository(database: database)
    let reflection = Reflection(bookID: book.id, originalText: "我注意到了制度的作用。", inputKind: .text)
    try await repository.insert(reflection, linkedHighlightIDs: [], evidence: [])
    let message = try ReflectionMessage(
        reflectionID: reflection.id, author: .agent, source: .agentGenerated,
        content: "这里的变化来自视角移动 [E1]。"
    )
    let locator = try TestFixtures.realisticLocator()
    let evidence = AgentResponseEvidence(
        id: "E1", messageID: message.id, kind: .bookPassage, sourceID: "chunk-stable-1",
        bookID: book.id, title: "第一章", excerpt: "制度让局部选择汇聚。", locator: locator
    )
    let citation = AgentCitation(messageID: message.id, evidenceID: "E1", marker: "E1")

    try await repository.appendAgentMessage(message, evidence: [evidence], citations: [citation])
    let stored = try await repository.provenance(for: message.id)

    #expect(stored == .init(evidence: [evidence], citations: [citation]))
    #expect(stored.evidence.first?.locator?.json == locator.json)
    #expect(stored.evidence.first?.locator?.identifiesSameAnchor(as: locator) == true)
}

@Test func unknownCitationRollsBackMessageAndAllProvenance() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book(); try await GRDBBookRepository(database: database).insert(book)
    let repository = GRDBReflectionRepository(database: database)
    let reflection = Reflection(bookID: book.id, originalText: "原始 Reflection", inputKind: .text)
    try await repository.insert(reflection, linkedHighlightIDs: [], evidence: [])
    let message = try ReflectionMessage(
        reflectionID: reflection.id, author: .agent, source: .agentGenerated, content: "无效来源 [E9]"
    )
    let evidence = AgentResponseEvidence(
        id: "E1", messageID: message.id, kind: .bookPassage, sourceID: "chunk-1",
        bookID: book.id, excerpt: "真实证据"
    )

    await #expect(throws: (any Error).self) {
        try await repository.appendAgentMessage(
            message, evidence: [evidence],
            citations: [.init(messageID: message.id, evidenceID: "E9", marker: "E9")]
        )
    }
    #expect(try await repository.message(id: message.id) == nil)
    #expect(try await repository.provenance(for: message.id).evidence.isEmpty)
}

@Test func deletingAgentMessageCascadesItsEvidenceAndCitations() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book(); try await GRDBBookRepository(database: database).insert(book)
    let repository = GRDBReflectionRepository(database: database)
    let reflection = Reflection(bookID: book.id, originalText: "原始 Reflection", inputKind: .text)
    try await repository.insert(reflection, linkedHighlightIDs: [], evidence: [])
    let message = try ReflectionMessage(
        reflectionID: reflection.id, author: .agent, source: .agentGenerated, content: "回应 [E1]"
    )
    let evidence = AgentResponseEvidence(
        id: "E1", messageID: message.id, kind: .bookPassage, sourceID: "chunk-1",
        bookID: book.id, excerpt: "证据"
    )
    try await repository.appendAgentMessage(
        message, evidence: [evidence], citations: [.init(messageID: message.id, evidenceID: "E1", marker: "E1")]
    )

    try await repository.delete(id: reflection.id)
    let counts = try await database.writer.read { db in
        (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM agentResponseEvidence")!,
         try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM agentCitations")!)
    }
    #expect(counts.0 == 0)
    #expect(counts.1 == 0)
}

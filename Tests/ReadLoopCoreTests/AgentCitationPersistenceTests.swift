import Foundation
import GRDB
import LibraryCore
import Persistence
import ReaderAgent
import ReflectionCore
import RetrievalCore
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

@Test func messagesLoadAgentCitationsInlineForAgentMessagesOnly() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book(); try await GRDBBookRepository(database: database).insert(book)
    let repository = GRDBReflectionRepository(database: database)
    let reflection = Reflection(bookID: book.id, originalText: "原始 Reflection", inputKind: .text)
    try await repository.insert(reflection, linkedHighlightIDs: [], evidence: [])
    let agentMessage = try ReflectionMessage(
        reflectionID: reflection.id, author: .agent, source: .agentGenerated, content: "回应 [E1]"
    )
    let userMessage = try ReflectionMessage(
        reflectionID: reflection.id, author: .user, source: .userInput, content: "继续说"
    )
    let evidence = AgentResponseEvidence(
        id: "E1", messageID: agentMessage.id, kind: .bookPassage, sourceID: "chunk-1",
        bookID: book.id, excerpt: "证据"
    )
    try await repository.appendMessage(userMessage)
    try await repository.appendAgentMessage(
        agentMessage, evidence: [evidence],
        citations: [.init(messageID: agentMessage.id, evidenceID: "E1", marker: "E1")]
    )
    let loaded = try await repository.messages(for: reflection.id)
    #expect(loaded.first(where: { $0.id == agentMessage.id })?.citations?.map(\.evidenceID) == ["E1"])
    #expect(loaded.first(where: { $0.id == userMessage.id })?.citations == nil)
}

@Test func validatorRejectsBookPassageChunkOutsideBoundaryOrMissingFromIndex() async throws {
    let database = try AppDatabase.inMemory()
    let book = TestFixtures.book(); try await GRDBBookRepository(database: database).insert(book)
    let index = GRDBBookIndexRepository(database: database)
    let version = BookIndexPipeline.currentVersion
    let within = try makeChunk(id: "chunk-within", book: book, resourceOrdinal: 0, ordinal: 0, progression: 0.3)
    let outside = try makeChunk(id: "chunk-outside", book: book, resourceOrdinal: 0, ordinal: 1, progression: 0.9)
    try await index.replace(chunks: [within, outside], for: book.id, version: version)

    let messageID = UUID()
    let evidence = [
        AgentResponseEvidence(id: "E1", messageID: messageID, kind: .bookPassage, sourceID: "chunk-within", bookID: book.id, title: "章", excerpt: "x"),
        AgentResponseEvidence(id: "E2", messageID: messageID, kind: .bookPassage, sourceID: "chunk-outside", bookID: book.id, title: "章", excerpt: "x"),
        AgentResponseEvidence(id: "E3", messageID: messageID, kind: .bookPassage, sourceID: "chunk-missing", bookID: book.id, title: "章", excerpt: "x"),
    ]
    let result = await AgentCitationValidator().validate(
        content: "引用 [E1][E2][E3]。",
        messageID: messageID,
        evidence: evidence,
        bookIndex: index,
        readingBoundary: ReadingBoundary(resourceOrdinal: 0, progression: 0.42)
    )
    #expect(result.content == "引用 [E1]。")
    #expect(result.citations.map(\.evidenceID) == ["E1"])
}

private func makeChunk(id: String, book: Book, resourceOrdinal: Int, ordinal: Int, progression: Double) throws -> BookChunk {
    let start = try TestFixtures.realisticLocator(progression: progression)
    let end = try TestFixtures.realisticLocator(progression: min(1, progression + 0.02))
    return BookChunk(
        id: .init(rawValue: id), bookID: book.id, resourceHref: start.href,
        resourceOrdinal: resourceOrdinal, ordinal: ordinal, text: "内容", normalizedText: "内容",
        startLocator: start, endLocator: end, sourceBlockIDs: []
    )
}

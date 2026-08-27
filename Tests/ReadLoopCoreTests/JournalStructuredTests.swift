import Foundation
import LibraryCore
import Persistence
import ReaderCore
import ReadingSessionCore
import ReflectionCore
import RetrievalCore
import Testing

@Test func journalStructuredParserDecodesEmbeddedJSONEnvelope() throws {
    let content = """
    这个选择其实更接近责任。
    {
      "question": "这个选择是否真的自由？",
      "whatIThink": ["忠于用户的观察", "另一个想法"],
      "memory_proposals": [
        {"type": "store", "id": null, "summary": "用户重视自由与责任"}
      ],
      "citations": [
        {"title": "第一章", "excerpt": "制度结构塑造选择", "locator": {"href": "0.xhtml", "progression": 0.1}}
      ]
    }
    后面还有一段普通文字。
    """
    let parsed = JournalStructuredParser.parse(content)
    #expect(parsed.thoughts == ["忠于用户的观察", "另一个想法"])
    #expect(parsed.question == "这个选择是否真的自由？")
    #expect(parsed.memoryProposals.count == 1)
    #expect(parsed.memoryProposals[0].changeType == .store)
    #expect(parsed.memoryProposals[0].summary == "用户重视自由与责任")
    #expect(parsed.citations.count == 1)
    #expect(parsed.citations[0].title == "第一章")
    #expect(parsed.citations[0].locator?.href == "0.xhtml")
}

@Test func journalStructuredParserIgnoresPlainProse() {
    let parsed = JournalStructuredParser.parse("这里没有结构化输出，只是一段普通的回应文字。")
    #expect(parsed == .empty)
}

@Test func journalChapterResolutionUsesSessionSpan() async throws {
    let db = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: db)
    let index = GRDBBookIndexRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "journal-chapters"), title: "章节目", fileName: "chapters.epub", fileSize: 1)
    try await books.insert(book)

    let chunks = [
        try chunk(book: book.id, id: "c0", resource: 0, progression: 0.2, text: "第一章正文"),
        try chunk(book: book.id, id: "c2", resource: 2, progression: 0.5, text: "第三章正文"),
    ]
    try await index.replace(chunks: chunks, for: book.id, version: BookIndexPipeline.currentVersion)
    try await index.replace(blocks: [try block(book: book.id, id: "b0", resource: 0, chapterID: "ch0", chapterTitle: "第一章")], inResource: "0.xhtml", for: book.id, version: BookIndexPipeline.currentVersion)
    try await index.replace(blocks: [try block(book: book.id, id: "b2", resource: 2, chapterID: "ch2", chapterTitle: "第三章")], inResource: "2.xhtml", for: book.id, version: BookIndexPipeline.currentVersion)

    let start = try locator(href: "0.xhtml", progression: 0.1)
    let end = try locator(href: "2.xhtml", progression: 0.9)
    let chapters = try await index.chapters(for: book.id, from: start, to: end)
    #expect(chapters.map(\.title) == ["第一章", "第三章"])

    let single = try await index.chapters(for: book.id, from: start, to: nil)
    #expect(single.map(\.title) == ["第一章"])
}

@Test func journalRepositoryRoundTripsQuestionThoughtCitationAndMemoryChange() async throws {
    let db = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: db)
    let reflections = GRDBReflectionRepository(database: db)
    let journal = GRDBJournalRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "journal-repo"), title: "仓库", fileName: "repo.epub", fileSize: 1)
    try await books.insert(book)
    let reflection = Reflection(bookID: book.id, originalText: "一条想法", inputKind: .text)
    try await reflections.insert(reflection, linkedHighlightIDs: [], evidence: [])

    let messageID = UUID()
    try await journal.saveThought(.init(reflectionID: reflection.id, messageID: messageID, thought: "我想保持克制"))
    try await journal.saveQuestion(.init(reflectionID: reflection.id, messageID: messageID, text: "还想继续吗？"))
    let citationLocator = try locator(href: "0.xhtml", progression: 0.3)
    try await journal.saveCitation(.init(reflectionID: reflection.id, messageID: messageID, sourceType: .bookLocator, bookID: book.id, locator: citationLocator, title: "第一章", excerpt: "原文引用"))
    try await journal.saveMemoryChange(.init(journalID: reflection.id, changeType: .store, summary: "用户喜欢简洁"))

    #expect(try await journal.thoughts(for: reflection.id).map(\.thought) == ["我想保持克制"])
    #expect(try await journal.questions(for: reflection.id).first?.text == "还想继续吗？")
    let citation = try #require(try await journal.citations(for: reflection.id).first)
    #expect(citation.title == "第一章")
    #expect(citation.locator?.href == "0.xhtml")
    #expect(try await journal.memoryChanges(for: reflection.id).first?.summary == "用户喜欢简洁")
    #expect(try await journal.hasStructuredData(for: reflection.id, messageID: messageID))
    #expect(!(try await journal.hasStructuredData(for: reflection.id, messageID: UUID())))
}

@Test func journalEntryServiceAssemblesSessionChaptersHighlightsAndStructuredOutput() async throws {
    let db = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: db)
    let reading = GRDBReadingRepository(database: db)
    let sessionsRepo = GRDBReadingSessionRepository(database: db)
    let reflections = GRDBReflectionRepository(database: db)
    let journal = GRDBJournalRepository(database: db)
    let index = GRDBBookIndexRepository(database: db)

    let book = Book(fingerprint: .init(rawValue: "journal-full"), title: "完整日志", fileName: "full.epub", fileSize: 1)
    try await books.insert(book)
    try await index.replace(chunks: [
        try chunk(book: book.id, id: "c0", resource: 0, progression: 0.2, text: "第一章正文"),
        try chunk(book: book.id, id: "c2", resource: 2, progression: 0.5, text: "第三章正文"),
    ], for: book.id, version: BookIndexPipeline.currentVersion)
    try await index.replace(blocks: [try block(book: book.id, id: "b0", resource: 0, chapterID: "ch0", chapterTitle: "第一章")], inResource: "0.xhtml", for: book.id, version: BookIndexPipeline.currentVersion)
    try await index.replace(blocks: [try block(book: book.id, id: "b2", resource: 2, chapterID: "ch2", chapterTitle: "第三章")], inResource: "2.xhtml", for: book.id, version: BookIndexPipeline.currentVersion)

    let t0 = Date(timeIntervalSince1970: 1_000)
    let mid = Date(timeIntervalSince1970: 1_030)
    let t1 = Date(timeIntervalSince1970: 1_090)
    let startLocator = try locator(href: "0.xhtml", progression: 0.1)
    let endLocator = try locator(href: "2.xhtml", progression: 0.9)
    let session = ReadingSession(bookID: book.id, startedAt: t0, endedAt: t1, startLocator: startLocator, endLocator: endLocator)
    try await sessionsRepo.insert(session)

    let highlight = Highlight(bookID: book.id, locator: try locator(href: "1.xhtml", progression: 0.4), createdAt: mid)
    try await reading.save(highlight: highlight)

    let submitted = try await TextReflectionSubmissionService(repository: reflections).submit(.init(
        bookID: book.id, sessionID: session.id, locator: endLocator,
        originalText: "读到第三章，我想起自由与责任。", linkedHighlightIDs: [highlight.id]
    ))

    let structured = """
    {
      "question": "责任与自由能否同时成立？",
      "whatIThink": ["用户在第三章重新审视了自由与责任"],
      "memory_proposals": [
        {"type": "reinforce", "id": "mem-1", "summary": "自由与责任是持续的母题"}
      ],
      "citations": [
        {"title": "第一章", "excerpt": "制度结构塑造选择", "locator": {"href": "0.xhtml", "progression": 0.2}}
      ]
    }
    """
    try await reflections.appendMessage(try ReflectionMessage(reflectionID: submitted.id, author: .agent, source: .agentGenerated, content: structured))

    let service = JournalEntryService(
        books: books, reflections: reflections, sessions: sessionsRepo,
        index: index, reading: reading, journal: journal
    )
    let entries = try await service.recentEntries()
    #expect(entries.count == 1)
    let entry = try #require(entries.first)
    #expect(entry.session?.duration == t1.timeIntervalSince(t0))
    #expect(entry.chapters.map(\.title) == ["第一章", "第三章"])
    #expect(entry.linkedHighlights.map(\.id) == [highlight.id])
    #expect(entry.whatIThink.map(\.thought) == ["用户在第三章重新审视了自由与责任"])
    #expect(entry.questions.first?.text == "责任与自由能否同时成立？")
    #expect(entry.citations.first?.title == "第一章")
    #expect(entry.citations.first?.locator?.href == "0.xhtml")
    #expect(entry.memoryChanges.first?.changeType == .reinforce)
    #expect(entry.memoryChanges.first?.summary == "自由与责任是持续的母题")

    // Materialization is idempotent across reloads.
    _ = try await service.recentEntries()
    #expect(try await journal.thoughts(for: submitted.id).count == 1)
}

@Test func textSubmissionLinksSessionHighlightsThroughInsert() async throws {
    let db = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: db)
    let reading = GRDBReadingRepository(database: db)
    let reflections = GRDBReflectionRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "journal-highlight-link"), title: "高亮", fileName: "highlight.epub", fileSize: 1)
    try await books.insert(book)
    let highlight = Highlight(bookID: book.id, locator: try locator(href: "0.xhtml", progression: 0.2))
    try await reading.save(highlight: highlight)

    let draft = TextReflectionDraft(
        bookID: book.id, sessionID: nil, locator: try locator(href: "0.xhtml", progression: 0.2),
        originalText: "把这次的高亮带进日志", linkedHighlightIDs: [highlight.id]
    )
    let reflection = try await TextReflectionSubmissionService(repository: reflections).submit(draft)
    #expect(try await reflections.linkedHighlightIDs(for: reflection.id) == [highlight.id])
}

// MARK: - Helpers

private func locator(href: String, progression: Double) throws -> BookLocator {
    let json = try JSONSerialization.data(withJSONObject: ["href": href, "locations": ["progression": progression]])
    return try BookLocator(json: json, href: href, progression: progression)
}

private func chunk(book: BookID, id: String, resource: Int, progression: Double, text: String) throws -> BookChunk {
    let locator = try locator(href: "\(resource).xhtml", progression: progression)
    return BookChunk(id: .init(rawValue: id), bookID: book, resourceHref: locator.href,
        resourceOrdinal: resource, ordinal: resource, text: text, normalizedText: text,
        startLocator: locator, endLocator: locator, sourceBlockIDs: [.init(rawValue: "block-\(id)")])
}

private func block(book: BookID, id: String, resource: Int, chapterID: String, chapterTitle: String) throws -> BookTextBlock {
    let locator = try locator(href: "\(resource).xhtml", progression: 0.5)
    return BookTextBlock(id: .init(rawValue: id), bookID: book, resourceHref: locator.href,
        chapterID: chapterID, chapterTitle: chapterTitle, resourceOrdinal: resource, ordinal: resource,
        text: "\(chapterTitle)正文", startLocator: locator, endLocator: locator)
}

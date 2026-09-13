import AgentRuntime
import Foundation
import LibraryCore
import Persistence
import ReaderAgent
import ReaderCore
import RetrievalCore
import Testing

@Test func readerHelpUsesCARCContextAndExcludesFutureTextAndLocatorTextAfter() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let index = GRDBBookIndexRepository(database: database)
    let book = TestFixtures.book(fingerprint: "reader-help-carc")
    try await books.insert(book)

    let version = BookIndexPipeline.currentVersion
    let past = try chunk(
        bookID: book.id,
        id: "past",
        start: 0.1,
        end: 0.2,
        text: "前面已经读到的结构说明。"
    )
    let active = try chunk(
        bookID: book.id,
        id: "active",
        start: 0.2,
        end: 0.4,
        text: "当前段落完整内容，结构在这里表示外部条件。"
    )
    let future = try chunk(
        bookID: book.id,
        id: "future",
        start: 0.4,
        end: 0.6,
        text: "未来才会揭晓的结构结局。"
    )
    try await index.replace(chunks: [past, active, future], for: book.id, version: version)
    try await index.save(job: BookIndexJob(
        bookID: book.id,
        indexVersion: version,
        state: .lexicalReady,
        nextResourceOrdinal: 1
    ))

    let anchor = try BookLocator(
        json: Data(#"{"href":"0.xhtml","locations":{"progression":0.3}}"#.utf8),
        href: "0.xhtml",
        progression: 0.3,
        textBefore: "已经读到的前缀",
        textHighlight: "结构",
        textAfter: "LOCATOR_TEXT_AFTER_MUST_NOT_APPEAR"
    )
    let builder = ReaderAgentContextBuilder(
        retriever: LocalBookRetriever(repository: index),
        repository: index
    )
    let client = HelpRecordingModelClient()
    let service = ReaderHelpService(
        models: HelpFixedModelFactory(client: client),
        contextBuilder: builder
    )
    let request = ReaderHelpRequest(
        bookID: book.id,
        anchor: anchor,
        selectedText: "结构",
        question: "这里的结构是什么意思？"
    )

    let events = await collectHelpEvents(service.answer(request))
    guard case .contextPrepared(let summary)? = events.first(where: {
        if case .contextPrepared = $0 { return true }
        return false
    }) else {
        Issue.record("Expected context summary"); return
    }
    #expect(summary.includedNearbyPassage)
    #expect(summary.usedActiveChunk)
    #expect(summary.retrievedBookEvidenceCount >= 1)
    #expect(summary.failClosedReason == nil)

    let prompt = try #require(client.requests.first).messages.map(\.content).joined(separator: "\n")
    #expect(prompt.contains("当前段落完整内容"))
    #expect(prompt.contains("前面已经读到的结构说明"))
    #expect(!prompt.contains("未来才会揭晓的结构结局"))
    #expect(!prompt.contains("LOCATOR_TEXT_AFTER_MUST_NOT_APPEAR"))
}

@Test func readerHelpFailsClosedForMissingProgression() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let index = GRDBBookIndexRepository(database: database)
    let book = TestFixtures.book(fingerprint: "reader-help-missing-progression")
    try await books.insert(book)
    try await index.replace(
        chunks: [try chunk(bookID: book.id, id: "active", start: 0.2, end: 0.4, text: "不应通过全书检索进入")],
        for: book.id,
        version: BookIndexPipeline.currentVersion
    )
    try await index.save(job: BookIndexJob(
        bookID: book.id,
        indexVersion: BookIndexPipeline.currentVersion,
        state: .lexicalReady
    ))

    let anchor = try BookLocator(
        json: Data(#"{"href":"0.xhtml"}"#.utf8),
        href: "0.xhtml",
        textBefore: "可见前缀",
        textHighlight: "可见选段",
        textAfter: "不可见未来"
    )
    let builder = ReaderAgentContextBuilder(
        retriever: LocalBookRetriever(repository: index),
        repository: index
    )
    let client = HelpRecordingModelClient()
    let service = ReaderHelpService(
        models: HelpFixedModelFactory(client: client),
        contextBuilder: builder
    )

    let events = await collectHelpEvents(service.answer(ReaderHelpRequest(
        bookID: book.id,
        anchor: anchor,
        selectedText: "可见选段",
        question: "这是什么？"
    )))
    guard case .contextPrepared(let summary)? = events.first(where: {
        if case .contextPrepared = $0 { return true }
        return false
    }) else {
        Issue.record("Expected context summary"); return
    }
    #expect(summary.failClosedReason == .unresolvedReadingBoundary)
    #expect(summary.retrievedBookEvidenceCount == 0)

    let prompt = try #require(client.requests.first).messages.map(\.content).joined(separator: "\n")
    #expect(prompt.contains("可见选段"))
    #expect(!prompt.contains("不应通过全书检索进入"))
    #expect(!prompt.contains("不可见未来"))
}

private func chunk(
    bookID: BookID,
    id: String,
    start: Double,
    end: Double,
    text: String
) throws -> BookChunk {
    let startLocator = try BookLocator(
        json: Data(#"{"href":"0.xhtml","locations":{"progression":\#(start)}}"#.utf8),
        href: "0.xhtml",
        progression: start
    )
    let endLocator = try BookLocator(
        json: Data(#"{"href":"0.xhtml","locations":{"progression":\#(end)}}"#.utf8),
        href: "0.xhtml",
        progression: end
    )
    return BookChunk(
        id: .init(rawValue: id),
        bookID: bookID,
        resourceHref: "0.xhtml",
        resourceOrdinal: 0,
        ordinal: Int(start * 100_000),
        text: text,
        normalizedText: text,
        startLocator: startLocator,
        endLocator: endLocator,
        sourceBlockIDs: [],
        role: .child
    )
}

private struct HelpFixedModelFactory: ModelClientFactory {
    let client: any ModelClient
    func makeClient() async throws -> any ModelClient { client }
}

private final class HelpRecordingModelClient: @unchecked Sendable, ModelClient {
    let descriptor = ModelDescriptor(
        provider: "fake",
        model: "reader-help-recording",
        capabilities: .init(supportsStreaming: true)
    )
    private let lock = NSLock()
    private var storage: [ModelRequest] = []

    var requests: [ModelRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func stream(request: ModelRequest) -> AsyncThrowingStream<ModelEvent, Error> {
        lock.lock()
        storage.append(request)
        lock.unlock()
        let content = "结构在这里表示影响选择的外部条件。"
        return FakeModelClient(events: [
            .started,
            .textDelta(content),
            .completed(ModelResponse(content: content))
        ]).stream(request: request)
    }
}

private func collectHelpEvents(_ stream: AsyncStream<ReaderHelpEvent>) async -> [ReaderHelpEvent] {
    var events: [ReaderHelpEvent] = []
    for await event in stream { events.append(event) }
    return events
}

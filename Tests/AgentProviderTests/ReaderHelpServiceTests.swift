import AgentRuntime
import Foundation
import LibraryCore
import ReaderAgent
import ReaderCore
import ReflectionCore
import Testing

@Test func readerHelpStreamsWithoutReflectionPersistenceAndUsesOneModelCall() async throws {
    let response = ModelResponse(content: "这里说的是，人在做出选择时也会受到周围结构的影响。")
    let factory = CountingModelFactory(client: FakeModelClient(events: [
        .started,
        .textDelta("这里说的是，"),
        .completed(response)
    ]))
    let service = ReaderHelpService(models: factory)

    let events = await collect(service.answer(try request()))
    guard case .completed(let helpResponse) = events.last else {
        Issue.record("Expected a completed Reader Help response"); return
    }

    #expect(helpResponse.content == response.content)
    #expect(helpResponse.provenance.evidence.map(\.kind) == [.nearbyPassage])
    #expect(!helpResponse.isTruncated)
    #expect(events.contains(.contextPrepared(.init(
        includedNearbyPassage: true,
        retrievedBookEvidenceCount: 0,
        usedActiveChunk: false,
        failClosedReason: .indexUnavailable
    ))))
    #expect(await factory.makeClientCount == 1)
}

@Test func readerHelpPromptUsesVisibleSelectionButNeverTextAfter() async throws {
    let client = RecordingModelClient(response: "解释")
    let service = ReaderHelpService(
        models: FixedReaderHelpFactory(client: client),
        contextBuilder: nil
    )

    _ = await collect(service.answer(try request()))

    let modelRequest = try #require(client.requests.first)
    let prompt = modelRequest.messages.map(\.content).joined(separator: "\n")
    #expect(prompt.contains("a page"))
    #expect(prompt.contains("A reader begins with"))
    #expect(!prompt.contains("returns with a thought"))
    #expect(modelRequest.maxOutputTokens == 600)
}

@Test func readerHelpRejectsInvalidSelectionsAndQuestionsBeforeCallingModel() async throws {
    let factory = CountingModelFactory(client: FakeModelClient(events: [.completed(.init(content: "不会调用"))]))
    let service = ReaderHelpService(models: factory)
    let locator = try helpLocator(selected: "选段")

    let emptySelection = ReaderHelpRequest(
        bookID: BookID(), anchor: locator, selectedText: "   ", question: "这是什么？"
    )
    let emptyQuestion = ReaderHelpRequest(
        bookID: BookID(), anchor: locator, selectedText: "选段", question: "  "
    )
    let longSelection = ReaderHelpRequest(
        bookID: BookID(), anchor: locator, selectedText: String(repeating: "选", count: 1_001), question: "这是什么？"
    )
    let longQuestion = ReaderHelpRequest(
        bookID: BookID(), anchor: locator, selectedText: "选段", question: String(repeating: "问", count: 501)
    )

    #expect(await collect(service.answer(emptySelection)).last == .failed(.invalidSelection))
    #expect(await collect(service.answer(emptyQuestion)).last == .failed(.emptyQuestion))
    #expect(await collect(service.answer(longSelection)).last == .failed(.selectionTooLong))
    #expect(await collect(service.answer(longQuestion)).last == .failed(.questionTooLong))
    #expect(await factory.makeClientCount == 0)
}

@Test func readerHelpMapsProviderAndRuntimeFailures() async throws {
    let missingProvider = ReaderHelpService(models: MissingReaderHelpFactory())
    #expect(await collect(missingProvider.answer(try request())).last == .failed(.providerNotConfigured))

    let runtimeFailure = ReaderHelpService(models: FixedReaderHelpFactory(
        client: FakeModelClient(events: [], terminalFailure: .authentication)
    ))
    #expect(await collect(runtimeFailure.answer(try request())).last == .failed(.runtime(.authentication)))
}

@Test func readerHelpMarksTruncatedResponsesWithoutPersistingThem() async throws {
    let service = ReaderHelpService(models: FixedReaderHelpFactory(
        client: FakeModelClient(events: [
            .started,
            .textDelta("未完成"),
            .completed(ModelResponse(content: "未完成", finishReason: "length"))
        ])
    ))

    let events = await collect(service.answer(try request()))
    guard case .completed(let response) = events.last else {
        Issue.record("Expected truncated completion"); return
    }
    #expect(response.content == "未完成")
    #expect(response.isTruncated)
}

@Test func readerHelpBoundsRecentTurnsAndDropsOldestFirst() async throws {
    let client = RecordingModelClient(response: "解释")
    let service = ReaderHelpService(models: FixedReaderHelpFactory(client: client))
    let turns = (1...8).map { index in
        ReaderHelpTurn(role: index.isMultiple(of: 2) ? .agent : .user, content: "turn-\(index)")
    }
    let request = ReaderHelpRequest(
        bookID: BookID(),
        anchor: try helpLocator(selected: "选段"),
        selectedText: "选段",
        question: "继续",
        recentTurns: turns
    )

    _ = await collect(service.answer(request))

    let prompt = try #require(client.requests.first).messages.map(\.content).joined(separator: "\n")
    #expect(prompt.contains("turn-8"))
    #expect(prompt.contains("turn-3"))
    #expect(!prompt.contains("turn-1"))
    #expect(!prompt.contains("turn-2"))
}

private actor CountingModelFactory: ModelClientFactory {
    private let client: any ModelClient
    private(set) var makeClientCount = 0

    init(client: any ModelClient) { self.client = client }

    func makeClient() async throws -> any ModelClient {
        makeClientCount += 1
        return client
    }
}

private struct FixedReaderHelpFactory: ModelClientFactory {
    let client: any ModelClient
    func makeClient() async throws -> any ModelClient { client }
}

private struct MissingReaderHelpFactory: ModelClientFactory {
    func makeClient() async throws -> any ModelClient { throw ModelFailure.invalidConfiguration }
}

private final class RecordingModelClient: @unchecked Sendable, ModelClient {
    let descriptor = ModelDescriptor(
        provider: "fake",
        model: "recording",
        capabilities: .init(supportsStreaming: true)
    )
    private let response: String
    private let lock = NSLock()
    private var storage: [ModelRequest] = []

    init(response: String) { self.response = response }

    var requests: [ModelRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func stream(request: ModelRequest) -> AsyncThrowingStream<ModelEvent, Error> {
        lock.lock()
        storage.append(request)
        lock.unlock()
        return FakeModelClient(events: [
            .started,
            .textDelta(response),
            .completed(ModelResponse(content: response))
        ]).stream(request: request)
    }
}

private func request() throws -> ReaderHelpRequest {
    ReaderHelpRequest(
        bookID: BookID(),
        anchor: try helpLocator(selected: "a page"),
        selectedText: "a page",
        question: "这里的 a page 是什么意思？"
    )
}

private func helpLocator(selected: String) throws -> BookLocator {
    let json = try JSONSerialization.data(withJSONObject: [
        "href": "chapter.xhtml",
        "locations": ["progression": 0.42]
    ])
    return try BookLocator(
        json: json,
        href: "chapter.xhtml",
        progression: 0.42,
        textBefore: "A reader begins with ",
        textHighlight: selected,
        textAfter: ", returns with a thought."
    )
}

private func collect(_ stream: AsyncStream<ReaderHelpEvent>) async -> [ReaderHelpEvent] {
    var events: [ReaderHelpEvent] = []
    for await event in stream { events.append(event) }
    return events
}

import AgentRuntime
import Foundation
import LibraryCore
import ModelProviders
import ReaderAgent
import ReflectionCore
import Testing

/// URLProtocol-backed network stubbing: no test ever touches the real network.
/// Handlers are registered per exact request URL — every test registers a
/// unique URL, so parallel test functions stay isolated and no cross-test
/// reset is needed. Unregistered URLs fail loudly instead of escaping the stub.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (statusCode: Int, headers: [String: String], body: Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]

    static func register(url: URL, handler: @escaping Handler) {
        lock.lock()
        defer { lock.unlock() }
        handlers[url.absoluteString] = handler
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeAll()
    }

    static func makeTransport() -> URLSessionDataTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSessionDataTransport(session: URLSession(configuration: configuration))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handlers[request.url?.absoluteString ?? ""]
        Self.lock.unlock()
        do {
            guard let handler else {
                // Never let a mis-routed stubbed request reach the real network.
                throw URLError(.unsupportedURL)
            }
            let result = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: result.statusCode,
                httpVersion: nil, headerFields: result.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Thread-safe request capture: assertions run in the test task, never inside
/// the URLProtocol loading thread.
final class CapturedRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?

    func store(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        self.request = request
    }

    func value() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }
}

extension URLRequest {
    /// POST bodies arrive in URLProtocol as a stream, not `httpBody`.
    var stubBody: Data {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

@Suite
struct AnthropicModelClientTests {
    private static let happyBody = #"{"id":"msg_1","type":"message","role":"assistant","content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn"}"#

    // MARK: Request mapping

    @Test func nativeMessagesRequestCarriesAnthropicHeadersSystemAndTurnMapping() async throws {
        let baseURL = URL(string: "https://happy.anthropic-stub.test/v1")!
        let captured = CapturedRequest()
        StubURLProtocol.register(url: baseURL.appendingPathComponent("messages")) { request in
            captured.store(request)
            return (200, [:], Data(Self.happyBody.utf8))
        }
        let client = try makeClient(baseURL: baseURL)
        for try await _ in client.stream(request: .init(
            messages: [
                .init(role: .system, content: "第一个系统约束"),
                .init(role: .system, content: "第二个系统约束"),
                .init(role: .user, content: "书里这句话让我停下来"),
            ],
            temperature: 0.4,
            maxOutputTokens: 120
        )) {}

        let request = try #require(captured.value())
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://happy.anthropic-stub.test/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let json = try #require(try JSONSerialization.jsonObject(with: request.stubBody) as? [String: Any])
        #expect(json["model"] as? String == "claude-sonnet-4")
        #expect(json["max_tokens"] as? Int == 120)
        #expect(json["temperature"] as? Double == 0.4)
        #expect(json["system"] as? String == "第一个系统约束\n\n第二个系统约束")
        // Non-streaming is the Messages API default; the request must not carry
        // any streaming notion (PRD §21.3).
        #expect(json["stream"] == nil)
        #expect(json["response_format"] == nil)
        #expect(json["messages"] as? [[String: String]] == [["role": "user", "content": "书里这句话让我停下来"]])
    }

    @Test func maxTokensFallsBackWhenCallerOmitsBudget() async throws {
        let json = try await capturedBodyJSON(
            baseURL: URL(string: "https://budget.anthropic-stub.test/v1")!,
            maxOutputTokens: nil
        )
        #expect(json["max_tokens"] as? Int == 1_024)
    }

    @Test func consecutiveSameRoleTurnsMergeAndTrailingAssistantNeverBecomesPrefill() async throws {
        let json = try await capturedBodyJSON(
            baseURL: URL(string: "https://merge.anthropic-stub.test/v1")!,
            messages: [
                .init(role: .user, content: "最初的想法"),
                .init(role: .user, content: "追加了想说的话"),
                .init(role: .assistant, content: "上一轮的回应"),
            ]
        )
        #expect(json["messages"] as? [[String: String]] == [
            ["role": "user", "content": "最初的想法\n\n追加了想说的话"],
            ["role": "assistant", "content": "上一轮的回应"],
            ["role": "user", "content": "请给出你的回应。"],
        ])
    }

    @Test func alternatingTurnsPassThroughUnchanged() async throws {
        let json = try await capturedBodyJSON(
            baseURL: URL(string: "https://alternating.anthropic-stub.test/v1")!,
            messages: [
                .init(role: .user, content: "最初的想法"),
                .init(role: .assistant, content: "回应"),
                .init(role: .user, content: "继续讨论"),
            ]
        )
        #expect(json["messages"] as? [[String: String]] == [
            ["role": "user", "content": "最初的想法"],
            ["role": "assistant", "content": "回应"],
            ["role": "user", "content": "继续讨论"],
        ])
    }

    // MARK: Response semantics

    @Test func stopReasonMaxTokensBecomesLengthForExecutorTruncation() async throws {
        let completed = try await completedResponse(
            body: #"{"id":"msg_m","content":[{"type":"text","text":"ok"}],"stop_reason":"max_tokens"}"#
        )
        #expect(completed.finishReason == "length")
    }

    @Test func multiTextBlocksJoinAndEmptyContentStaysEmptyWithoutThrowing() async throws {
        let joined = try await completedResponse(
            body: #"{"id":"msg_2","content":[{"type":"text","text":"第一段"},{"type":"text","text":"第二段"}],"stop_reason":"end_turn"}"#,
            baseURL: URL(string: "https://blocks.anthropic-stub.test/v1")!
        )
        #expect(joined.content == "第一段\n\n第二段")

        let empty = try await completedResponse(
            body: #"{"id":"msg_3","content":[],"stop_reason":null}"#,
            baseURL: URL(string: "https://empty.anthropic-stub.test/v1")!
        )
        #expect(empty.content == "")
        #expect(empty.finishReason == nil)
    }

    // MARK: Error taxonomy (mirrors OpenAICompatibleModelClient)

    @Test func errorEnvelopeMapsToSharedFailureTaxonomy() async throws {
        func failure(_ name: String, statusCode: Int, body: String) async throws -> ModelFailure {
            let baseURL = URL(string: "https://\(name).anthropic-stub.test/v1")!
            StubURLProtocol.register(url: baseURL.appendingPathComponent("messages")) { _ in
                (statusCode, [:], Data(body.utf8))
            }
            let client = try makeClient(baseURL: baseURL)
            do {
                for try await _ in client.stream(request: .init(messages: [.init(role: .user, content: "hi")])) {}
                Issue.record("Expected provider failure for \(name)")
                return .invalidResponse
            } catch let failure as ModelFailure {
                return failure
            }
        }

        #expect(try await failure(
            "unauthorized", statusCode: 401,
            body: #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        ) == .authentication)
        #expect(try await failure(
            "limited", statusCode: 429,
            body: #"{"type":"error","error":{"type":"rate_limit_error","message":"Number of requests too high"}}"#
        ) == .rateLimited)
        // Parity with the OpenAI client: a decodable error envelope surfaces the
        // provider's own message (AgentExecutor normalizes it to providerUnavailable).
        #expect(try await failure(
            "overloaded", statusCode: 503,
            body: #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        ) == .providerMessage("Overloaded"))
        #expect(try await failure("gateway", statusCode: 503, body: "gateway timeout") == .providerUnavailable)
    }

    @Test func malformedJSONSurfacesAsInvalidResponseAndTimeoutAsNetwork() async throws {
        let malformedURL = URL(string: "https://malformed.anthropic-stub.test/v1")!
        StubURLProtocol.register(url: malformedURL.appendingPathComponent("messages")) { _ in
            (200, [:], Data("<html>not json</html>".utf8))
        }
        let malformedClient = try makeClient(baseURL: malformedURL)
        do {
            for try await _ in malformedClient.stream(request: .init(messages: [.init(role: .user, content: "hi")])) {}
            Issue.record("Expected malformed provider response to fail")
        } catch let failure as ModelFailure {
            #expect(failure == .invalidResponse)
        }

        let timeoutURL = URL(string: "https://timeout.anthropic-stub.test/v1")!
        StubURLProtocol.register(url: timeoutURL.appendingPathComponent("messages")) { _ in
            throw URLError(.timedOut)
        }
        let timeoutClient = try makeClient(baseURL: timeoutURL)
        do {
            for try await _ in timeoutClient.stream(request: .init(messages: [.init(role: .user, content: "hi")])) {}
            Issue.record("Expected timeout to surface as network failure")
        } catch let failure as ModelFailure {
            #expect(failure == .network)
        }
    }

    // MARK: Configuration guards

    @Test func rejectsNonAnthropicOrIncompleteConfiguration() {
        #expect(throws: ModelFailure.invalidConfiguration.self) {
            _ = try AnthropicModelClient(
                configuration: ProviderConfiguration(
                    provider: .openAICompatible, baseURL: URL(string: "https://api.deepseek.com/v1")!,
                    modelID: "deepseek-chat", secretReference: .init(rawValue: "ref")
                ),
                apiKey: "k"
            )
        }
        #expect(throws: ModelFailure.invalidConfiguration.self) {
            _ = try AnthropicModelClient(
                configuration: ProviderConfiguration(
                    provider: .anthropic, baseURL: ModelProviderPreset.anthropic.baseURL!,
                    modelID: "", secretReference: .init(rawValue: "ref")
                ),
                apiKey: "k"
            )
        }
        #expect(throws: ModelFailure.invalidConfiguration.self) {
            _ = try AnthropicModelClient(
                configuration: ProviderConfiguration(
                    provider: .anthropic, baseURL: ModelProviderPreset.anthropic.baseURL!,
                    modelID: "claude-sonnet-4", secretReference: .init(rawValue: "ref")
                ),
                apiKey: ""
            )
        }
    }

    @Test func descriptorDeclaresNonStreamingWithoutStructuredOutput() throws {
        let client = try makeClient(baseURL: ModelProviderPreset.anthropic.baseURL!)
        #expect(client.descriptor.provider == "anthropic")
        #expect(client.descriptor.capabilities.supportsStreaming == false)
        #expect(client.descriptor.capabilities.supportsStructuredOutput == false)
    }

    // MARK: Shared runtime semantics (provider-agnostic error path, PROV-03)

    @Test func agentExecutorNormalizesAnthropicRateLimit() async throws {
        let baseURL = URL(string: "https://executor.anthropic-stub.test/v1")!
        StubURLProtocol.register(url: baseURL.appendingPathComponent("messages")) { _ in
            (429, [:], Data(#"{"type":"error","error":{"type":"rate_limit_error","message":"busy"}}"#.utf8))
        }
        let client = try makeClient(baseURL: baseURL)
        var events: [AgentEvent] = []
        for await event in AgentExecutor(client: client, budget: .init(maxOutputTokens: 64)).run(input: .init(
            metadata: .init(agentKind: "reader.reflection", promptVersion: "v", contextRecipeVersion: "v"),
            messages: [.init(role: .user, content: "hi")]
        )) { events.append(event) }
        #expect(events.last == .failed(.rateLimited))
    }

    @Test func agentFailureNeverLosesThePersistedUserMessage() async throws {
        let baseURL = URL(string: "https://agent-auth.anthropic-stub.test/v1")!
        StubURLProtocol.register(url: baseURL.appendingPathComponent("messages")) { _ in
            (401, [:], Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8))
        }
        let reflection = Reflection(bookID: .init(), originalText: "无效 Key 也不该弄丢这句话", inputKind: .text)
        let repository = ReflectionRepositoryFake(reflection: reflection)
        let agent = ReaderAgent(
            reflections: repository,
            models: StaticModelFactory(client: try makeClient(baseURL: baseURL))
        )
        let events = await collect(agent.continueDiscussion(on: reflection.id, messageID: UUID(), text: "继续想"))

        #expect(events.last == .failed(.runtime(.authentication)))
        let saved = await repository.savedMessages()
        #expect(saved.count == 1)
        #expect(saved.first?.author == .user)
        #expect(await repository.persistedReflection()?.originalText == "无效 Key 也不该弄丢这句话")
    }

    // MARK: Helpers

    private func makeClient(baseURL: URL) throws -> AnthropicModelClient {
        try AnthropicModelClient(
            configuration: ProviderConfiguration(
                provider: .anthropic, baseURL: baseURL,
                modelID: "claude-sonnet-4", secretReference: .init(rawValue: "ref")
            ),
            apiKey: "sk-ant-test",
            transport: StubURLProtocol.makeTransport()
        )
    }

    private func capturedBodyJSON(
        baseURL: URL, messages: [ModelMessage] = [.init(role: .user, content: "hi")],
        maxOutputTokens: Int? = nil
    ) async throws -> [String: Any] {
        let captured = CapturedRequest()
        StubURLProtocol.register(url: baseURL.appendingPathComponent("messages")) { request in
            captured.store(request)
            return (200, [:], Data(Self.happyBody.utf8))
        }
        let client = try makeClient(baseURL: baseURL)
        for try await _ in client.stream(request: .init(messages: messages, maxOutputTokens: maxOutputTokens)) {}
        let request = try #require(captured.value())
        return try #require(try JSONSerialization.jsonObject(with: request.stubBody) as? [String: Any])
    }

    private func completedResponse(body: String, baseURL: URL = URL(string: "https://map.anthropic-stub.test/v1")!) async throws -> ModelResponse {
        StubURLProtocol.register(url: baseURL.appendingPathComponent("messages")) { _ in
            (200, [:], Data(body.utf8))
        }
        let client = try makeClient(baseURL: baseURL)
        var completed: ModelResponse?
        for try await event in client.stream(request: .init(messages: [.init(role: .user, content: "hi")])) {
            if case .completed(let response) = event { completed = response }
        }
        return try #require(completed)
    }
}

private func collect(_ stream: AsyncStream<ReaderAgentEvent>) async -> [ReaderAgentEvent] {
    var events: [ReaderAgentEvent] = []
    for await event in stream { events.append(event) }
    return events
}

private struct StaticModelFactory: ModelClientFactory {
    let client: any ModelClient
    func makeClient() -> any ModelClient { client }
}

private actor ReflectionRepositoryFake: ReflectionRepository {
    private let stored: Reflection?
    private var messages: [ReflectionMessage] = []

    init(reflection: Reflection?) { stored = reflection }
    func reflection(id: ReflectionID) -> Reflection? { stored?.id == id ? stored : nil }
    func reflections(for bookID: BookID) -> [Reflection] { stored?.bookID == bookID ? [stored!]: [] }
    func insert(_ reflection: Reflection, linkedHighlightIDs: [UUID], evidence: [ReflectionEvidence]) throws {}
    func linkedHighlightIDs(for reflectionID: ReflectionID) -> [UUID] { [] }
    func messages(for reflectionID: ReflectionID) -> [ReflectionMessage] { messages }
    func appendMessage(_ message: ReflectionMessage) { messages.append(message) }
    func appendAgentMessage(_ message: ReflectionMessage, evidence: [AgentResponseEvidence], citations: [AgentCitation]) {
        messages.append(message)
    }
    func provenance(for messageID: UUID) -> AgentResponseProvenance { .init(evidence: [], citations: []) }
    func message(id: UUID) -> ReflectionMessage? { messages.first { $0.id == id } }
    func recentReflections(limit: Int) -> [Reflection] { stored.map { [$0] } ?? [] }
    func connections(for reflectionID: ReflectionID) -> [ReflectionConnection] { [] }
    func saveConnection(_ connection: ReflectionConnection) {}
    func evidence(for reflectionID: ReflectionID) -> [ReflectionEvidence] { [] }
    func appendEvidence(_ evidence: ReflectionEvidence) throws {}
    func delete(id: ReflectionID) throws {}
    func savedMessages() -> [ReflectionMessage] { messages }
    func persistedReflection() -> Reflection? { stored }
}

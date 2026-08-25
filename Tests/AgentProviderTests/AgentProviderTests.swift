import AgentRuntime
import Foundation
import LibraryCore
import ModelProviders
import ReaderAgent
import ReflectionCore
import Testing

@Test func fakeModelClientIsDeterministicWithoutNetworkOrSecrets() async throws {
    let response = ModelResponse(content: "A small prompt back.")
    let client = FakeModelClient(events: [.started, .textDelta(response.content), .completed(response)])
    var events: [ModelEvent] = []
    for try await event in client.stream(request: ModelRequest(messages: [])) { events.append(event) }
    #expect(events == [.started, .textDelta("A small prompt back."), .completed(response)])
}

@Test func inMemorySecretStoreKeepsSecretOutsideProviderConfiguration() async throws {
    let reference = SecretReference(rawValue: "provider-openai-primary")
    let store = InMemorySecretStore()
    await store.save("test-secret", for: reference)
    #expect(await store.secret(for: reference) == "test-secret")

    let configuration = ProviderConfiguration(
        provider: .openAICompatible, baseURL: URL(string: "https://api.example.test/v1")!,
        modelID: "small-model", secretReference: reference
    )
    let encoded = try JSONEncoder().encode(configuration)
    #expect(!String(decoding: encoded, as: UTF8.self).contains("test-secret"))

    await store.removeSecret(for: reference)
    #expect(await store.secret(for: reference) == nil)
}

@Test func mainstreamProviderPresetsUseKnownOpenAICompatibleBaseURLs() {
    #expect(ModelProviderPreset.openAI.baseURL?.absoluteString == "https://api.openai.com/v1")
    #expect(ModelProviderPreset.deepSeek.baseURL?.absoluteString == "https://api.deepseek.com/v1")
    #expect(ModelProviderPreset.anthropic.baseURL?.absoluteString == "https://api.anthropic.com/v1")
    #expect(ModelProviderPreset.gemini.baseURL?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/openai")
    #expect(ModelProviderPreset.openRouter.baseURL?.absoluteString == "https://openrouter.ai/api/v1")
    #expect(ModelProviderPreset.groq.baseURL?.absoluteString == "https://api.groq.com/openai/v1")
    #expect(ModelProviderPreset.siliconFlow.baseURL?.absoluteString == "https://api.siliconflow.cn/v1")
    #expect(ModelProviderPreset.alibabaBailian.baseURL?.absoluteString == "https://dashscope.aliyuncs.com/compatible-mode/v1")
    #expect(ModelProviderPreset.custom.baseURL == nil)
    #expect(ModelProviderPreset.deepSeek.providerKind == .openAICompatible)
}

@Test func providerPresetCanBeRecoveredFromPersistedBaseURL() {
    #expect(ModelProviderPreset.matching(baseURL: ModelProviderPreset.deepSeek.baseURL!) == .deepSeek)
    #expect(ModelProviderPreset.matching(baseURL: URL(string: "https://api.deepseek.com/v1/")!) == .deepSeek)
    #expect(ModelProviderPreset.matching(baseURL: URL(string: "https://private.example/v1")!) == .custom)
}

@Test func compatibleClientMapsRequestAndResponseWithoutExposingKey() async throws {
    let transport = RecordedTransport(data: Data("""
    {"id":"chatcmpl-1","choices":[{"message":{"content":"A concise response."},"finish_reason":"stop"}],"usage":{"prompt_tokens":12,"completion_tokens":4,"total_tokens":16}}
    """.utf8))
    let configuration = ProviderConfiguration(
        provider: .openAICompatible, baseURL: URL(string: "https://provider.example/v1")!,
        modelID: "model-a", secretReference: SecretReference(rawValue: "provider-key")
    )
    let client = try OpenAICompatibleModelClient(configuration: configuration, apiKey: "secret-for-test", transport: transport)
    let request = ModelRequest(messages: [ModelMessage(role: .user, content: "What stayed with me?")], temperature: 0.3, maxOutputTokens: 120)

    var events: [ModelEvent] = []
    for try await event in client.stream(request: request) { events.append(event) }

    #expect(events == [
        .started,
        .textDelta("A concise response."),
        .completed(ModelResponse(id: "chatcmpl-1", content: "A concise response.", finishReason: "stop", usage: TokenUsage(inputTokens: 12, outputTokens: 4, totalTokens: 16))),
    ])
    let captured = await transport.captured()
    #expect(captured.url?.absoluteString == "https://provider.example/v1/chat/completions")
    #expect(captured.authorization == "Bearer secret-for-test")
    #expect(captured.body.contains("\"model\":\"model-a\""))
    #expect(captured.body.contains("\"stream\":false"))
}

@Test func compatibleClientTranslatesProviderErrors() async throws {
    let transport = RecordedTransport(
        statusCode: 401,
        data: Data("{\"error\":{\"message\":\"Invalid API key\"}}".utf8)
    )
    let configuration = ProviderConfiguration(
        provider: .openAI, baseURL: URL(string: "https://api.openai.com/v1")!,
        modelID: "gpt-test", secretReference: SecretReference(rawValue: "key")
    )
    let client = try OpenAICompatibleModelClient(configuration: configuration, apiKey: "test", transport: transport)

    do {
        for try await _ in client.stream(request: ModelRequest(messages: [])) {}
        Issue.record("Expected provider failure")
    } catch let error as ModelFailure {
        #expect(error == .authentication)
    }
}

@Test func compatibleClientNormalizesRateLimitServerAndNetworkFailures() async throws {
    let configuration = ProviderConfiguration(
        provider: .openAICompatible,
        baseURL: URL(string: "https://provider.example/v1")!,
        modelID: "model-a",
        secretReference: SecretReference(rawValue: "key")
    )
    for (status, expected) in [(429, ModelFailure.rateLimited), (503, .providerUnavailable)] {
        let client = try OpenAICompatibleModelClient(
            configuration: configuration,
            apiKey: "test",
            transport: RecordedTransport(statusCode: status, data: Data())
        )
        do {
            for try await _ in client.stream(request: ModelRequest(messages: [])) {}
            Issue.record("Expected normalized provider failure")
        } catch let failure as ModelFailure {
            #expect(failure == expected)
        } catch {
            Issue.record("Unexpected failure type: \(error)")
        }
    }

    let networkClient = try OpenAICompatibleModelClient(
        configuration: configuration,
        apiKey: "test",
        transport: FailingTransport()
    )
    do {
        for try await _ in networkClient.stream(request: ModelRequest(messages: [])) {}
        Issue.record("Expected normalized network failure")
    } catch let failure as ModelFailure {
        #expect(failure == .network)
    }
}

@Test func agentReplyLoadsPersistedReflectionBeforeCallingModelAndStoresDerivedMessage() async throws {
    let reflection = Reflection(
        bookID: .init(), originalText: "我开始怀疑效率是否总是一件好事。", inputKind: .text
    )
    let repository = ReflectionRepositoryFake(reflection: reflection)
    let response = ModelResponse(content: "效率服务于什么，或许比效率本身更值得追问。")
    let agent = ReaderAgent(
        reflections: repository,
        models: StaticModelFactory(client: FakeModelClient(events: [.started, .completed(response)]))
    )

    let events = await collect(agent.respond(to: reflection.id))
    guard case .completed(let message) = events.last else {
        Issue.record("Expected persisted ReaderAgent completion"); return
    }

    #expect(message.reflectionID == reflection.id)
    #expect(message.author == .agent)
    #expect(message.source == .agentGenerated)
    #expect(await repository.savedMessages() == [message])
}

@Test func readerAgentPolicyKeepsPromptAndContextRecipeVersioned() {
    let reflection = Reflection(bookID: .init(), originalText: "这是我的原始想法", inputKind: .text)
    let input = ReaderAgentPolicy(promptVersion: "reader-test-v2").input(for: reflection)

    #expect(input.metadata.agentKind == "reader.reflection")
    #expect(input.metadata.promptVersion == "reader-test-v2")
    #expect(input.metadata.contextRecipeVersion == "reflection-history-lexical-v1")
    #expect(input.messages.last?.role == .user)
    #expect(input.messages.last?.content == reflection.originalText)
}

@Test func failedAgentReplyDoesNotMutatePersistedReflectionOrAppendMessage() async throws {
    let reflection = Reflection(bookID: .init(), originalText: "原始想法", inputKind: .text)
    let repository = ReflectionRepositoryFake(reflection: reflection)
    let agent = ReaderAgent(
        reflections: repository,
        models: StaticModelFactory(client: FakeModelClient(events: [.completed(ModelResponse(content: "  "))]))
    )

    let events = await collect(agent.respond(to: reflection.id))
    #expect(events.last == .failed(.emptyResponse))
    #expect(await repository.savedMessages().isEmpty)
    #expect(await repository.persistedReflection()?.originalText == "原始想法")
}

private struct StaticModelFactory: ModelClientFactory {
    let client: any ModelClient
    func makeClient() -> any ModelClient { client }
}

private func collect(_ stream: AsyncStream<ReaderAgentEvent>) async -> [ReaderAgentEvent] {
    var events: [ReaderAgentEvent] = []
    for await event in stream { events.append(event) }
    return events
}

private actor RecordedTransport: HTTPDataTransport {
    struct Captured: Sendable {
        let url: URL?
        let authorization: String?
        let body: String
    }

    private let statusCode: Int
    private let responseData: Data
    private var latest: Captured?

    init(statusCode: Int = 200, data: Data) {
        self.statusCode = statusCode
        responseData = data
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        latest = Captured(
            url: request.url, authorization: request.value(forHTTPHeaderField: "Authorization"),
            body: String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        )
        return (responseData, HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!)
    }

    func captured() -> Captured { latest! }
}

private struct FailingTransport: HTTPDataTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        throw URLError(.notConnectedToInternet)
    }
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

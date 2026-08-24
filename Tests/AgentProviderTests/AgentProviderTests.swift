import AgentCore
import Foundation
import ModelProviders
import ReflectionCore
import Testing

@Test func agentDiscussionOnlyReferencesAlreadyPersistedReflection() {
    let reflectionID = ReflectionID()
    let request = AgentDiscussionRequest(reflectionID: reflectionID, prompt: "Help me examine this thought.")
    let response = AgentDiscussionResponse(requestID: request.id, content: "What makes that tension important to you?")

    #expect(request.reflectionID == reflectionID)
    #expect(response.requestID == request.id)
    #expect(!response.content.isEmpty)
}

@Test func fakeModelClientIsDeterministicWithoutNetworkOrSecrets() async throws {
    let response = ModelResponse(content: "A small prompt back.")
    let client = FakeModelClient(script: [.started, .textDelta(response.content), .completed(response)])
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
        .completed(ModelResponse(id: "chatcmpl-1", content: "A concise response.", finishReason: "stop", usage: ModelUsage(inputTokens: 12, outputTokens: 4, totalTokens: 16))),
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
    } catch let error as ModelClientError {
        #expect(error == .providerMessage("Invalid API key"))
    }
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

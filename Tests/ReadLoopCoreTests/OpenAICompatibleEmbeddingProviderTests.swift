import AgentRuntime
import Foundation
import ModelProviders
import RetrievalCore
import Testing

@Test func embeddingProviderBuildsCorrectRequestAndDecodesVectors() async throws {
    let configuration = makeConfiguration(embeddingModel: "text-embedding-3-small")
    let transport = StubTransport { request in
        #expect(request.url?.absoluteString == "https://api.example.com/v1/embeddings")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["model"] as? String == "text-embedding-3-small")
        #expect(json?["input"] as? [String] == ["第一段", "第二段"])
        return try okResponse(EmbeddingResponseBody(data: [
            EmbeddingDatum(index: 0, embedding: [0.1, 0.2, 0.3]),
            EmbeddingDatum(index: 1, embedding: [0.4, 0.5, 0.6]),
        ]))
    }
    let provider = try OpenAICompatibleEmbeddingProvider(configuration: configuration, apiKey: "secret", transport: transport)
    let vectors = try await provider.embed(["第一段", "第二段"])

    #expect(vectors.count == 2)
    #expect(vectors[0] == [0.1, 0.2, 0.3])
    #expect(vectors[1] == [0.4, 0.5, 0.6])
    #expect(provider.dimensions == 3)
    #expect(provider.modelIdentifier == "text-embedding-3-small")
}

@Test func embeddingProviderMapsHTTPErrors() async throws {
    let configuration = makeConfiguration(embeddingModel: "m")
    let cases: [(Int, ModelFailure)] = [
        (401, .authentication), (403, .authentication), (429, .rateLimited),
        (422, .providerMessage("boom")), (500, .providerMessage("boom")),
    ]
    for (code, expected) in cases {
        let transport = StubTransport { _ in errorResponse(code) }
        let provider = try OpenAICompatibleEmbeddingProvider(configuration: configuration, apiKey: "k", transport: transport)
        do {
            _ = try await provider.embed(["x"])
            Issue.record("expected failure for HTTP \(code)")
        } catch {
            #expect(matches(error, expected), "for HTTP \(code)")
        }
    }

    // A 5xx whose body is NOT a parseable OpenAI error envelope → providerUnavailable.
    let plainTransport = StubTransport { _ in
        (Data("<html>oops</html>".utf8), HTTPURLResponse(
            url: URL(string: "https://api.example.com")!, statusCode: 500,
            httpVersion: nil, headerFields: nil
        )!)
    }
    let provider = try OpenAICompatibleEmbeddingProvider(configuration: configuration, apiKey: "k", transport: plainTransport)
    do {
        _ = try await provider.embed(["x"])
        Issue.record("expected failure for plain 500")
    } catch {
        #expect(matches(error, .providerUnavailable))
    }
}

@Test func embeddingProviderRequiresConfiguredModel() throws {
    let configuration = makeConfiguration(embeddingModel: nil)
    #expect(throws: ModelFailure.invalidConfiguration.self) {
        try OpenAICompatibleEmbeddingProvider(configuration: configuration, apiKey: "k")
    }
}

@Test func embeddingProviderTruncatesOversizedInput() async throws {
    let configuration = makeConfiguration(embeddingModel: "m")
    let transport = StubTransport { request in
        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let input = json?["input"] as? [String]
        #expect(input?.count == 1)
        #expect(input?[0].count == 6_000)
        return try okResponse(EmbeddingResponseBody(data: [EmbeddingDatum(index: 0, embedding: [1])]))
    }
    let provider = try OpenAICompatibleEmbeddingProvider(configuration: configuration, apiKey: "k", transport: transport)
    let vectors = try await provider.embed([String(repeating: "字", count: 10_000)])
    #expect(vectors.count == 1)
}

@Test func providerEmbeddingTesterPassesOnNonEmptyVectors() async throws {
    let configuration = makeConfiguration(embeddingModel: "m")
    let transport = StubTransport { _ in
        try okResponse(EmbeddingResponseBody(data: [EmbeddingDatum(index: 0, embedding: [1, 2])]))
    }
    try await ProviderEmbeddingTester(transport: transport).test(configuration: configuration, apiKey: "k")
}

// MARK: - Helpers

private func makeConfiguration(embeddingModel: String?) -> ProviderConfiguration {
    ProviderConfiguration(
        provider: .openAICompatible,
        baseURL: URL(string: "https://api.example.com/v1")!,
        modelID: "chat-model",
        secretReference: .init(rawValue: "ref"),
        embeddingModelID: embeddingModel
    )
}

private struct StubTransport: HTTPDataTransport {
    let onRequest: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try onRequest(request)
    }
}

private func okResponse(_ body: Encodable) throws -> (Data, HTTPURLResponse) {
    let data = try JSONEncoder().encode(body)
    let response = HTTPURLResponse(
        url: URL(string: "https://api.example.com")!, statusCode: 200,
        httpVersion: nil, headerFields: nil
    )!
    return (data, response)
}

private func errorResponse(_ code: Int) -> (Data, HTTPURLResponse) {
    let data = Data(#"{"error":{"message":"boom"}}"#.utf8)
    let response = HTTPURLResponse(
        url: URL(string: "https://api.example.com")!, statusCode: code,
        httpVersion: nil, headerFields: nil
    )!
    return (data, response)
}

private struct EmbeddingResponseBody: Encodable {
    let data: [EmbeddingDatum]
}

private struct EmbeddingDatum: Encodable {
    let index: Int
    let embedding: [Float]
}

private func matches(_ error: Error, _ expected: ModelFailure) -> Bool {
    guard let failure = error as? ModelFailure else { return false }
    switch (failure, expected) {
    case (.authentication, .authentication), (.rateLimited, .rateLimited),
         (.providerUnavailable, .providerUnavailable), (.invalidResponse, .invalidResponse),
         (.invalidConfiguration, .invalidConfiguration), (.network, .network):
        return true
    case let (.providerMessage(a), .providerMessage(b)):
        return a == b
    default:
        return false
    }
}

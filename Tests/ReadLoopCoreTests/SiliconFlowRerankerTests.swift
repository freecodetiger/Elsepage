import AgentRuntime
import Foundation
import ModelProviders
import RetrievalCore
import Testing

@Test func rerankerBuildsCorrectRequestAndDecodesScores() async throws {
    let configuration = makeConfiguration(reranker: "BAAI/bge-reranker-v2-m3")
    let transport = StubTransport { request in
        #expect(request.url?.absoluteString == "https://api.siliconflow.cn/v1/rerank")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]
        #expect(body?["model"] as? String == "BAAI/bge-reranker-v2-m3")
        #expect(body?["query"] as? String == "自由是什么")
        #expect(body?["documents"] as? [String] == ["第一段", "第二段"])
        #expect(body?["top_n"] as? Int == 2)
        return okResponse(Data(#"{"results":[{"index":1,"relevance_score":0.9},{"index":0,"relevance_score":0.3}]}"#.utf8))
    }
    let reranker = try SiliconFlowReranker(configuration: configuration, apiKey: "secret", transport: transport)
    let results = try await reranker.rerank(query: "自由是什么", candidates: [
        RerankCandidate(id: "a", text: "第一段"),
        RerankCandidate(id: "b", text: "第二段"),
    ], limit: 2)

    #expect(results.map(\.id) == ["b", "a"]) // sorted by score, descending
    #expect(results[0].score == 0.9)
    #expect(results[1].score == 0.3)
}

@Test func rerankerOmitsTopNWhenLimitNil() async throws {
    let configuration = makeConfiguration(reranker: "m")
    let transport = StubTransport { request in
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]
        #expect(body?["top_n"] == nil)
        return okResponse(Data(#"{"results":[{"index":0,"relevance_score":0.5}]}"#.utf8))
    }
    let reranker = try SiliconFlowReranker(configuration: configuration, apiKey: "k", transport: transport)
    let results = try await reranker.rerank(query: "q", candidates: [RerankCandidate(id: "a", text: "t")], limit: nil)
    #expect(results.map(\.id) == ["a"])
}

@Test func rerankerMapsHTTPErrors() async throws {
    let configuration = makeConfiguration(reranker: "m")
    let cases: [(Int, ModelFailure)] = [(401, .authentication), (429, .rateLimited), (500, .providerMessage("boom"))]
    for (code, expected) in cases {
        let transport = StubTransport { _ in errorResponse(code) }
        let reranker = try SiliconFlowReranker(configuration: configuration, apiKey: "k", transport: transport)
        do {
            _ = try await reranker.rerank(query: "q", candidates: [RerankCandidate(id: "a", text: "t")], limit: 1)
            Issue.record("expected failure for HTTP \(code)")
        } catch {
            #expect(matches(error, expected), "for HTTP \(code)")
        }
    }
    // non-JSON 5xx -> providerUnavailable
    let plain = StubTransport { _ in (Data("oops".utf8), HTTPURLResponse(url: URL(string: "https://x.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!) }
    let reranker = try SiliconFlowReranker(configuration: configuration, apiKey: "k", transport: plain)
    do { _ = try await reranker.rerank(query: "q", candidates: [RerankCandidate(id: "a", text: "t")], limit: 1); Issue.record("expected fail") }
    catch { #expect(matches(error, .providerUnavailable)) }
}

@Test func rerankerRequiresConfiguredModel() throws {
    #expect(throws: ModelFailure.invalidConfiguration.self) {
        try SiliconFlowReranker(configuration: makeConfiguration(reranker: nil), apiKey: "k")
    }
}

// MARK: - Helpers

private func makeConfiguration(reranker: String?) -> ProviderConfiguration {
    ProviderConfiguration(
        provider: .openAICompatible,
        baseURL: URL(string: "https://api.siliconflow.cn/v1")!,
        modelID: "chat-model",
        secretReference: .init(rawValue: "ref"),
        streamingEnabled: false,
        embeddingModelID: nil,
        rerankerModelID: reranker
    )
}

private struct StubTransport: HTTPDataTransport {
    let onRequest: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try onRequest(request)
    }
}

private func okResponse(_ data: Data) -> (Data, HTTPURLResponse) {
    let response = HTTPURLResponse(url: URL(string: "https://x.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    return (data, response)
}

private func errorResponse(_ code: Int) -> (Data, HTTPURLResponse) {
    let data = Data(#"{"error":{"message":"boom"}}"#.utf8)
    let response = HTTPURLResponse(url: URL(string: "https://x.com")!, statusCode: code, httpVersion: nil, headerFields: nil)!
    return (data, response)
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

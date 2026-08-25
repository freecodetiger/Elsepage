import AgentRuntime
import Foundation
import RetrievalCore

/// Jina-compatible cross-encoder rerank adapter. SiliconFlow exposes this at
/// `{baseURL}/rerank` (e.g. api.siliconflow.cn/v1/rerank) with models such as
/// `BAAI/bge-reranker-v2-m3`. Uses the same transport + error mapping as the
/// other provider clients; a missing/empty `rerankerModelID` is invalid config.
public final class SiliconFlowReranker: Reranker, @unchecked Sendable {
    public let modelIdentifier: String

    private let baseURL: URL
    private let apiKey: String
    private let transport: any HTTPDataTransport

    public init(
        configuration: ProviderConfiguration,
        apiKey: String,
        transport: any HTTPDataTransport = URLSessionDataTransport()
    ) throws {
        guard configuration.provider == .openAI || configuration.provider == .openAICompatible,
              let model = configuration.rerankerModelID, !model.isEmpty,
              !apiKey.isEmpty,
              configuration.baseURL.scheme == "https" || configuration.baseURL.scheme == "http" else {
            throw ModelFailure.invalidConfiguration
        }
        self.modelIdentifier = model
        self.baseURL = configuration.baseURL
        self.apiKey = apiKey
        self.transport = transport
    }

    public func rerank(query: String, candidates: [RerankCandidate], limit: Int?) async throws -> [RerankedPassage] {
        guard !candidates.isEmpty else { return [] }
        let endpoint = baseURL.appendingPathComponent("rerank")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // Defensive truncation; rerank docs are usually short passages.
        let body = RerankRequestBody(
            model: modelIdentifier,
            query: query,
            documents: candidates.map { String($0.text.prefix(4_000)) },
            topN: limit
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do { (data, response) = try await transport.data(for: urlRequest) }
        catch is CancellationError { throw CancellationError() }
        catch { throw ModelFailure.network }
        guard let http = response as? HTTPURLResponse else { throw ModelFailure.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let providerError = try? JSONDecoder().decode(RerankErrorEnvelope.self, from: data) {
                if http.statusCode == 401 || http.statusCode == 403 { throw ModelFailure.authentication }
                if http.statusCode == 429 { throw ModelFailure.rateLimited }
                throw ModelFailure.providerMessage(providerError.error.message)
            }
            if http.statusCode == 401 || http.statusCode == 403 { throw ModelFailure.authentication }
            if http.statusCode == 429 { throw ModelFailure.rateLimited }
            if http.statusCode >= 500 { throw ModelFailure.providerUnavailable }
            throw ModelFailure.providerMessage("HTTP \(http.statusCode)")
        }
        let decoded: RerankResponse
        do { decoded = try JSONDecoder().decode(RerankResponse.self, from: data) }
        catch { throw ModelFailure.invalidResponse }
        return decoded.results
            .filter { $0.index >= 0 && $0.index < candidates.count }
            .map { RerankedPassage(id: candidates[$0.index].id, score: $0.relevanceScore) }
            .sorted { $0.score > $1.score }
    }
}

public struct ProviderRerankerTester: Sendable {
    private let transport: any HTTPDataTransport

    public init(transport: any HTTPDataTransport = URLSessionDataTransport()) {
        self.transport = transport
    }

    public func test(configuration: ProviderConfiguration, apiKey: String) async throws {
        let reranker = try SiliconFlowReranker(configuration: configuration, apiKey: apiKey, transport: transport)
        let results = try await reranker.rerank(query: "test", candidates: [
            RerankCandidate(id: "a", text: "第一段"),
            RerankCandidate(id: "b", text: "第二段"),
        ], limit: 1)
        guard !results.isEmpty else { throw ModelFailure.invalidResponse }
    }
}

private struct RerankRequestBody: Encodable {
    let model: String
    let query: String
    let documents: [String]
    let topN: Int?

    enum CodingKeys: String, CodingKey {
        case model, query, documents, topN = "top_n"
    }
}

private struct RerankResponse: Decodable {
    let results: [Result]

    struct Result: Decodable {
        let index: Int
        let relevanceScore: Double

        enum CodingKeys: String, CodingKey {
            case index, relevanceScore = "relevance_score"
        }
    }
}

private struct RerankErrorEnvelope: Decodable {
    struct ProviderError: Decodable { let message: String }
    let error: ProviderError
}

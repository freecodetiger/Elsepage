import AgentRuntime
import Foundation
import RetrievalCore

/// OpenAI-compatible `/embeddings` adapter implementing `RetrievalCore.EmbeddingProvider`.
/// Reuses the same `HTTPDataTransport`, Bearer-key pattern, and error mapping as
/// `OpenAICompatibleModelClient`. `dimensions` is discovered from the first
/// response and cached (thread-safe), so any embedding model name works without
/// a hard-coded dimension table.
public final class OpenAICompatibleEmbeddingProvider: EmbeddingProvider, @unchecked Sendable {
    public let modelIdentifier: String

    private let baseURL: URL
    private let apiKey: String
    private let transport: any HTTPDataTransport
    private let lock = NSLock()
    private var cachedDimensions: Int?

    public init(
        configuration: ProviderConfiguration,
        apiKey: String,
        transport: any HTTPDataTransport = URLSessionDataTransport()
    ) throws {
        guard configuration.provider == .openAI || configuration.provider == .openAICompatible,
              let model = configuration.embeddingModelID, !model.isEmpty,
              !apiKey.isEmpty,
              configuration.baseURL.scheme == "https" || configuration.baseURL.scheme == "http" else {
            throw ModelFailure.invalidConfiguration
        }
        self.modelIdentifier = model
        self.baseURL = configuration.baseURL
        self.apiKey = apiKey
        self.transport = transport
    }

    public var dimensions: Int {
        lock.withLock { cachedDimensions ?? 0 }
    }

    public func embed(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        let endpoint = baseURL.appendingPathComponent("embeddings")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // Chunk texts are ~900 chars; truncate defensively so an oversized block
        // cannot blow a provider's per-input token limit.
        let payload = try JSONEncoder().encode(EmbeddingRequestBody(
            model: modelIdentifier,
            input: texts.map { String($0.prefix(6_000)) }
        ))
        urlRequest.httpBody = payload

        let data: Data
        let response: URLResponse
        do { (data, response) = try await transport.data(for: urlRequest) }
        catch is CancellationError { throw CancellationError() }
        catch { throw ModelFailure.network }
        guard let http = response as? HTTPURLResponse else { throw ModelFailure.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let providerError = try? JSONDecoder().decode(EmbeddingErrorEnvelope.self, from: data) {
                if http.statusCode == 401 || http.statusCode == 403 { throw ModelFailure.authentication }
                if http.statusCode == 429 { throw ModelFailure.rateLimited }
                throw ModelFailure.providerMessage(providerError.error.message)
            }
            if http.statusCode == 401 || http.statusCode == 403 { throw ModelFailure.authentication }
            if http.statusCode == 429 { throw ModelFailure.rateLimited }
            if http.statusCode >= 500 { throw ModelFailure.providerUnavailable }
            throw ModelFailure.providerMessage("HTTP \(http.statusCode)")
        }
        let decoded: EmbeddingResponse
        do { decoded = try JSONDecoder().decode(EmbeddingResponse.self, from: data) }
        catch { throw ModelFailure.invalidResponse }
        let vectors = decoded.data.sorted { $0.index < $1.index }.map(\.embedding)
        guard !vectors.isEmpty, let dimension = vectors.first?.count, dimension > 0 else {
            throw ModelFailure.invalidResponse
        }
        lock.withLock { if cachedDimensions == nil { cachedDimensions = dimension } }
        return vectors
    }
}

public struct ProviderEmbeddingTester: Sendable {
    private let transport: any HTTPDataTransport

    public init(transport: any HTTPDataTransport = URLSessionDataTransport()) {
        self.transport = transport
    }

    public func test(configuration: ProviderConfiguration, apiKey: String) async throws {
        let provider = try OpenAICompatibleEmbeddingProvider(configuration: configuration, apiKey: apiKey, transport: transport)
        let vectors = try await provider.embed(["test"])
        guard vectors.first?.isEmpty == false else { throw ModelFailure.invalidResponse }
    }
}

private struct EmbeddingRequestBody: Encodable {
    let model: String
    let input: [String]
}

private struct EmbeddingResponse: Decodable {
    let data: [Embedding]

    struct Embedding: Decodable {
        let index: Int
        let embedding: [Float]
    }
}

private struct EmbeddingErrorEnvelope: Decodable {
    struct ProviderError: Decodable { let message: String }
    let error: ProviderError
}

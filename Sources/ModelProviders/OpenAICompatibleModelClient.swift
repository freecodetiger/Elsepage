import AgentRuntime
import Foundation

public protocol HTTPDataTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionDataTransport: HTTPDataTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

/// Minimal OpenAI Chat Completions-compatible adapter. It intentionally sends a
/// non-streaming HTTP request for now, while presenting the stable `ModelClient`
/// event contract required by the future local runtime.
public struct OpenAICompatibleModelClient: ModelClient {
    public let descriptor: ModelDescriptor

    private let configuration: ProviderConfiguration
    private let apiKey: String
    private let transport: any HTTPDataTransport

    public init(
        configuration: ProviderConfiguration, apiKey: String,
        transport: any HTTPDataTransport = URLSessionDataTransport()
    ) throws {
        guard configuration.provider == .openAI || configuration.provider == .openAICompatible,
              !configuration.modelID.isEmpty,
              !apiKey.isEmpty,
              configuration.baseURL.scheme == "https" || configuration.baseURL.scheme == "http" else {
            throw ModelFailure.invalidConfiguration
        }
        self.configuration = configuration
        self.apiKey = apiKey
        self.transport = transport
        descriptor = ModelDescriptor(
            provider: configuration.provider.rawValue,
            model: configuration.modelID,
            capabilities: ModelCapabilities(supportsStreaming: false)
        )
    }

    public func stream(request: ModelRequest) -> AsyncThrowingStream<ModelEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.started)
                    let response = try await complete(request: request)
                    continuation.yield(.textDelta(response.content))
                    continuation.yield(.completed(response))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func complete(request: ModelRequest) async throws -> ModelResponse {
        let endpoint = configuration.baseURL.appendingPathComponent("chat/completions")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(OpenAIRequest(configuration: configuration, request: request))

        let data: Data
        let response: URLResponse
        do { (data, response) = try await transport.data(for: urlRequest) }
        catch is CancellationError { throw CancellationError() }
        catch { throw ModelFailure.network }
        guard let http = response as? HTTPURLResponse else { throw ModelFailure.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let providerError = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data) {
                if http.statusCode == 401 || http.statusCode == 403 { throw ModelFailure.authentication }
                if http.statusCode == 429 { throw ModelFailure.rateLimited }
                throw ModelFailure.providerMessage(providerError.error.message)
            }
            if http.statusCode == 401 || http.statusCode == 403 { throw ModelFailure.authentication }
            if http.statusCode == 429 { throw ModelFailure.rateLimited }
            if http.statusCode >= 500 { throw ModelFailure.providerUnavailable }
            throw ModelFailure.providerMessage("HTTP \(http.statusCode)")
        }
        let decoded: OpenAIResponse
        do { decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data) }
        catch { throw ModelFailure.invalidResponse }
        guard let choice = decoded.choices.first else { throw ModelFailure.invalidResponse }
        return ModelResponse(
            id: decoded.id, content: choice.message.content ?? "", finishReason: choice.finishReason,
            usage: decoded.usage.map { TokenUsage(inputTokens: $0.promptTokens, outputTokens: $0.completionTokens, totalTokens: $0.totalTokens) }
        )
    }
}

private struct OpenAIRequest: Encodable {
    let model: String
    let messages: [OpenAIMessage]
    let temperature: Double?
    let maxTokens: Int?
    let stream: Bool
    let thinking: Thinking?

    init(configuration: ProviderConfiguration, request: ModelRequest) {
        model = configuration.modelID
        messages = request.messages.map(OpenAIMessage.init)
        temperature = request.temperature
        maxTokens = request.maxOutputTokens
        stream = false
        thinking = configuration.baseURL.host?.lowercased() == "api.deepseek.com"
            ? Thinking(type: "disabled")
            : nil
    }

    struct Thinking: Encodable { let type: String }

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, maxTokens = "max_tokens", stream, thinking
    }
}

private struct OpenAIMessage: Codable {
    let role: String
    let content: String
    init(_ message: ModelMessage) { role = message.role.rawValue; content = message.content }
}

private struct OpenAIResponse: Decodable {
    let id: String?
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
        let message: Message
        let finishReason: String?
        enum CodingKeys: String, CodingKey { case message, finishReason = "finish_reason" }
    }
    struct Message: Decodable { let content: String? }
    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

private struct OpenAIErrorEnvelope: Decodable {
    struct ProviderError: Decodable { let message: String }
    let error: ProviderError
}

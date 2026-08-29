import AgentRuntime
import Foundation

/// Native Anthropic Messages API adapter (`POST {baseURL}/v1/messages`).
///
/// Anthropic's endpoint is not OpenAI-compatible (different auth header, a
/// top-level `system` parameter, strictly alternating user/assistant turns and
/// a required `max_tokens`), so it gets its own client instead of riding the
/// `OpenAICompatibleModelClient`. Wire contract:
/// - Headers: `x-api-key` + `anthropic-version: 2023-06-01` + JSON content type.
/// - Body: `model`, `max_tokens` (required by the API), optional `temperature`,
///   optional top-level `system`, and `messages` (user/assistant only).
/// - No `stream` field: non-streaming is the Messages API default and requests
///   must stay non-streaming (PRD §21.3) — do not reintroduce the key.
///
/// Event and error semantics mirror `OpenAICompatibleModelClient` exactly so
/// `AgentExecutor` and the UI error taxonomy stay provider-agnostic.
public struct AnthropicModelClient: ModelClient {
    public let descriptor: ModelDescriptor

    private let configuration: ProviderConfiguration
    private let apiKey: String
    private let transport: any HTTPDataTransport

    /// anthropic-version header value for the non-streaming Messages API.
    static let apiVersion = "2023-06-01"

    public init(
        configuration: ProviderConfiguration, apiKey: String,
        transport: any HTTPDataTransport = URLSessionDataTransport()
    ) throws {
        guard configuration.provider == .anthropic || ModelClientRouting.isNativeAnthropic(configuration.baseURL),
              !configuration.modelID.isEmpty,
              !apiKey.isEmpty,
              configuration.baseURL.scheme == "https" || configuration.baseURL.scheme == "http" else {
            throw ModelFailure.invalidConfiguration
        }
        self.configuration = configuration
        self.apiKey = apiKey
        self.transport = transport
        descriptor = ModelDescriptor(
            provider: ModelProviderKind.anthropic.rawValue,
            model: configuration.modelID,
            // The Messages API has no response_format json_object equivalent;
            // the context router degrades to prompt-only JSON instructions.
            capabilities: ModelCapabilities(supportsStreaming: false, supportsStructuredOutput: false)
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
        let endpoint = configuration.baseURL.appendingPathComponent("messages")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONEncoder().encode(AnthropicRequest(configuration: configuration, request: request))

        let data: Data
        let response: URLResponse
        do { (data, response) = try await transport.data(for: urlRequest) }
        catch is CancellationError { throw CancellationError() }
        catch { throw ModelFailure.network }
        guard let http = response as? HTTPURLResponse else { throw ModelFailure.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let providerError = try? JSONDecoder().decode(AnthropicErrorEnvelope.self, from: data) {
                if http.statusCode == 401 || http.statusCode == 403 { throw ModelFailure.authentication }
                if http.statusCode == 429 { throw ModelFailure.rateLimited }
                throw ModelFailure.providerMessage(providerError.error.message)
            }
            if http.statusCode == 401 || http.statusCode == 403 { throw ModelFailure.authentication }
            if http.statusCode == 429 { throw ModelFailure.rateLimited }
            if http.statusCode >= 500 { throw ModelFailure.providerUnavailable }
            throw ModelFailure.providerMessage("HTTP \(http.statusCode)")
        }
        let decoded: AnthropicResponse
        do { decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data) }
        catch { throw ModelFailure.invalidResponse }
        let content = decoded.content.filter { $0.type == "text" }.compactMap(\.text).joined(separator: "\n\n")
        return ModelResponse(
            id: decoded.id, content: content, finishReason: Self.finishReason(from: decoded.stopReason),
            usage: decoded.usage.map { TokenUsage(inputTokens: $0.inputTokens, outputTokens: $0.outputTokens, totalTokens: Self.totalTokens($0)) }
        )
    }

    /// Maps Anthropic `stop_reason` onto the OpenAI finish-reason vocabulary the
    /// runtime already understands — `max_tokens` must become "length" so
    /// `AgentExecutor` still emits its truncation event for cut-off replies.
    private static func finishReason(from stopReason: String?) -> String? {
        switch stopReason {
        case "max_tokens": "length"
        case "end_turn", "stop_sequence": "stop"
        case "tool_use": "tool_calls"
        case nil: nil
        case let other: other
        }
    }

    private static func totalTokens(_ usage: AnthropicResponse.Usage) -> Int? {
        guard let input = usage.inputTokens, let output = usage.outputTokens else { return nil }
        return input + output
    }
}

/// The Messages API request. `stream` is intentionally absent — non-streaming
/// is the endpoint default and PRD §21.3 removed the streaming notion entirely.
private struct AnthropicRequest: Encodable {
    let model: String
    let maxTokens: Int
    let temperature: Double?
    let system: String?
    let messages: [AnthropicMessage]

    init(configuration: ProviderConfiguration, request: ModelRequest) {
        model = configuration.modelID
        // max_tokens is required by the Messages API; callers normally set it
        // via ExecutionBudget, 1024 is the fallback runaway guard.
        maxTokens = request.maxOutputTokens ?? 1_024
        temperature = request.temperature
        // System prompts become the top-level `system` parameter (joined in
        // order); ReaderAgentPolicy interleaves several of them by design.
        let systemParts = request.messages.filter { $0.role == .system }.map(\.content)
        system = systemParts.isEmpty ? nil : systemParts.joined(separator: "\n\n")
        messages = AnthropicMessage.alternating(request.messages.filter { $0.role != .system })
    }

    enum CodingKeys: String, CodingKey {
        case model, temperature, system, messages
        case maxTokens = "max_tokens"
    }
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: String

    /// The Messages API requires strictly alternating user/assistant turns,
    /// while `ModelRequest` may carry consecutive same-role messages (the
    /// reflection flow always emits the original reflection followed by the
    /// discussion history, both user-authored). Same-role neighbors are merged
    /// with a blank line — no information is dropped.
    ///
    /// A trailing assistant turn means "continue this text" (prefill) on
    /// Anthropic but only "context so far" on OpenAI. To keep semantics
    /// identical across providers, a trailing assistant turn is followed by a
    /// neutral user cue so the model produces a fresh reply instead of
    /// extending the previous one.
    static func alternating(_ messages: [ModelMessage]) -> [AnthropicMessage] {
        var merged: [AnthropicMessage] = []
        for message in messages where !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let role = message.role == .assistant ? "assistant" : "user"
            if let last = merged.last, last.role == role {
                merged[merged.count - 1] = AnthropicMessage(role: role, content: last.content + "\n\n" + message.content)
            } else {
                merged.append(AnthropicMessage(role: role, content: message.content))
            }
        }
        if let last = merged.last, last.role == "assistant" {
            merged.append(AnthropicMessage(role: "user", content: "请给出你的回应。"))
        }
        return merged
    }
}

private struct AnthropicResponse: Decodable {
    let id: String?
    let content: [ContentBlock]
    let stopReason: String?
    let usage: Usage?

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, content, usage
        case stopReason = "stop_reason"
    }
}

private struct AnthropicErrorEnvelope: Decodable {
    struct ProviderError: Decodable { let message: String }
    let error: ProviderError
}

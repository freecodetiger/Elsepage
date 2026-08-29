import AgentRuntime
import Foundation
import ModelProviders

/// Model identity recorded in the run report. Never carries the API key.
public struct BenchModelInfo: Codable, Sendable, Equatable {
    public let provider: String
    public let model: String
    public let baseURL: String
}

public enum BenchError: Error, LocalizedError, Sendable {
    /// Raised when DEEPSEEK_API_KEY is missing/empty. The message must never
    /// echo environment values.
    case missingAPIKey
    case invalidBaseURL

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "缺少 DEEPSEEK_API_KEY 环境变量。请先执行: set -a; source ~/.readloop-bench-env; set +a (或使用 --dry-run 做无网络冒烟)"
        case .invalidBaseURL:
            "DEEPSEEK_BASE_URL 不是合法的 http(s) URL (密钥本身不会被输出)"
        }
    }
}

/// Builds the model client for a bench run. Reads configuration from the
/// environment only:
///
///   DEEPSEEK_API_KEY   (required for real runs; never logged, never persisted)
///   DEEPSEEK_BASE_URL  (default: https://api.deepseek.com/v1 — the app preset)
///   DEEPSEEK_MODEL     (default: deepseek-chat)
///
/// Real runs go through `OpenAICompatibleModelClient` — the exact client the app
/// uses — so wire format, headers and DeepSeek-specific fields are identical.
/// Dry runs use `FakeModelClient` (no network, deterministic).
public enum BenchModelClientFactory {
    public static let defaultBaseURL = "https://api.deepseek.com/v1"
    public static let defaultModel = "deepseek-chat"

    public static func make(
        dryRun: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> (client: any ModelClient, info: BenchModelInfo) {
        if dryRun {
            let client = FakeModelClient(events: [
                .started,
                .textDelta(BenchPipeline.dryRunReply),
                .completed(ModelResponse(id: "dry-run", content: BenchPipeline.dryRunReply, finishReason: "stop")),
            ])
            return (client, BenchModelInfo(provider: "fake", model: "scripted-dry-run", baseURL: "local://dry-run"))
        }

        let key = environment["DEEPSEEK_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else { throw BenchError.missingAPIKey }
        let baseURLString = environment["DEEPSEEK_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let model = environment["DEEPSEEK_MODEL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURLString, !baseURLString.isEmpty, let baseURL = URL(string: baseURLString),
              baseURL.scheme == "https" || baseURL.scheme == "http" else {
            throw BenchError.invalidBaseURL
        }
        let configuration = ProviderConfiguration(
            provider: .openAICompatible,
            baseURL: baseURL,
            modelID: (model?.isEmpty == false ? model! : defaultModel),
            secretReference: SecretReference(rawValue: "bench-env-deepseek")
        )
        let client = try OpenAICompatibleModelClient(configuration: configuration, apiKey: key)
        return (
            client,
            BenchModelInfo(provider: configuration.provider.rawValue, model: configuration.modelID, baseURL: baseURL.absoluteString)
        )
    }
}

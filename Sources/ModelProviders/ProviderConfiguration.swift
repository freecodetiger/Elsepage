import Foundation

public enum ModelProviderKind: String, Codable, Sendable, CaseIterable {
    case openAI
    case anthropic
    case gemini
    case openAICompatible
}

/// Curated endpoints which implement the OpenAI Chat Completions protocol.
public enum ModelProviderPreset: String, CaseIterable, Identifiable, Sendable {
    case openAI
    case deepSeek
    case anthropic
    case gemini
    case openRouter
    case groq
    case mistral
    case xAI
    case siliconFlow
    case moonshot
    case alibabaBailian
    case zhipu
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .deepSeek: "DeepSeek"
        case .anthropic: "Anthropic Claude"
        case .gemini: "Google Gemini"
        case .openRouter: "OpenRouter"
        case .groq: "Groq"
        case .mistral: "Mistral AI"
        case .xAI: "xAI"
        case .siliconFlow: "硅基流动 SiliconFlow"
        case .moonshot: "Moonshot / Kimi"
        case .alibabaBailian: "阿里云百炼"
        case .zhipu: "智谱 GLM"
        case .custom: "自定义 OpenAI-compatible"
        }
    }

    /// The persisted provider kind. Note: the `.anthropic` preset also
    /// persists as `.openAICompatible` because the `providerConfigurations`
    /// schema CHECK constraint only admits 'openAI'/'openAICompatible'; the
    /// native Messages API is selected at client-construction time from the
    /// canonical preset base URL (see `ModelClientRouting`).
    public var providerKind: ModelProviderKind {
        self == .openAI ? .openAI : .openAICompatible
    }

    public var baseURL: URL? {
        let value: String
        switch self {
        case .openAI: value = "https://api.openai.com/v1"
        case .deepSeek: value = "https://api.deepseek.com/v1"
        case .anthropic: value = "https://api.anthropic.com/v1"
        case .gemini: value = "https://generativelanguage.googleapis.com/v1beta/openai"
        case .openRouter: value = "https://openrouter.ai/api/v1"
        case .groq: value = "https://api.groq.com/openai/v1"
        case .mistral: value = "https://api.mistral.ai/v1"
        case .xAI: value = "https://api.x.ai/v1"
        case .siliconFlow: value = "https://api.siliconflow.cn/v1"
        case .moonshot: value = "https://api.moonshot.cn/v1"
        case .alibabaBailian: value = "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .zhipu: value = "https://open.bigmodel.cn/api/paas/v4"
        case .custom: return nil
        }
        return URL(string: value)!
    }

    public static func matching(baseURL: URL) -> ModelProviderPreset {
        let candidate = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return allCases.first {
            $0.baseURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == candidate
        } ?? .custom
    }
}

/// Opaque non-secret reference to a key held by `SecretStore`.
public struct SecretReference: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

/// This is safe to persist in SQLite. The API key itself is intentionally absent.
/// Note: the former `streamingEnabled` debug flag is gone (PRD §21.3) — requests
/// are always non-streaming, so there is nothing to configure.
public struct ProviderConfiguration: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let provider: ModelProviderKind
    public let baseURL: URL
    public let modelID: String
    public let secretReference: SecretReference
    /// Separate embedding model for the semantic retrieval layer. Nil means the
    /// RAG stays lexical-only. Non-nil enables the `/embeddings` path.
    public let embeddingModelID: String?
    /// Optional dedicated endpoint + key for the embedding role. When nil, the
    /// chat provider's `baseURL`/`secretReference` are used (shared-key setups).
    public let embeddingBaseURL: URL?
    public let embeddingSecretReference: SecretReference?
    /// Separate cross-encoder rerank model (the RAG precision gate). Nil means
    /// candidates are used as-fused; non-nil re-scores them via `/rerank`.
    public let rerankerModelID: String?
    /// Optional dedicated endpoint + key for the reranker role. Same fallback
    /// semantics as the embedding role.
    public let rerankerBaseURL: URL?
    public let rerankerSecretReference: SecretReference?

    /// Effective endpoint/key for each RAG role — the role-specific value when
    /// configured, else the chat provider's (preserves legacy shared-key setups).
    public var effectiveEmbeddingBaseURL: URL { embeddingBaseURL ?? baseURL }
    public var effectiveEmbeddingSecretReference: SecretReference { embeddingSecretReference ?? secretReference }
    public var effectiveRerankerBaseURL: URL { rerankerBaseURL ?? baseURL }
    public var effectiveRerankerSecretReference: SecretReference { rerankerSecretReference ?? secretReference }

    public init(
        id: UUID = UUID(), provider: ModelProviderKind, baseURL: URL,
        modelID: String, secretReference: SecretReference,
        embeddingModelID: String? = nil,
        embeddingBaseURL: URL? = nil, embeddingSecretReference: SecretReference? = nil,
        rerankerModelID: String? = nil,
        rerankerBaseURL: URL? = nil, rerankerSecretReference: SecretReference? = nil
    ) {
        self.id = id
        self.provider = provider
        self.baseURL = baseURL
        self.modelID = modelID
        self.secretReference = secretReference
        self.embeddingModelID = embeddingModelID
        self.embeddingBaseURL = embeddingBaseURL
        self.embeddingSecretReference = embeddingSecretReference
        self.rerankerModelID = rerankerModelID
        self.rerankerBaseURL = rerankerBaseURL
        self.rerankerSecretReference = rerankerSecretReference
    }
}

public protocol ProviderConfigurationRepository: Sendable {
    func currentConfiguration() async throws -> ProviderConfiguration?
    func save(_ configuration: ProviderConfiguration) async throws
    func deleteCurrentConfiguration() async throws
}

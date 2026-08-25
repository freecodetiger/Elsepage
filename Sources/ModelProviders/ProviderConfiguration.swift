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
public struct ProviderConfiguration: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let provider: ModelProviderKind
    public let baseURL: URL
    public let modelID: String
    public let secretReference: SecretReference
    public let streamingEnabled: Bool

    public init(
        id: UUID = UUID(), provider: ModelProviderKind, baseURL: URL,
        modelID: String, secretReference: SecretReference,
        streamingEnabled: Bool = true
    ) {
        self.id = id
        self.provider = provider
        self.baseURL = baseURL
        self.modelID = modelID
        self.secretReference = secretReference
        self.streamingEnabled = streamingEnabled
    }
}

public protocol ProviderConfigurationRepository: Sendable {
    func currentConfiguration() async throws -> ProviderConfiguration?
    func save(_ configuration: ProviderConfiguration) async throws
    func deleteCurrentConfiguration() async throws
}

import Foundation

public enum ModelProviderKind: String, Codable, Sendable, CaseIterable {
    case openAI
    case anthropic
    case gemini
    case openAICompatible
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

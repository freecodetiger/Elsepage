import Foundation

public struct ModelCapabilities: Hashable, Codable, Sendable {
    public var supportsStreaming: Bool
    public var supportsToolCalling: Bool
    public var supportsStructuredOutput: Bool
    public var supportsVision: Bool
    public var maxContextTokens: Int?

    public init(
        supportsStreaming: Bool = false, supportsToolCalling: Bool = false,
        supportsStructuredOutput: Bool = false, supportsVision: Bool = false,
        maxContextTokens: Int? = nil
    ) {
        self.supportsStreaming = supportsStreaming
        self.supportsToolCalling = supportsToolCalling
        self.supportsStructuredOutput = supportsStructuredOutput
        self.supportsVision = supportsVision
        self.maxContextTokens = maxContextTokens
    }
}

public enum ModelMessageRole: String, Codable, Sendable { case system, user, assistant }

public struct ModelMessage: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let role: ModelMessageRole
    public let content: String

    public init(id: UUID = UUID(), role: ModelMessageRole, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

public struct ModelRequest: Hashable, Codable, Sendable {
    public let messages: [ModelMessage]
    public let temperature: Double?
    public let maxOutputTokens: Int?

    public init(messages: [ModelMessage], temperature: Double? = nil, maxOutputTokens: Int? = nil) {
        self.messages = messages
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
    }
}

public struct ModelUsage: Hashable, Codable, Sendable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let totalTokens: Int?

    public init(inputTokens: Int? = nil, outputTokens: Int? = nil, totalTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }
}

public struct ModelResponse: Hashable, Codable, Sendable {
    public let id: String?
    public let content: String
    public let finishReason: String?
    public let usage: ModelUsage?

    public init(id: String? = nil, content: String, finishReason: String? = nil, usage: ModelUsage? = nil) {
        self.id = id
        self.content = content
        self.finishReason = finishReason
        self.usage = usage
    }
}

public enum ModelEvent: Hashable, Sendable {
    case started
    case textDelta(String)
    case completed(ModelResponse)
}

public protocol ModelClient: Sendable {
    var capabilities: ModelCapabilities { get }
    func stream(request: ModelRequest) -> AsyncThrowingStream<ModelEvent, Error>
}

public enum ModelClientError: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidResponse
    case httpStatus(Int)
    case providerMessage(String)
}

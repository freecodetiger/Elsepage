import Foundation

public struct AgentRunID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: UUID
    public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public struct ModelCallID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: UUID
    public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public struct AgentInput: Hashable, Codable, Sendable {
    public let metadata: AgentRunMetadata
    public let messages: [ModelMessage]
    public let temperature: Double?
    /// Optional provider-level structured-output request (e.g. json_object),
    /// carried through AgentExecutor into the wire request. Nil → no response_format.
    public let responseFormat: ModelResponseFormat?

    public init(
        metadata: AgentRunMetadata,
        messages: [ModelMessage],
        temperature: Double? = nil,
        responseFormat: ModelResponseFormat? = nil
    ) {
        self.metadata = metadata
        self.messages = messages
        self.temperature = temperature
        self.responseFormat = responseFormat
    }
}

public struct AgentRunMetadata: Hashable, Codable, Sendable {
    public let agentKind: String
    public let promptVersion: String
    public let contextRecipeVersion: String

    public init(agentKind: String, promptVersion: String, contextRecipeVersion: String) {
        self.agentKind = agentKind
        self.promptVersion = promptVersion
        self.contextRecipeVersion = contextRecipeVersion
    }
}

public struct AgentResult: Hashable, Codable, Sendable {
    public let runID: AgentRunID
    public let metadata: AgentRunMetadata
    public let response: ModelResponse

    public init(runID: AgentRunID, metadata: AgentRunMetadata, response: ModelResponse) {
        self.runID = runID
        self.metadata = metadata
        self.response = response
    }
}

public enum AgentFailure: Error, Equatable, Sendable {
    case authentication
    case rateLimited
    case providerUnavailable
    case network
    case malformedProviderResponse
    case budgetExceeded
    case unknown
}

public enum AgentEvent: Hashable, Sendable {
    case runStarted(AgentRunID)
    case modelStarted(ModelCallID)
    case textDelta(String)
    case usageUpdated(TokenUsage)
    /// The provider stopped generation at maxOutputTokens (finish_reason == "length").
    /// Always precedes `.completed`; consumers should surface the cut rather than
    /// persisting the truncated response as if it were complete.
    case truncated
    case completed(AgentResult)
    case cancelled
    case failed(AgentFailure)
}

public struct ExecutionBudget: Hashable, Sendable {
    public let maxModelCalls: Int
    public let maxWallTime: Duration
    public let maxOutputTokens: Int?

    public init(
        maxModelCalls: Int = 1,
        maxWallTime: Duration = .seconds(45),
        maxOutputTokens: Int? = 400
    ) {
        self.maxModelCalls = maxModelCalls
        self.maxWallTime = maxWallTime
        self.maxOutputTokens = maxOutputTokens
    }

    // 1000 output tokens ≈ 600–1000 Chinese chars: room for the full reply plus
    // the ---CITATIONS--- block. A runaway guard, not a shaping constraint —
    // shaping lives in ReaderAgentPolicy's targetLength guidance.
    public static let readerReply = ExecutionBudget(maxOutputTokens: 1_000)
}

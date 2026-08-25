import Foundation
import ModelProviders
import ReflectionCore

/// Produces optional derived feedback for an already-persisted Reflection.
public struct ReflectionAgentReplyService: Sendable {
    private let reflections: any ReflectionRepository
    private let client: any ModelClient

    public init(reflections: any ReflectionRepository, client: any ModelClient) {
        self.reflections = reflections
        self.client = client
    }

    @discardableResult
    public func reply(to reflectionID: ReflectionID) async throws -> ReflectionMessage {
        guard let reflection = try await reflections.reflection(id: reflectionID) else {
            throw ReflectionAgentReplyError.missingPersistedReflection
        }

        let request = ModelRequest(
            messages: [
                ModelMessage(
                    role: .system,
                    content: "你是一位克制、诚实的阅读思考伙伴。准确回应用户，最多补充一个相关连接，并最多提出一个值得继续思考的问题。不要替用户总结整本书。"
                ),
                ModelMessage(role: .user, content: reflection.originalText)
            ],
            temperature: 0.4,
            maxOutputTokens: 400
        )

        var response: ModelResponse?
        for try await event in client.stream(request: request) {
            if case .completed(let completed) = event { response = completed }
        }
        guard let content = response?.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw ReflectionAgentReplyError.emptyProviderResponse
        }

        let message = try ReflectionMessage(
            reflectionID: reflection.id,
            author: .agent,
            source: .agentGenerated,
            content: content
        )
        try await reflections.appendMessage(message)
        return message
    }
}

public enum ReflectionAgentReplyError: Error, Equatable, Sendable {
    case missingPersistedReflection
    case emptyProviderResponse
}

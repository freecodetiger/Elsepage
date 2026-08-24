import Foundation
import ReflectionCore

/// A request to discuss a reflection which has already been persisted locally.
/// It deliberately carries the reflection ID rather than user-authored content: a
/// model response can only ever be stored as separately authored derived data.
public struct AgentDiscussionRequest: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let reflectionID: ReflectionID
    public let prompt: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(), reflectionID: ReflectionID, prompt: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.reflectionID = reflectionID
        self.prompt = prompt
        self.createdAt = createdAt
    }
}

/// A derived response. This type is intentionally separate from `Reflection`
/// and `ReflectionMessage`, whose user-authored source data stays immutable.
public struct AgentDiscussionResponse: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let requestID: UUID
    public let content: String
    public let providerResponseID: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(), requestID: UUID, content: String,
        providerResponseID: String? = nil, createdAt: Date = Date()
    ) {
        self.id = id
        self.requestID = requestID
        self.content = content
        self.providerResponseID = providerResponseID
        self.createdAt = createdAt
    }
}

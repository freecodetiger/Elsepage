import Foundation

/// Immutable browsing summary generated once from the first Reflection and its
/// first Agent response. It is derived data and never overwrites user text.
public struct ReflectionSummary: Hashable, Codable, Sendable, Identifiable {
    public var id: ReflectionID { reflectionID }

    public let reflectionID: ReflectionID
    public let text: String
    public let sourceMessageID: UUID
    public let promptVersion: String
    public let createdAt: Date

    public init(
        reflectionID: ReflectionID,
        text: String,
        sourceMessageID: UUID,
        promptVersion: String,
        createdAt: Date = Date()
    ) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ReflectionSummaryValidationError.emptyText }
        guard trimmed.count <= ReflectionSummary.maximumCharacterCount else {
            throw ReflectionSummaryValidationError.tooLong
        }
        guard !promptVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReflectionSummaryValidationError.emptyPromptVersion
        }

        self.reflectionID = reflectionID
        self.text = trimmed
        self.sourceMessageID = sourceMessageID
        self.promptVersion = promptVersion
        self.createdAt = createdAt
    }

    public static let maximumCharacterCount = 36
}

public enum ReflectionSummaryValidationError: Error, Equatable, Sendable {
    case emptyText
    case tooLong
    case emptyPromptVersion
}

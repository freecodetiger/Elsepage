import Foundation
import LibraryCore
import ReaderCore
import ReadingSessionCore

/// A stable draft identity makes a retry after an interrupted save idempotent.
public struct TextReflectionDraft: Hashable, Sendable {
    public let id: ReflectionID
    public let bookID: BookID
    public let sessionID: ReadingSessionID?
    public let locator: BookLocator
    public let originalText: String
    public let createdAt: Date

    public init(
        id: ReflectionID = ReflectionID(),
        bookID: BookID,
        sessionID: ReadingSessionID?,
        locator: BookLocator,
        originalText: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookID = bookID
        self.sessionID = sessionID
        self.locator = locator
        self.originalText = originalText
        self.createdAt = createdAt
    }

    public var hasText: Bool {
        !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Saves raw user text and its reading context. It deliberately performs no model or derived-data work.
public struct TextReflectionSubmissionService: Sendable {
    private let repository: any ReflectionRepository

    public init(repository: any ReflectionRepository) {
        self.repository = repository
    }

    @discardableResult
    public func submit(_ draft: TextReflectionDraft) async throws -> Reflection {
        guard draft.hasText else { throw TextReflectionSubmissionError.emptyText }

        if let existing = try await repository.reflection(id: draft.id) {
            guard existing.bookID == draft.bookID,
                  existing.sessionID == draft.sessionID,
                  existing.originalText == draft.originalText,
                  existing.inputKind == .text else {
                throw TextReflectionSubmissionError.conflictingRetry
            }
            return existing
        }

        let reflection = Reflection(
            id: draft.id,
            bookID: draft.bookID,
            sessionID: draft.sessionID,
            originalText: draft.originalText,
            inputKind: .text,
            createdAt: draft.createdAt
        )
        var evidence = [try ReflectionEvidence(
            reflectionID: reflection.id,
            sourceType: .bookLocator,
            locator: draft.locator
        )]
        if let sessionID = draft.sessionID {
            evidence.append(try ReflectionEvidence(
                reflectionID: reflection.id,
                sourceType: .readingSession,
                sourceID: sessionID.description
            ))
        }
        try await repository.insert(reflection, linkedHighlightIDs: [], evidence: evidence)
        return reflection
    }
}

public enum TextReflectionSubmissionError: Error, Equatable, Sendable {
    case emptyText
    case conflictingRetry
}

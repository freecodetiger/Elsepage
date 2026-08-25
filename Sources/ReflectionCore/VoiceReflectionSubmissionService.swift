import Foundation
import LibraryCore
import ReaderCore
import ReadingSessionCore

public struct VoiceReflectionDraft: Hashable, Sendable {
    public let id: ReflectionID
    public let bookID: BookID
    public let sessionID: ReadingSessionID?
    public let locator: BookLocator
    public let editedTranscript: String
    /// Optional raw audio file name (relative to the Reflections directory). Nil when the
    /// user chose not to save audio (PRD "可选").
    public let audioFileName: String?
    public let linkedHighlightIDs: [UUID]
    public let createdAt: Date

    public init(
        id: ReflectionID = ReflectionID(), bookID: BookID, sessionID: ReadingSessionID?,
        locator: BookLocator, editedTranscript: String, audioFileName: String? = nil,
        linkedHighlightIDs: [UUID] = [], createdAt: Date = Date()
    ) {
        self.id = id
        self.bookID = bookID
        self.sessionID = sessionID
        self.locator = locator
        self.editedTranscript = editedTranscript
        self.audioFileName = audioFileName
        self.linkedHighlightIDs = linkedHighlightIDs
        self.createdAt = createdAt
    }
}

/// Persists the user-reviewed transcript as source data. Agent work is deliberately out of scope.
public struct VoiceReflectionSubmissionService: Sendable {
    private let repository: any ReflectionRepository

    public init(repository: any ReflectionRepository) { self.repository = repository }

    @discardableResult
    public func submit(_ draft: VoiceReflectionDraft) async throws -> Reflection {
        guard !draft.editedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceReflectionSubmissionError.emptyTranscript
        }
        if let existing = try await repository.reflection(id: draft.id) {
            guard existing.bookID == draft.bookID,
                  existing.sessionID == draft.sessionID,
                  existing.originalText == draft.editedTranscript,
                  existing.inputKind == .voiceTranscript,
                  existing.audioFileName == draft.audioFileName else {
                throw VoiceReflectionSubmissionError.conflictingRetry
            }
            return existing
        }

        let reflection = Reflection(
            id: draft.id, bookID: draft.bookID, sessionID: draft.sessionID,
            originalText: draft.editedTranscript, inputKind: .voiceTranscript,
            audioFileName: draft.audioFileName, createdAt: draft.createdAt
        )
        var evidence = [try ReflectionEvidence(reflectionID: reflection.id, sourceType: .bookLocator, locator: draft.locator)]
        if let sessionID = draft.sessionID {
            evidence.append(try ReflectionEvidence(reflectionID: reflection.id, sourceType: .readingSession, sourceID: sessionID.description))
        }
        try await repository.insert(reflection, linkedHighlightIDs: draft.linkedHighlightIDs, evidence: evidence)
        return reflection
    }
}

public enum VoiceReflectionSubmissionError: Error, Equatable, Sendable {
    case emptyTranscript
    case conflictingRetry
}

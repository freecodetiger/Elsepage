import Foundation
import LibraryCore
import ReaderCore

/// Serializes the lifecycle of the one active session for a book in this app process.
/// The persistent representation remains the source of truth across launches.
public actor ReadingSessionService {
    private let repository: any ReadingSessionRepository

    public init(repository: any ReadingSessionRepository) {
        self.repository = repository
    }

    /// Returns the existing unfinished session for this book, or records a new one.
    public func start(bookID: BookID, at locator: BookLocator, startedAt: Date = Date()) async throws -> ReadingSession {
        if let active = try await repository.sessions(for: bookID).first(where: { $0.endedAt == nil }) {
            return active
        }

        let session = ReadingSession(bookID: bookID, startedAt: startedAt, startLocator: locator)
        try await repository.insert(session)
        return session
    }

    /// Completes a session exactly once. A repeated end request returns the already-recorded result.
    public func end(
        id: ReadingSessionID,
        at locator: BookLocator,
        endedAt: Date = Date(),
        highlightCount: Int,
        noteCount: Int,
        agentDiscussionCount: Int = 0
    ) async throws -> ReadingSession {
        guard let existing = try await repository.session(id: id) else {
            throw ReadingSessionServiceError.missingSession
        }
        guard existing.endedAt == nil else { return existing }

        try await repository.complete(
            id: id,
            endedAt: max(endedAt, existing.startedAt),
            endLocator: locator,
            highlightCount: max(0, highlightCount),
            noteCount: max(0, noteCount),
            agentDiscussionCount: max(0, agentDiscussionCount)
        )
        guard let completed = try await repository.session(id: id) else {
            throw ReadingSessionServiceError.missingSession
        }
        return completed
    }
}

public enum ReadingSessionServiceError: Error, Equatable, Sendable {
    case missingSession
}

/// UI-ready facts derived from persisted session data. Duration is wall-clock time, not active-reading time.
public struct SessionEndingSummary: Hashable, Sendable {
    public let session: ReadingSession

    public init(session: ReadingSession) {
        self.session = session
    }

    public var wallClockDuration: TimeInterval {
        max(0, session.duration ?? 0)
    }

    public var progressDelta: Double? {
        guard let start = session.startLocator.totalProgression,
              let end = session.endLocator?.totalProgression else { return nil }
        return max(0, end - start)
    }

    public var shouldOfferReflection: Bool {
        MeaningfulReadingSessionPolicy().shouldOfferReflection(for: self)
    }
}

/// A deterministic product policy which prevents accidental or very short opens
/// from becoming Reflection prompts.
public struct MeaningfulReadingSessionPolicy: Sendable {
    public let minimumDuration: TimeInterval
    public let minimumProgressDelta: Double

    public init(minimumDuration: TimeInterval = 3 * 60, minimumProgressDelta: Double = 0.005) {
        self.minimumDuration = minimumDuration
        self.minimumProgressDelta = minimumProgressDelta
    }

    public func shouldOfferReflection(for summary: SessionEndingSummary) -> Bool {
        guard summary.session.endedAt != nil else { return false }
        return summary.wallClockDuration >= minimumDuration
            || (summary.progressDelta ?? 0) >= minimumProgressDelta
            || summary.session.highlightCount > 0
            || summary.session.noteCount > 0
    }
}

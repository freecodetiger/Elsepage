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
    /// `agentDiscussionCount` is normally left nil: the counter is persisted at the
    /// moment each user-initiated discussion starts (`recordAgentDiscussion`), so
    /// ending a session preserves it. An explicit value — legacy callers, tests —
    /// is combined by taking the larger of the persisted and provided numbers.
    public func end(
        id: ReadingSessionID,
        at locator: BookLocator,
        endedAt: Date = Date(),
        highlightCount: Int,
        noteCount: Int,
        agentDiscussionCount: Int? = nil
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
            agentDiscussionCount: max(existing.agentDiscussionCount, max(0, agentDiscussionCount ?? 0))
        )
        guard let completed = try await repository.session(id: id) else {
            throw ReadingSessionServiceError.missingSession
        }
        return completed
    }

    /// FIX-01 (PRD §21.5): records one user-initiated agent discussion — the
    /// Reflection submission that opens the Agent conversation, and each follow-up
    /// the user sends in it. The increment lands in the store immediately (and is
    /// additive), so app kills and later session ends never lose it. Sessions
    /// that already ended still accept the increment: a 补写 Reflection reopens
    /// that session's discussion thread, and the count stays a property of it.
    /// Returns the updated session, or nil when the session is unknown.
    public func recordAgentDiscussion(id: ReadingSessionID) async throws -> ReadingSession? {
        guard (try await repository.session(id: id)) != nil else { return nil }
        try await repository.incrementAgentDiscussionCount(id: id, by: 1)
        return try await repository.session(id: id)
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

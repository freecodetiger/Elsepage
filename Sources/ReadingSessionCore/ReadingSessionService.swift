import Foundation
import LibraryCore
import ReaderCore

/// Serializes the lifecycle of the one active session for a book in this app process.
/// The persistent representation remains the source of truth across launches.
public actor ReadingSessionService {
    private let repository: any ReadingSessionRepository
    /// How long an unfinished session stays resumable. Something left open
    /// days ago is a leftover (app killed, reader skipped out), not the same
    /// read, so it is closed instead of being continued.
    public let resumeWindow: TimeInterval

    public init(repository: any ReadingSessionRepository, resumeWindow: TimeInterval = 30 * 60) {
        self.repository = repository
        self.resumeWindow = resumeWindow
    }

    /// Returns the unfinished session for this book if the reader was in the
    /// reader recently enough to be the same sitting, or records a new one.
    public func start(bookID: BookID, at locator: BookLocator, startedAt now: Date = Date()) async throws -> ReadingSession {
        if let open = try await repository.sessions(for: bookID).first(where: { $0.endedAt == nil }) {
            if open.lastActiveAt >= now.addingTimeInterval(-resumeWindow) {
                // An open session seen here came from a previous process: it was
                // never paused because the app died or the reader was skipped
                // out. Nobody can tell how long that gap was, so none of it is
                // banked — the clock restarts now.
                try await repository.setActivity(
                    id: open.id,
                    activeDuration: open.activeDuration ?? 0,
                    activeSince: now
                )
                return try await repository.session(id: open.id) ?? open
            }
            // Close the leftover where it stopped, so its own duration stays
            // honest and it cannot carry its clock into the new session.
            _ = try? await end(
                id: open.id,
                at: open.endLocator ?? open.startLocator,
                endedAt: open.lastActiveAt,
                highlightCount: open.highlightCount,
                noteCount: open.noteCount
            )
        }

        let session = ReadingSession(bookID: bookID, startedAt: now, startLocator: locator, activeSince: now)
        try await repository.insert(session)
        return session
    }

    /// The reader left the screen: bank the open segment and stop the clock.
    @discardableResult
    public func pause(id: ReadingSessionID, at now: Date = Date()) async throws -> ReadingSession? {
        guard let session = try await repository.session(id: id),
              session.endedAt == nil,
              let open = session.activeSince else { return nil }
        let banked = (session.activeDuration ?? 0) + max(0, now.timeIntervalSince(open))
        try await repository.setActivity(id: id, activeDuration: banked, activeSince: nil)
        return try await repository.session(id: id)
    }

    /// The reader came back: count from now on. Background time is never
    /// banked, so it never lands in the session's duration.
    @discardableResult
    public func resume(id: ReadingSessionID, at now: Date = Date()) async throws -> ReadingSession? {
        guard let session = try await repository.session(id: id),
              session.endedAt == nil,
              session.activeSince == nil else { return nil }
        try await repository.setActivity(id: id, activeDuration: session.activeDuration ?? 0, activeSince: now)
        return try await repository.session(id: id)
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

/// UI-ready facts derived from persisted session data. Duration is reading
/// time — the time the reader was actually in the reader — not wall-clock time.
public struct SessionEndingSummary: Hashable, Sendable {
    public let session: ReadingSession

    public init(session: ReadingSession) {
        self.session = session
    }

    public var readingDuration: TimeInterval {
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
    /// Below this the session never prompts for a reflection, even if a page
    /// turned or a highlight was made. A two-minute look is not a reading
    /// session worth interrupting; the progress and highlight signals only
    /// qualify sessions that already cleared this floor.
    public let hardFloorDuration: TimeInterval
    public let minimumDuration: TimeInterval
    public let minimumProgressDelta: Double

    public init(
        hardFloorDuration: TimeInterval = 2 * 60,
        minimumDuration: TimeInterval = 3 * 60,
        minimumProgressDelta: Double = 0.005
    ) {
        self.hardFloorDuration = hardFloorDuration
        self.minimumDuration = minimumDuration
        self.minimumProgressDelta = minimumProgressDelta
    }

    public func shouldOfferReflection(for summary: SessionEndingSummary) -> Bool {
        guard summary.session.endedAt != nil else { return false }
        guard summary.readingDuration >= hardFloorDuration else { return false }
        return summary.readingDuration >= minimumDuration
            || (summary.progressDelta ?? 0) >= minimumProgressDelta
            || summary.session.highlightCount > 0
            || summary.session.noteCount > 0
    }
}

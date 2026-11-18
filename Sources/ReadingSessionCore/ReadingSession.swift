import Foundation
import LibraryCore
import ReaderCore

public struct ReadingSessionID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
    public init() { rawValue = UUID() }
    public var description: String { rawValue.uuidString.lowercased() }
}

public struct ReadingSession: Hashable, Codable, Sendable, Identifiable {
    public let id: ReadingSessionID
    public let bookID: BookID
    public let startedAt: Date
    public var endedAt: Date?
    public let startLocator: BookLocator
    public var endLocator: BookLocator?
    public var highlightCount: Int
    public var noteCount: Int
    public var agentDiscussionCount: Int
    /// Seconds the reader was actually in the reader, excluding background and
    /// between-launch gaps. `nil` on rows written before activity tracking;
    /// those fall back to the wall-clock span.
    public var activeDuration: TimeInterval?
    /// Start of the currently open active segment, `nil` while paused or ended.
    public var activeSince: Date?

    public init(
        id: ReadingSessionID = ReadingSessionID(), bookID: BookID,
        startedAt: Date = Date(), endedAt: Date? = nil,
        startLocator: BookLocator, endLocator: BookLocator? = nil,
        highlightCount: Int = 0, noteCount: Int = 0, agentDiscussionCount: Int = 0,
        activeDuration: TimeInterval? = nil, activeSince: Date? = nil
    ) {
        self.id = id
        self.bookID = bookID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.startLocator = startLocator
        self.endLocator = endLocator
        self.highlightCount = highlightCount
        self.noteCount = noteCount
        self.agentDiscussionCount = agentDiscussionCount
        self.activeDuration = activeDuration
        self.activeSince = activeSince
    }

    /// Reading time, not wall-clock time: a book left open while the phone sat
    /// in a pocket the whole night is a few minutes, not 624.
    public var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return activeDuration ?? endedAt.timeIntervalSince(startedAt)
    }

    /// The last moment the reader was known to be reading — the anchor the
    /// resume window is measured from. An open session whose value is stale is
    /// a leftover, not a session someone is still reading.
    public var lastActiveAt: Date {
        if let activeSince { return activeSince }
        guard let activeDuration else { return startedAt }
        return startedAt.addingTimeInterval(activeDuration)
    }
}

public protocol ReadingSessionRepository: Sendable {
    func session(id: ReadingSessionID) async throws -> ReadingSession?
    func sessions(for bookID: BookID) async throws -> [ReadingSession]
    /// Every reading session across all books, newest first. Derived indicators
    /// (streaks) consume this. Fakes inherit an empty default; the GRDB
    /// implementation loads the real table.
    func allSessions() async throws -> [ReadingSession]
    func insert(_ session: ReadingSession) async throws
    func complete(
        id: ReadingSessionID, endedAt: Date, endLocator: BookLocator,
        highlightCount: Int, noteCount: Int, agentDiscussionCount: Int
    ) async throws
    /// FIX-01 (PRD §21.5): persists an increment of the user-initiated agent
    /// discussion counter as soon as a discussion starts, so it survives crashes
    /// and can never be overwritten by a later session end.
    func incrementAgentDiscussionCount(id: ReadingSessionID, by count: Int) async throws
    /// Replaces the activity bookkeeping. `activeSince == nil` means the
    /// reader is not on screen; `activeDuration` is the time already banked.
    func setActivity(id: ReadingSessionID, activeDuration: TimeInterval, activeSince: Date?) async throws
    func delete(id: ReadingSessionID) async throws
}

public extension ReadingSessionRepository {
    func allSessions() async throws -> [ReadingSession] { [] }
}

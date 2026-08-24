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

    public init(
        id: ReadingSessionID = ReadingSessionID(), bookID: BookID,
        startedAt: Date = Date(), endedAt: Date? = nil,
        startLocator: BookLocator, endLocator: BookLocator? = nil,
        highlightCount: Int = 0, noteCount: Int = 0, agentDiscussionCount: Int = 0
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
    }

    public var duration: TimeInterval? { endedAt.map { $0.timeIntervalSince(startedAt) } }
}

public protocol ReadingSessionRepository: Sendable {
    func session(id: ReadingSessionID) async throws -> ReadingSession?
    func sessions(for bookID: BookID) async throws -> [ReadingSession]
    func insert(_ session: ReadingSession) async throws
    func complete(
        id: ReadingSessionID, endedAt: Date, endLocator: BookLocator,
        highlightCount: Int, noteCount: Int, agentDiscussionCount: Int
    ) async throws
    func delete(id: ReadingSessionID) async throws
}

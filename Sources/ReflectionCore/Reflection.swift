import Foundation
import LibraryCore
import ReadingSessionCore

public struct ReflectionID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
    public init() { rawValue = UUID() }
    public var description: String { rawValue.uuidString.lowercased() }
}

public enum ReflectionInputKind: String, Codable, Sendable { case text, voiceTranscript }

/// User-authored source data. Agent output is intentionally not represented by this type.
public struct Reflection: Hashable, Codable, Sendable, Identifiable {
    public let id: ReflectionID
    public let bookID: BookID
    public let sessionID: ReadingSessionID?
    public let originalText: String
    public let inputKind: ReflectionInputKind
    public let audioFileName: String?
    public let createdAt: Date

    public init(
        id: ReflectionID = ReflectionID(), bookID: BookID,
        sessionID: ReadingSessionID? = nil, originalText: String,
        inputKind: ReflectionInputKind, audioFileName: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookID = bookID
        self.sessionID = sessionID
        self.originalText = originalText
        self.inputKind = inputKind
        self.audioFileName = audioFileName
        self.createdAt = createdAt
    }
}

/// Future conversation/AI output. Kept separate so it can never overwrite `Reflection.originalText`.
public struct ReflectionDerivedMessage: Hashable, Codable, Sendable, Identifiable {
    public enum Role: String, Codable, Sendable { case agent, userFollowUp }
    public let id: UUID
    public let reflectionID: ReflectionID
    public let role: Role
    public let content: String
    public let createdAt: Date

    public init(id: UUID = UUID(), reflectionID: ReflectionID, role: Role, content: String, createdAt: Date = Date()) {
        self.id = id; self.reflectionID = reflectionID; self.role = role; self.content = content; self.createdAt = createdAt
    }
}

public protocol ReflectionRepository: Sendable {
    func reflection(id: ReflectionID) async throws -> Reflection?
    func reflections(for bookID: BookID) async throws -> [Reflection]
    func insert(_ reflection: Reflection, linkedHighlightIDs: [UUID]) async throws
    func linkedHighlightIDs(for reflectionID: ReflectionID) async throws -> [UUID]
    func derivedMessages(for reflectionID: ReflectionID) async throws -> [ReflectionDerivedMessage]
    func appendDerivedMessage(_ message: ReflectionDerivedMessage) async throws
    func delete(id: ReflectionID) async throws
}

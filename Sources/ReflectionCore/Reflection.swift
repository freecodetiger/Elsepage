import Foundation
import LibraryCore
import ReaderCore
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

public enum ReflectionMessageAuthor: String, Codable, Sendable { case user, agent }
public enum ReflectionMessageSource: String, Codable, Sendable { case userInput, agentGenerated }

/// Conversation content with explicit authorship and provenance.
/// `.userInput` is user-owned source data; `.agentGenerated` is replaceable derived data.
public struct ReflectionMessage: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let reflectionID: ReflectionID
    public let author: ReflectionMessageAuthor
    public let source: ReflectionMessageSource
    public let content: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(), reflectionID: ReflectionID,
        author: ReflectionMessageAuthor, source: ReflectionMessageSource,
        content: String, createdAt: Date = Date()
    ) throws {
        guard (author == .user && source == .userInput) || (author == .agent && source == .agentGenerated) else {
            throw ReflectionValidationError.inconsistentMessageProvenance
        }
        self.id = id; self.reflectionID = reflectionID; self.author = author
        self.source = source; self.content = content; self.createdAt = createdAt
    }

    public var isUserSourceOfTruth: Bool { source == .userInput }
}

public enum ReflectionEvidenceSourceType: String, Codable, Sendable {
    case bookLocator, highlight, note, readingSession
}

public struct ReflectionEvidence: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let reflectionID: ReflectionID
    public let sourceType: ReflectionEvidenceSourceType
    public let sourceID: String?
    public let locator: BookLocator?
    public let createdAt: Date

    public init(
        id: UUID = UUID(), reflectionID: ReflectionID,
        sourceType: ReflectionEvidenceSourceType, sourceID: String? = nil,
        locator: BookLocator? = nil, createdAt: Date = Date()
    ) throws {
        guard sourceID != nil || locator != nil else { throw ReflectionValidationError.missingEvidenceProvenance }
        self.id = id; self.reflectionID = reflectionID; self.sourceType = sourceType
        self.sourceID = sourceID; self.locator = locator; self.createdAt = createdAt
    }
}

public enum ReflectionValidationError: Error, Equatable {
    case inconsistentMessageProvenance
    case missingEvidenceProvenance
}

public protocol ReflectionRepository: Sendable {
    func reflection(id: ReflectionID) async throws -> Reflection?
    func reflections(for bookID: BookID) async throws -> [Reflection]
    func insert(_ reflection: Reflection, linkedHighlightIDs: [UUID], evidence: [ReflectionEvidence]) async throws
    func linkedHighlightIDs(for reflectionID: ReflectionID) async throws -> [UUID]
    func messages(for reflectionID: ReflectionID) async throws -> [ReflectionMessage]
    func appendMessage(_ message: ReflectionMessage) async throws
    func evidence(for reflectionID: ReflectionID) async throws -> [ReflectionEvidence]
    func appendEvidence(_ evidence: ReflectionEvidence) async throws
    func delete(id: ReflectionID) async throws
}

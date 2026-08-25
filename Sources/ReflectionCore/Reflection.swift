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
/// `originalText` is always the user's raw words (PRD P2: never overwritten by AI);
/// `polishedText` is the optional AI-tidied version shown in place of it.
public struct Reflection: Hashable, Codable, Sendable, Identifiable {
    public let id: ReflectionID
    public let bookID: BookID
    public let sessionID: ReadingSessionID?
    public let originalText: String
    public let inputKind: ReflectionInputKind
    public let audioFileName: String?
    public let polishedText: String?
    public let createdAt: Date

    public init(
        id: ReflectionID = ReflectionID(), bookID: BookID,
        sessionID: ReadingSessionID? = nil, originalText: String,
        inputKind: ReflectionInputKind, audioFileName: String? = nil,
        polishedText: String? = nil, createdAt: Date = Date()
    ) {
        self.id = id
        self.bookID = bookID
        self.sessionID = sessionID
        self.originalText = originalText
        self.inputKind = inputKind
        self.audioFileName = audioFileName
        self.polishedText = polishedText
        self.createdAt = createdAt
    }

    /// What the user reads first: the polished version when present, else the raw words.
    public var displayText: String { polishedText ?? originalText }
}

public enum ReflectionMessageAuthor: String, Codable, Sendable { case user, agent }
public enum ReflectionMessageSource: String, Codable, Sendable { case userInput, agentGenerated }

/// Conversation content with explicit authorship and provenance.
/// `.userInput` is user-owned source data; `.agentGenerated` is replaceable derived data.
/// `citations` is a loaded convenience (nil unless the repository attached it); the
/// persisted source of truth remains the `agentCitations` table.
public struct ReflectionMessage: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let reflectionID: ReflectionID
    public let author: ReflectionMessageAuthor
    public let source: ReflectionMessageSource
    public let content: String
    public let citations: [AgentCitation]?
    public let createdAt: Date

    public init(
        id: UUID = UUID(), reflectionID: ReflectionID,
        author: ReflectionMessageAuthor, source: ReflectionMessageSource,
        content: String, citations: [AgentCitation]? = nil, createdAt: Date = Date()
    ) throws {
        guard (author == .user && source == .userInput) || (author == .agent && source == .agentGenerated) else {
            throw ReflectionValidationError.inconsistentMessageProvenance
        }
        self.id = id; self.reflectionID = reflectionID; self.author = author
        self.source = source; self.content = content; self.citations = citations
        self.createdAt = createdAt
    }

    /// Copy with citations attached (used by the repository when loading messages).
    public func withCitations(_ attached: [AgentCitation]) -> ReflectionMessage {
        (try? ReflectionMessage(
            id: id, reflectionID: reflectionID, author: author, source: source,
            content: content, citations: attached.isEmpty ? nil : attached, createdAt: createdAt
        )) ?? self
    }

    public var isUserSourceOfTruth: Bool { source == .userInput }
}

public enum AgentEvidenceKind: String, Codable, Sendable {
    case nearbyPassage, bookPassage, pastReflection
}

/// Immutable snapshot of context actually sent to the model for one Agent reply.
/// Keeping the full Locator JSON makes provenance independently inspectable and navigable.
public struct AgentResponseEvidence: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let messageID: UUID
    public let kind: AgentEvidenceKind
    public let sourceID: String
    public let bookID: BookID
    public let title: String?
    public let excerpt: String
    public let locator: BookLocator?

    public init(
        id: String, messageID: UUID, kind: AgentEvidenceKind, sourceID: String,
        bookID: BookID, title: String? = nil, excerpt: String, locator: BookLocator? = nil
    ) {
        self.id = id; self.messageID = messageID; self.kind = kind; self.sourceID = sourceID
        self.bookID = bookID; self.title = title; self.excerpt = excerpt; self.locator = locator
    }
}

/// A model-requested reference accepted only after it resolves to evidence in the
/// exact context sent for this response.
public struct AgentCitation: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let messageID: UUID
    public let evidenceID: String
    public let marker: String

    public init(id: UUID = UUID(), messageID: UUID, evidenceID: String, marker: String) {
        self.id = id; self.messageID = messageID; self.evidenceID = evidenceID; self.marker = marker
    }
}

public struct AgentResponseProvenance: Hashable, Codable, Sendable {
    public let evidence: [AgentResponseEvidence]
    public let citations: [AgentCitation]

    public init(evidence: [AgentResponseEvidence], citations: [AgentCitation]) {
        self.evidence = evidence; self.citations = citations
    }
}

/// A deterministic, evidence-backed link from the current thought to one past
/// user-authored Reflection. It is derived data and never replaces either source.
public struct ReflectionConnection: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let reflectionID: ReflectionID
    public let sourceReflectionID: ReflectionID
    public let relevance: Double
    public let createdAt: Date

    public init(
        id: UUID = UUID(), reflectionID: ReflectionID, sourceReflectionID: ReflectionID,
        relevance: Double, createdAt: Date = Date()
    ) {
        self.id = id
        self.reflectionID = reflectionID
        self.sourceReflectionID = sourceReflectionID
        self.relevance = min(1, max(0, relevance))
        self.createdAt = createdAt
    }
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
    func appendAgentMessage(
        _ message: ReflectionMessage,
        evidence: [AgentResponseEvidence],
        citations: [AgentCitation]
    ) async throws
    func provenance(for messageID: UUID) async throws -> AgentResponseProvenance
    func message(id: UUID) async throws -> ReflectionMessage?
    func recentReflections(limit: Int) async throws -> [Reflection]
    func connections(for reflectionID: ReflectionID) async throws -> [ReflectionConnection]
    func saveConnection(_ connection: ReflectionConnection) async throws
    func evidence(for reflectionID: ReflectionID) async throws -> [ReflectionEvidence]
    func appendEvidence(_ evidence: ReflectionEvidence) async throws
    func delete(id: ReflectionID) async throws
}

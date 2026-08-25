import Foundation
import LibraryCore
import ReaderCore
import ReadingSessionCore
import RetrievalCore

/// A "What I think" bullet derived from the Agent's structured output. It is
/// derived data and never replaces the user's own `originalText`.
public struct JournalThought: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let reflectionID: ReflectionID
    public let messageID: UUID
    public let thought: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(), reflectionID: ReflectionID,
        messageID: UUID, thought: String, createdAt: Date = Date()
    ) {
        self.id = id
        self.reflectionID = reflectionID
        self.messageID = messageID
        self.thought = thought
        self.createdAt = createdAt
    }
}

public enum AgentQuestionStatus: String, Codable, Sendable, CaseIterable {
    case open, answered
}

/// An Agent question left open for the reader, tracked per message so a later
/// follow-up can mark it answered without rewriting history.
public struct AgentQuestion: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let reflectionID: ReflectionID
    public let messageID: UUID
    public let text: String
    public let createdAt: Date
    public var status: AgentQuestionStatus
    public var answeredByMessageID: UUID?

    public init(
        id: UUID = UUID(), reflectionID: ReflectionID,
        messageID: UUID, text: String, createdAt: Date = Date(),
        status: AgentQuestionStatus = .open, answeredByMessageID: UUID? = nil
    ) {
        self.id = id
        self.reflectionID = reflectionID
        self.messageID = messageID
        self.text = text
        self.createdAt = createdAt
        self.status = status
        self.answeredByMessageID = answeredByMessageID
    }
}

/// Journal-side citation. Layout intentionally mirrors `ReflectionEvidence`'s
/// locator columns so the Citation 收口 task can align on the same table.
public struct ReflectionCitation: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let reflectionID: ReflectionID
    public let messageID: UUID
    public let sourceType: ReflectionEvidenceSourceType
    public let sourceID: String?
    public let bookID: BookID
    public let locator: BookLocator?
    public let title: String?
    public let excerpt: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(), reflectionID: ReflectionID,
        messageID: UUID, sourceType: ReflectionEvidenceSourceType,
        sourceID: String? = nil, bookID: BookID, locator: BookLocator? = nil,
        title: String? = nil, excerpt: String? = nil, createdAt: Date = Date()
    ) {
        self.id = id
        self.reflectionID = reflectionID
        self.messageID = messageID
        self.sourceType = sourceType
        self.sourceID = sourceID
        self.bookID = bookID
        self.locator = locator
        self.title = title
        self.excerpt = excerpt
        self.createdAt = createdAt
    }
}

public enum JournalMemoryChangeType: String, Codable, Sendable, CaseIterable {
    case store, reinforce, revise
}

/// A snapshot of a memory proposal derived from Agent structured output. It is
/// deliberately decoupled from the Memory domain (a separate P2 task).
public struct JournalMemoryChange: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let journalID: ReflectionID
    public let changeType: JournalMemoryChangeType
    public let memoryID: String?
    public let summary: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(), journalID: ReflectionID,
        changeType: JournalMemoryChangeType, memoryID: String? = nil,
        summary: String, createdAt: Date = Date()
    ) {
        self.id = id
        self.journalID = journalID
        self.changeType = changeType
        self.memoryID = memoryID
        self.summary = summary
        self.createdAt = createdAt
    }
}

/// A structured, derived projection of one Reflection plus its reading context
/// and parsed Agent output. This is the Journal (as opposed to the raw Archive).
public struct JournalEntry: Hashable, Sendable, Identifiable {
    public let reflection: Reflection
    public let book: Book
    public let messages: [ReflectionMessage]
    public let evidence: [ReflectionEvidence]
    public let connections: [ReflectionArchiveConnection]
    public let session: ReadingSession?
    public let chapters: [BookChapterRef]
    public let linkedHighlights: [Highlight]
    public let whatIThink: [JournalThought]
    public let questions: [AgentQuestion]
    public let citations: [ReflectionCitation]
    public let memoryChanges: [JournalMemoryChange]

    public var id: ReflectionID { reflection.id }

    public var derivedAgentResponse: ReflectionMessage? {
        messages.last(where: { $0.source == .agentGenerated })
    }

    public var sourceLocator: BookLocator? {
        evidence.first(where: { $0.sourceType == .bookLocator })?.locator
    }

    public var sessionDuration: TimeInterval? { session?.duration }

    public var openQuestions: [AgentQuestion] { questions.filter { $0.status == .open } }

    public init(
        reflection: Reflection,
        book: Book,
        messages: [ReflectionMessage] = [],
        evidence: [ReflectionEvidence] = [],
        connections: [ReflectionArchiveConnection] = [],
        session: ReadingSession? = nil,
        chapters: [BookChapterRef] = [],
        linkedHighlights: [Highlight] = [],
        whatIThink: [JournalThought] = [],
        questions: [AgentQuestion] = [],
        citations: [ReflectionCitation] = [],
        memoryChanges: [JournalMemoryChange] = []
    ) {
        self.reflection = reflection
        self.book = book
        self.messages = messages
        self.evidence = evidence
        self.connections = connections
        self.session = session
        self.chapters = chapters
        self.linkedHighlights = linkedHighlights
        self.whatIThink = whatIThink
        self.questions = questions
        self.citations = citations
        self.memoryChanges = memoryChanges
    }
}

/// Persists the derived, structured Journal rows. Idempotent by design: the
/// assembly service materializes Agent output once per message.
public protocol JournalRepository: Sendable {
    func thoughts(for reflectionID: ReflectionID) async throws -> [JournalThought]
    func saveThought(_ thought: JournalThought) async throws
    func questions(for reflectionID: ReflectionID) async throws -> [AgentQuestion]
    func saveQuestion(_ question: AgentQuestion) async throws
    func citations(for reflectionID: ReflectionID) async throws -> [ReflectionCitation]
    func saveCitation(_ citation: ReflectionCitation) async throws
    func memoryChanges(for journalID: ReflectionID) async throws -> [JournalMemoryChange]
    func saveMemoryChange(_ change: JournalMemoryChange) async throws
    func hasStructuredData(for reflectionID: ReflectionID, messageID: UUID) async throws -> Bool
}

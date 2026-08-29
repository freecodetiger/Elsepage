import Foundation
import LibraryCore
import ReaderCore
import ReadingSessionCore
import RetrievalCore

/// A "What I think" bullet derived from the Agent's structured output. It is
/// derived data and never replaces the user's own `originalText`.
///
/// User sovereignty (JRNL-01/02, PRD F9 忠于用户): the user may edit a bullet.
/// An edited row keeps the Agent's original draft in `agentOriginalText` and is
/// flagged `userEdited`; later re-materialization of Agent output must never
/// overwrite the user's words (`JournalEntryService` drops a matching Agent
/// redraft instead). The Agent draft is captured once — at materialization or,
/// for pre-v19 rows, by the v19 migration backfill — and never rewritten.
public struct JournalThought: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let reflectionID: ReflectionID
    public let messageID: UUID
    public let thought: String
    public let createdAt: Date
    /// True once the user has edited (or explicitly confirmed) this bullet.
    public let userEdited: Bool
    /// The Agent's original draft, preserved verbatim so the user version and
    /// the Agent version remain distinguishable in data.
    public let agentOriginalText: String?

    public init(
        id: UUID = UUID(), reflectionID: ReflectionID,
        messageID: UUID, thought: String, createdAt: Date = Date(),
        userEdited: Bool = false, agentOriginalText: String? = nil
    ) {
        self.id = id
        self.reflectionID = reflectionID
        self.messageID = messageID
        self.thought = thought
        self.createdAt = createdAt
        self.userEdited = userEdited
        self.agentOriginalText = agentOriginalText
    }

    private enum CodingKeys: String, CodingKey {
        case id, reflectionID, messageID, thought, createdAt, userEdited, agentOriginalText
    }

    /// Tolerant decode: archives and payloads written before the userEdited
    /// fields existed decode with `userEdited = false` and no agent draft.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        reflectionID = try container.decode(ReflectionID.self, forKey: .reflectionID)
        messageID = try container.decode(UUID.self, forKey: .messageID)
        thought = try container.decode(String.self, forKey: .thought)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        userEdited = try container.decodeIfPresent(Bool.self, forKey: .userEdited) ?? false
        agentOriginalText = try container.decodeIfPresent(String.self, forKey: .agentOriginalText)
    }

    /// Returns a copy whose `agentOriginalText` defaults to the draft itself when
    /// unset. JournalThought rows are always Agent-drafted, so this is the
    /// persistence invariant behind the JRNL-02 overwrite guard: every Agent
    /// bullet keeps its original, whichever materialization path saved it.
    public func capturingAgentOriginal() -> JournalThought {
        guard agentOriginalText == nil else { return self }
        return JournalThought(
            id: id, reflectionID: reflectionID, messageID: messageID,
            thought: thought, createdAt: createdAt,
            userEdited: userEdited, agentOriginalText: thought
        )
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
    /// Applies a user edit to an Agent-drafted thought (JRNL-01/02): stores the
    /// user's text, flags the row `userEdited` and preserves the Agent's original
    /// draft. Agent re-materialization must never overwrite a row edited here.
    func applyUserEdit(thoughtID: UUID, newText: String) async throws
    func questions(for reflectionID: ReflectionID) async throws -> [AgentQuestion]
    func saveQuestion(_ question: AgentQuestion) async throws
    func citations(for reflectionID: ReflectionID) async throws -> [ReflectionCitation]
    func saveCitation(_ citation: ReflectionCitation) async throws
    func memoryChanges(for journalID: ReflectionID) async throws -> [JournalMemoryChange]
    func saveMemoryChange(_ change: JournalMemoryChange) async throws
    func hasStructuredData(for reflectionID: ReflectionID, messageID: UUID) async throws -> Bool
}

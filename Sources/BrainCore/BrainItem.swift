import Foundation

/// The Brain domain (docs/brain.md): three first-class objects —
///
///   Thought  — an evolving proposition ("我正在形成什么观点")
///   Question — an open, tracked problem ("还没想明白的问题")
///   Memory   — stable user knowledge the Agent may rely on ("Agent 记住的我")
///
/// Reflections, book passages and conversation messages are NOT brain items;
/// they are evidence (Phase 14). Evidence is fact, brain items are
/// interpretation. Everything here is a closed enum / tagged union so illegal
/// states are unrepresentable: no `type: String` with optional per-kind fields.
public struct BrainItemID: Hashable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public enum BrainItemKind: String, Hashable, Sendable, CaseIterable {
    case thought, question, memory
}

/// Evidence provenance. Phase 1 carries string-typed source IDs to keep
/// BrainCore dependency-free; the integration layer adapts typed IDs
/// (`ReflectionID`, `BookChunkID`) in Phase 14/16.
public enum BrainEvidenceSource: Hashable, Sendable {
    case reflection(String)
    case bookChunk(String)
    case message(String)
}

public struct BrainProvenance: Hashable, Sendable {
    public let originEvidence: BrainEvidenceSource?

    public init(originEvidence: BrainEvidenceSource?) {
        self.originEvidence = originEvidence
    }
}

/// A thought evolves through stages; it is never a boolean "stable" flag.
public enum ThoughtStage: String, Hashable, Codable, Sendable, CaseIterable {
    case emerging, evolving, stable, reconsidering, archived
}

public struct Thought: Hashable, Sendable {
    public let id: BrainItemID
    public var title: String
    public var statement: String
    public var stage: ThoughtStage
    public var provenance: BrainProvenance
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: BrainItemID, title: String, statement: String, stage: ThoughtStage,
        provenance: BrainProvenance, createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.statement = statement
        self.stage = stage
        self.provenance = provenance
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A question that stays answerable-but-unresolved; "resolved" transitions into
/// a Thought through a relation (Phase 14), never by deletion.
public enum QuestionState: String, Hashable, Codable, Sendable, CaseIterable {
    case open, exploring, partiallyResolved, resolved, dormant
}

public struct Question: Hashable, Sendable {
    public let id: BrainItemID
    public var question: String
    public var state: QuestionState
    public var provenance: BrainProvenance
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: BrainItemID, question: String, state: QuestionState,
        provenance: BrainProvenance, createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.question = question
        self.state = state
        self.provenance = provenance
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Where a memory came from. The Agent must surface this in the UI (brain.md
/// §17): a user's explicit statement and an agent inference are not the same
/// kind of trust.
public enum MemoryOrigin: String, Hashable, Codable, Sendable, CaseIterable {
    case userExplicit, agentInferred, derivedFromThought
}

public enum MemoryState: String, Hashable, Codable, Sendable, CaseIterable {
    case active, needsReview, superseded, forgotten
}

public enum MemoryConfidence: String, Hashable, Codable, Sendable, CaseIterable {
    case high, medium, low
}

/// Agent-reliable stable knowledge. Named `BrainMemory` (brain.md calls it
/// `Memory`) to avoid confusion with the legacy `ReaderMemory` row model it is
/// backfilled from; the semantics are the brain.md ones.
public struct BrainMemory: Hashable, Sendable {
    public let id: BrainItemID
    public var content: String
    public var origin: MemoryOrigin
    public var confidence: MemoryConfidence
    public var state: MemoryState
    public var provenance: BrainProvenance
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: BrainItemID, content: String, origin: MemoryOrigin, confidence: MemoryConfidence,
        state: MemoryState, provenance: BrainProvenance, createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.content = content
        self.origin = origin
        self.confidence = confidence
        self.state = state
        self.provenance = provenance
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// The closed tagged union. Persistence maps `kind` rows back into exactly one
/// of these cases; there is no fourth "generic" shape.
public enum BrainItem: Hashable, Sendable {
    case thought(Thought)
    case question(Question)
    case memory(BrainMemory)

    public var id: BrainItemID {
        switch self {
        case .thought(let item): item.id
        case .question(let item): item.id
        case .memory(let item): item.id
        }
    }

    public var kind: BrainItemKind {
        switch self {
        case .thought: .thought
        case .question: .question
        case .memory: .memory
        }
    }
}

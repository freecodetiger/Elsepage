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

/// How an evidence item relates to a brain item (docs/brain.md §4). Evidence
/// is fact, brain items are interpretation — this vocabulary expresses the
/// interpretive stance the item takes toward its sources.
public enum EvidenceRelation: String, Hashable, Codable, Sendable, CaseIterable {
    case origin, supports, contradicts, revises, raises, answers
}

/// Item↔item relations (docs/brain.md §5) — deliberately a small closed set,
/// not a knowledge graph. Lifecycle is expressed as relations, never as state
/// rewrites: a resolved question points at an answering thought via
/// `addresses`; a confirmed thought spawns a memory via `derivedMemory`, and
/// both records keep existing.
public enum BrainRelationType: String, Hashable, Codable, Sendable, CaseIterable {
    case related, supports, contradicts, evolvesFrom, raises, addresses, derivedMemory
}

/// One evidence row attached to a brain item. Identity is
/// (item, source, relation) — attaching the same source twice with the same
/// relation is a no-op, not a duplicate.
public struct BrainEvidence: Hashable, Sendable {
    public let itemID: BrainItemID
    public let source: BrainEvidenceSource
    public let relation: EvidenceRelation
    /// 0...1 (1 = full strength). Kept simple and deterministic in v1.
    public let weight: Double
    public let createdAt: Date

    public init(itemID: BrainItemID, source: BrainEvidenceSource, relation: EvidenceRelation, weight: Double = 1, createdAt: Date) {
        self.itemID = itemID
        self.source = source
        self.relation = relation
        self.weight = weight
        self.createdAt = createdAt
    }
}

/// A directed relation between two brain items. Identity is
/// (source, target, relation).
public struct BrainRelation: Hashable, Sendable {
    public let sourceItemID: BrainItemID
    public let targetItemID: BrainItemID
    public let relation: BrainRelationType
    /// 0...1.
    public let weight: Double
    public let createdAt: Date

    public init(sourceItemID: BrainItemID, targetItemID: BrainItemID, relation: BrainRelationType, weight: Double = 1, createdAt: Date) {
        self.sourceItemID = sourceItemID
        self.targetItemID = targetItemID
        self.relation = relation
        self.weight = weight
        self.createdAt = createdAt
    }
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

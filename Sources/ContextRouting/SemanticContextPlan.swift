import Foundation

/// The strict semantic domain plan produced by the Context Planner (v2).
///
/// The LLM decides semantic intent only — what the user needs and which local
/// sources are worth consulting, expressed as a closed set of tagged requests.
/// Every numeric retrieval/runtime knob (evidence counts, candidate limits,
/// reranker, expansion, token budgets) is decided downstream by the
/// `ContextPolicyCompiler`, never by the model.
///
/// This type is the runtime truth; the LLM-facing shape is `PlannerWirePlan`
/// and the persisted trace shape is the legacy `ReaderContextPlan`
/// representation compiled by `ContextPolicyCompiler`.
public struct SemanticContextPlan: Hashable, Sendable {
    public let intent: ReflectionIntent
    public let requests: [ContextRequest]
    public let response: SemanticResponsePlan

    public init(intent: ReflectionIntent, requests: [ContextRequest], response: SemanticResponsePlan) {
        self.intent = intent
        self.requests = requests
        self.response = response
    }

    public var nearbyRequested: Bool {
        requests.contains(.nearby)
    }

    public var bookRequest: BookContextRequest? {
        requests.compactMap { if case .book(let request) = $0 { return request } else { return nil } }.first
    }

    public var pastThoughtRequest: PastThoughtContextRequest? {
        requests.compactMap { if case .pastThought(let request) = $0 { return request } else { return nil } }.first
    }

    public var brainRequest: BrainContextRequest? {
        requests.compactMap { if case .brain(let request) = $0 { return request } else { return nil } }.first
    }
}

/// One planned context source. A tagged union so invalid states are hard to
/// represent: a book request cannot carry memory configuration, an absent
/// request unambiguously means "this source was not planned", and per-source
/// multiplicity is checkable. Long-term memory is deliberately absent — it is
/// a deterministic system policy (always consulted as evidence), compiled by
/// `ContextPolicyCompiler`, not an LLM decision.
public enum ContextRequest: Hashable, Sendable {
    case nearby
    case book(BookContextRequest)
    case pastThought(PastThoughtContextRequest)
    /// Retrieval over the user's own formed thinking (Thought/Question). The
    /// LLM decides only whether the user is clearly reaching back to their own
    /// ideas and provides a query; kinds and limits are compiled policy.
    case brain(BrainContextRequest)
}

/// A planned retrieval over the user's brain items (docs/brain.md §11B).
public struct BrainContextRequest: Hashable, Sendable {
    public let query: String

    public init(query: String) {
        self.query = query
    }
}

/// A planned book retrieval. Queries are the only open-world values; scope and
/// purpose are closed enums. `denseQuery`/`lexicalTerms` are normalized at the
/// wire boundary (trimmed, defaulting to `query`) so the domain model carries
/// no optionality here.
public struct BookContextRequest: Hashable, Sendable {
    public let query: String
    public let purpose: RetrievalPurpose
    public let scope: PreferredBookScope
    public let denseQuery: String
    public let lexicalTerms: String

    public init(query: String, purpose: RetrievalPurpose, scope: PreferredBookScope, denseQuery: String, lexicalTerms: String) {
        self.query = query
        self.purpose = purpose
        self.scope = scope
        self.denseQuery = denseQuery
        self.lexicalTerms = lexicalTerms
    }
}

/// A planned past-thought retrieval. The evidence count is deliberately absent:
/// same-book preference and the single-connection rule are code policy.
public struct PastThoughtContextRequest: Hashable, Sendable {
    public let query: String
    public let purpose: PastThoughtPurpose

    public init(query: String, purpose: PastThoughtPurpose) {
        self.query = query
        self.purpose = purpose
    }
}

/// The LLM's conversational posture for this reply. Length stays a closed
/// semantic enum; "may ask a question" is a closed two-state posture instead
/// of a bare boolean, so the prompt cannot drift into flag combinations.
/// The hard runtime constraint (no question when the previous agent turn
/// already asked one) is enforced deterministically by `SemanticPlanValidator`.
public enum ConversationPosture: String, Hashable, Codable, Sendable {
    case respondOnly
    case mayAskQuestion
}

public struct SemanticResponsePlan: Hashable, Sendable {
    public let length: ResponseLength
    public let posture: ConversationPosture

    public init(length: ResponseLength, posture: ConversationPosture) {
        self.length = length
        self.posture = posture
    }
}

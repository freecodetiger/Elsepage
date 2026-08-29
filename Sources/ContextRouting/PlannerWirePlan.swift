import Foundation

/// The LLM-facing wire contract for the Context Planner (schema v2,
/// `reader-context-router-v2`). Deliberately narrow: only semantic decisions —
/// intent, which sources to consult, retrieval purpose/scope, query rewriting
/// and the response posture. No numeric retrieval/runtime tuning appears here;
/// those are compiled deterministically from the validated semantic plan.
///
/// Decoding is strict on closed enums (an off-schema value fails decode →
/// bounded repair → deterministic fallback) and forgiving only where the value
/// is open-world (`denseQuery`/`lexicalTerms` optional, defaulting to `query`).
public struct PlannerWirePlan: Codable, Hashable, Sendable {
    public var intent: ReflectionIntent
    public var nearbyPassage: NearbyPassagePlan
    public var bookRetrieval: BookRetrievalRequest?
    public var pastThoughtRetrieval: PastThoughtRetrievalRequest?
    public var response: ResponsePlan?

    public init(
        intent: ReflectionIntent,
        nearbyPassage: NearbyPassagePlan,
        bookRetrieval: BookRetrievalRequest? = nil,
        pastThoughtRetrieval: PastThoughtRetrievalRequest? = nil,
        response: ResponsePlan? = nil
    ) {
        self.intent = intent
        self.nearbyPassage = nearbyPassage
        self.bookRetrieval = bookRetrieval
        self.pastThoughtRetrieval = pastThoughtRetrieval
        self.response = response
    }

    public struct BookRetrievalRequest: Codable, Hashable, Sendable {
        public var query: String
        public var purpose: RetrievalPurpose
        public var scope: PreferredBookScope
        public var denseQuery: String?
        public var lexicalTerms: String?

        public init(query: String, purpose: RetrievalPurpose, scope: PreferredBookScope, denseQuery: String? = nil, lexicalTerms: String? = nil) {
            self.query = query
            self.purpose = purpose
            self.scope = scope
            self.denseQuery = denseQuery
            self.lexicalTerms = lexicalTerms
        }
    }

    public struct PastThoughtRetrievalRequest: Codable, Hashable, Sendable {
        public var query: String
        public var purpose: PastThoughtPurpose

        public init(query: String, purpose: PastThoughtPurpose) {
            self.query = query
            self.purpose = purpose
        }
    }

    public struct ResponsePlan: Codable, Hashable, Sendable {
        public var length: ResponseLength
        public var posture: ConversationPosture

        public init(length: ResponseLength, posture: ConversationPosture) {
            self.length = length
            self.posture = posture
        }
    }
}

public extension PlannerWirePlan {
    /// Schema version recorded in routing traces for plans decoded from this
    /// wire contract. Legacy (v1) traces simply leave the field nil.
    static let schemaVersion = 2

    /// Normalizes the decoded wire plan into the strict domain model:
    /// trims queries (bounded), defaults denseQuery/lexicalTerms to the query,
    /// keeps at most one request per source (first wins), and derives a
    /// conservative response plan when the model omitted one.
    ///
    /// Normalization is deterministic and semantic-only — availability gating,
    /// empty-query removal and conversation hard rules belong to
    /// `SemanticPlanValidator`.
    func normalized() -> SemanticContextPlan {
        var requests: [ContextRequest] = []
        if nearbyPassage == .include { requests.append(.nearby) }
        if let book = bookRetrieval {
            let query = Self.boundedQuery(book.query)
            requests.append(.book(BookContextRequest(
                query: query,
                purpose: book.purpose,
                scope: book.scope,
                denseQuery: book.denseQuery.flatMap(Self.boundedQuery) ?? query,
                lexicalTerms: book.lexicalTerms.flatMap(Self.boundedQuery) ?? query
            )))
        }
        if let past = pastThoughtRetrieval {
            requests.append(.pastThought(PastThoughtContextRequest(
                query: Self.boundedQuery(past.query),
                purpose: past.purpose
            )))
        }
        let response = self.response.map { SemanticResponsePlan(length: $0.length, posture: $0.posture) }
            ?? SemanticResponsePlan(length: .short, posture: .respondOnly)
        return SemanticContextPlan(intent: intent, requests: requests, response: response)
    }

    /// Shared query hygiene: trim and cap at 240 characters. Used by wire
    /// normalization and by the deterministic fallback so both paths produce
    /// identically bounded queries.
    static func boundedQuery(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(240))
    }
}

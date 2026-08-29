import Foundation

/// The deterministic execution policy compiled from a validated semantic plan.
///
/// The LLM decides semantic intent (`SemanticContextPlan`); this type decides
/// execution: evidence counts, retrieval mode, candidate limits, reranker and
/// expansion policy, and per-source character budgets. Rules are centralized,
/// testable mappings (`purpose + intent + scope → retrieval configuration`)
/// instead of scattered prompt instructions, validator clamps and call-site
/// defaults.
public struct ContextExecutionPlan: Hashable, Sendable {
    public let intent: ReflectionIntent
    public let nearbyIncluded: Bool
    /// Nil → book retrieval is skipped this turn.
    public let book: BookRetrievalPolicy?
    /// Nil → past-thought retrieval (and connection building) is skipped.
    public let pastThought: ReflectionRetrievalPolicy?
    /// Nil → no brain retrieval this turn (user's own formed thinking).
    public let brain: BrainRetrievalPolicy?
    /// Deterministic system policy: long-term memory is always consulted as
    /// evidence, independent of the LLM plan (v1 plans carried a
    /// `memoryRetrieval` request that no consumer ever read; the behavior was
    /// already unconditional — see ReaderAgent/Bench pre-routing retrieval).
    public let memory: MemoryRetrievalPolicy
    public let responseGuidance: ResponseGuidance
    public let budget: ContextBudget

    /// Legacy wire-shape snapshot of the normalized plan, for
    /// `ContextPlanTrace.proposedPlan` (same persisted shape as v1 traces so
    /// Settings diagnostics decode unchanged). Numeric fields carry the
    /// compiled values actually used; corrections are recorded separately in
    /// `ContextPlanTrace.validationCorrections`.
    public let legacyProposal: ReaderContextPlan
    /// Legacy validated-shape snapshot (v1 persisted shape) for
    /// `ContextPlanTrace.validatedPlan`.
    public let legacyValidatedPlan: ValidatedContextPlan

    public init(
        intent: ReflectionIntent,
        nearbyIncluded: Bool,
        book: BookRetrievalPolicy?,
        pastThought: ReflectionRetrievalPolicy?,
        brain: BrainRetrievalPolicy?,
        memory: MemoryRetrievalPolicy,
        responseGuidance: ResponseGuidance,
        budget: ContextBudget,
        legacyProposal: ReaderContextPlan,
        legacyValidatedPlan: ValidatedContextPlan
    ) {
        self.intent = intent
        self.nearbyIncluded = nearbyIncluded
        self.book = book
        self.pastThought = pastThought
        self.brain = brain
        self.memory = memory
        self.responseGuidance = responseGuidance
        self.budget = budget
        self.legacyProposal = legacyProposal
        self.legacyValidatedPlan = legacyValidatedPlan
    }
}

/// Compiled book-retrieval execution policy. All numeric values are code
/// policy; the LLM never sets them.
public struct BookRetrievalPolicy: Hashable, Sendable {
    public let query: String
    /// Normalized dense-recall query (semantic rewriting, defaults to query).
    public let denseQuery: String
    /// Normalized lexical terms (entities/terms, defaults to query).
    public let lexicalTerms: String
    public let purpose: RetrievalPurpose
    public let scope: PreferredBookScope
    public let evidenceLimit: Int
    /// The implemented retrieval path is hybrid (lexical + semantic RRF);
    /// degradation to lexical-only on missing embeddings is deterministic
    /// behavior inside the retriever, not a per-plan decision.
    public let retrievalMode: RetrievalMode
    public let candidateLimit: Int
    public let useReranker: Bool
    public let expansionMode: ContextExpansionMode

    public init(
        query: String, denseQuery: String, lexicalTerms: String,
        purpose: RetrievalPurpose, scope: PreferredBookScope,
        evidenceLimit: Int, retrievalMode: RetrievalMode,
        candidateLimit: Int, useReranker: Bool, expansionMode: ContextExpansionMode
    ) {
        self.query = query
        self.denseQuery = denseQuery
        self.lexicalTerms = lexicalTerms
        self.purpose = purpose
        self.scope = scope
        self.evidenceLimit = evidenceLimit
        self.retrievalMode = retrievalMode
        self.candidateLimit = candidateLimit
        self.useReranker = useReranker
        self.expansionMode = expansionMode
    }
}

public struct ReflectionRetrievalPolicy: Hashable, Sendable {
    public let query: String
    public let purpose: PastThoughtPurpose
    /// The single-strongest-connection rule is code policy; exactly one past
    /// thought is retrieved per turn.
    public let evidenceLimit: Int

    public init(query: String, purpose: PastThoughtPurpose, evidenceLimit: Int = 1) {
        self.query = query
        self.purpose = purpose
        self.evidenceLimit = evidenceLimit
    }
}

public struct MemoryRetrievalPolicy: Hashable, Sendable {
    public let topN: Int

    public init(topN: Int = 2) {
        self.topN = max(1, topN)
    }
}

/// Compiled brain-retrieval execution policy (docs/brain.md §11B). The LLM
/// decides only whether the user reaches back to their own ideas and provides
/// a query; kinds (thought+question) and the limit are code policy. Pinned
/// context (an explicitly active brain item) bypasses the plan entirely — it
/// is input-driven and can never be vetoed by the model.
public struct BrainRetrievalPolicy: Hashable, Sendable {
    public let query: String
    public let limit: Int

    public init(query: String, limit: Int = Self.defaultLimit) {
        self.query = query
        self.limit = max(1, limit)
    }

    public static let defaultLimit = 3
}

/// Compiles a validated `SemanticContextPlan` into a `ContextExecutionPlan`.
public struct ContextPolicyCompiler: Sendable {
    public init() {}

    public func compile(_ plan: SemanticContextPlan, input: ContextRoutingInput) -> ContextExecutionPlan {
        let bookPolicy = plan.bookRequest.map { Self.bookPolicy(for: $0) }
        let pastPolicy = plan.pastThoughtRequest.map {
            ReflectionRetrievalPolicy(query: $0.query, purpose: $0.purpose)
        }
        let brainPolicy = plan.brainRequest.map {
            BrainRetrievalPolicy(query: $0.query, limit: BrainRetrievalPolicy.defaultLimit)
        }
        let budget = Self.budget(for: plan.intent)
        let guidance = Self.responseGuidance(from: plan.response)

        let legacyProposal = ReaderContextPlan(
            intent: plan.intent,
            nearbyPassage: plan.nearbyRequested ? .include : .omit,
            bookRetrieval: plan.bookRequest.map { request in
                BookRetrievalPlan(
                    query: request.query, purpose: request.purpose, preferredScope: request.scope,
                    maximumEvidenceCount: bookPolicy?.evidenceLimit ?? 1,
                    denseQuery: request.denseQuery, lexicalTerms: request.lexicalTerms
                )
            },
            pastThoughtRetrieval: plan.pastThoughtRequest.map {
                PastThoughtRetrievalPlan(query: $0.query, purpose: $0.purpose, maximumEvidenceCount: pastPolicy?.evidenceLimit ?? 1)
            },
            memoryRetrieval: nil,
            responseGuidance: guidance,
            rationale: nil
        )
        let legacyValidated = ValidatedContextPlan(
            intent: plan.intent,
            nearbyPassage: plan.nearbyRequested ? .include : .omit,
            bookRetrieval: bookPolicy.map {
                BookRetrievalPlan(
                    query: $0.query, purpose: $0.purpose, preferredScope: $0.scope,
                    maximumEvidenceCount: $0.evidenceLimit,
                    denseQuery: $0.denseQuery, lexicalTerms: $0.lexicalTerms,
                    retrievalMode: $0.retrievalMode, candidateLimit: $0.candidateLimit,
                    useReranker: $0.useReranker, expansionMode: $0.expansionMode
                )
            },
            pastThoughtRetrieval: pastPolicy.map {
                PastThoughtRetrievalPlan(query: $0.query, purpose: $0.purpose, maximumEvidenceCount: $0.evidenceLimit)
            },
            memoryRetrieval: nil,
            responseGuidance: guidance,
            budget: budget
        )

        return ContextExecutionPlan(
            intent: plan.intent,
            nearbyIncluded: plan.nearbyRequested,
            book: bookPolicy,
            pastThought: pastPolicy,
            brain: brainPolicy,
            memory: MemoryRetrievalPolicy(),
            responseGuidance: guidance,
            budget: budget,
            legacyProposal: legacyProposal,
            legacyValidatedPlan: legacyValidated
        )
    }

    // MARK: - Policy mappings

    /// Evidence (parent windows) per book-retrieval purpose. Grounded in the
    /// former validator clamp (1...4) and the deterministic fallback (3):
    /// fact checks stay narrow, concept tracing earns the widest window.
    public static func evidenceLimit(for purpose: RetrievalPurpose) -> Int {
        switch purpose {
        case .verifyBookFact: 2
        case .traceConcept: 4
        case .clarifyCurrentPassage, .findEarlierSupport, .findEarlierContrast: 3
        }
    }

    /// Fused candidates handed to the reranker (cost control), matching the
    /// retriever's former default.
    public static let candidateLimit = 10
    /// The reranker is the RAG precision gate; unavailability degrades to fused
    /// results deterministically, so it is always requested.
    public static let useReranker = true
    public static let retrievalMode: RetrievalMode = .hybrid
    public static let expansionMode: ContextExpansionMode = .boundedWindow
    public static let memoryTopN = 2

    private static func bookPolicy(for request: BookContextRequest) -> BookRetrievalPolicy {
        BookRetrievalPolicy(
            query: request.query,
            denseQuery: request.denseQuery,
            lexicalTerms: request.lexicalTerms,
            purpose: request.purpose,
            scope: request.scope,
            evidenceLimit: evidenceLimit(for: request.purpose),
            retrievalMode: retrievalMode,
            candidateLimit: candidateLimit,
            useReranker: useReranker,
            expansionMode: expansionMode
        )
    }

    /// Per-source character budgets by intent (the former validator table,
    /// moved here — budgets are execution policy, not validation).
    public static func budget(for intent: ReflectionIntent) -> ContextBudget {
        switch intent {
        case .emotionalRecord:
            ContextBudget(totalCharacters: 6_000, nearbyCharacters: 600, bookEvidenceCharacters: 0, pastThoughtCharacters: 0, conversationCharacters: 1_800)
        case .authorDisagreement, .conceptualQuestion:
            ContextBudget(totalCharacters: 6_000, nearbyCharacters: 1_400, bookEvidenceCharacters: 2_800, pastThoughtCharacters: 600, conversationCharacters: 1_200)
        case .personalConnection:
            ContextBudget(totalCharacters: 6_000, nearbyCharacters: 1_000, bookEvidenceCharacters: 2_000, pastThoughtCharacters: 1_200, conversationCharacters: 1_200)
        case .conversationContinuation:
            ContextBudget(totalCharacters: 6_000, nearbyCharacters: 600, bookEvidenceCharacters: 1_400, pastThoughtCharacters: 600, conversationCharacters: 2_400)
        case .passageObservation, .unclear:
            ContextBudget(totalCharacters: 6_000, nearbyCharacters: 1_200, bookEvidenceCharacters: 2_200, pastThoughtCharacters: 800, conversationCharacters: 1_400)
        }
    }

    private static func responseGuidance(from response: SemanticResponsePlan) -> ResponseGuidance {
        switch response.posture {
        case .respondOnly:
            ResponseGuidance(targetLength: response.length, allowQuestion: false, shouldNaturallyEnd: true)
        case .mayAskQuestion:
            ResponseGuidance(targetLength: response.length, allowQuestion: true, shouldNaturallyEnd: false)
        }
    }
}

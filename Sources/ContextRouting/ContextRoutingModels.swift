import AgentRuntime
import Foundation
import LibraryCore

public enum ReaderInteractionMode: String, Codable, Sendable { case reflection, conversation }
public enum ReflectionIntent: String, Codable, Sendable {
    case emotionalRecord, passageObservation, authorDisagreement, conceptualQuestion
    case personalConnection, conversationContinuation, unclear
}
public enum NearbyPassagePlan: String, Codable, Sendable { case include, omit }
public enum RetrievalPurpose: String, Codable, Sendable {
    case clarifyCurrentPassage, findEarlierSupport, findEarlierContrast, traceConcept, verifyBookFact
}
public enum PreferredBookScope: String, Codable, Sendable { case currentSection, currentChapter, readSoFar }
public enum PastThoughtPurpose: String, Codable, Sendable { case findContinuation, findChange, findContradiction, findRecurringQuestion }
public enum ResponseLength: String, Codable, Sendable { case short, medium, long }

public struct RoutingMessage: Hashable, Codable, Sendable {
    public let role: String
    public let content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
}

public struct CurrentReadingSummary: Hashable, Codable, Sendable {
    public let bookID: BookID
    public let chapterTitle: String?
    public let selectedText: String?
    public let nearbyTextPreview: String?
    public let hasCurrentLocator: Bool
    public init(bookID: BookID, chapterTitle: String? = nil, selectedText: String? = nil,
                nearbyTextPreview: String? = nil, hasCurrentLocator: Bool) {
        self.bookID = bookID; self.chapterTitle = chapterTitle; self.selectedText = selectedText
        self.nearbyTextPreview = nearbyTextPreview; self.hasCurrentLocator = hasCurrentLocator
    }
}

public struct AvailableContextSources: Hashable, Codable, Sendable {
    public let hasNearbyPassage: Bool
    public let hasBookIndex: Bool
    public let hasPastThoughts: Bool
    /// Session-scoped availability signals. Nullable so existing call sites keep
    /// the compact initializer and the Router can treat absence as "unknown".
    public let hasSessionHighlight: Bool?
    public let hasSessionNote: Bool?
    public let hasBookReflections: Bool?

    public init(hasNearbyPassage: Bool, hasBookIndex: Bool, hasPastThoughts: Bool) {
        self.hasNearbyPassage = hasNearbyPassage; self.hasBookIndex = hasBookIndex; self.hasPastThoughts = hasPastThoughts
        self.hasSessionHighlight = nil; self.hasSessionNote = nil; self.hasBookReflections = nil
    }

    public init(
        hasNearbyPassage: Bool, hasBookIndex: Bool, hasPastThoughts: Bool,
        hasSessionHighlight: Bool?, hasSessionNote: Bool?, hasBookReflections: Bool?
    ) {
        self.hasNearbyPassage = hasNearbyPassage; self.hasBookIndex = hasBookIndex; self.hasPastThoughts = hasPastThoughts
        self.hasSessionHighlight = hasSessionHighlight; self.hasSessionNote = hasSessionNote; self.hasBookReflections = hasBookReflections
    }
}

public struct ContextRoutingInput: Hashable, Codable, Sendable {
    public let interactionMode: ReaderInteractionMode
    public let currentReflection: String
    public let recentConversation: [RoutingMessage]
    public let currentReading: CurrentReadingSummary?
    public let availableSources: AvailableContextSources
    public let previousAgentAskedQuestion: Bool
    public init(interactionMode: ReaderInteractionMode, currentReflection: String,
                recentConversation: [RoutingMessage], currentReading: CurrentReadingSummary?,
                availableSources: AvailableContextSources, previousAgentAskedQuestion: Bool) {
        self.interactionMode = interactionMode; self.currentReflection = currentReflection
        self.recentConversation = recentConversation; self.currentReading = currentReading
        self.availableSources = availableSources; self.previousAgentAskedQuestion = previousAgentAskedQuestion
    }
}

public struct BookRetrievalPlan: Hashable, Codable, Sendable {
    public let query: String
    public let purpose: RetrievalPurpose
    public let preferredScope: PreferredBookScope
    public let maximumEvidenceCount: Int
    // Context-engineering v2: denseQuery drives semantic recall, lexicalTerms drives
    // BM25/lexical recall. Both optional so plans persisted before this evolution
    // decode cleanly; consumers fall back to `query` when absent. New retrieval
    // knobs are optional too and get defaults/clamps at the assembly layer.
    public let denseQuery: String?
    public let lexicalTerms: String?
    public let retrievalMode: RetrievalMode?
    public let candidateLimit: Int?
    public let useReranker: Bool?
    public let expansionMode: ContextExpansionMode?
    public let expansionMaxTokens: Int?
    public init(query: String, purpose: RetrievalPurpose, preferredScope: PreferredBookScope, maximumEvidenceCount: Int,
                denseQuery: String? = nil, lexicalTerms: String? = nil, retrievalMode: RetrievalMode? = nil,
                candidateLimit: Int? = nil, useReranker: Bool? = nil, expansionMode: ContextExpansionMode? = nil,
                expansionMaxTokens: Int? = nil) {
        self.query = query; self.purpose = purpose; self.preferredScope = preferredScope; self.maximumEvidenceCount = maximumEvidenceCount
        self.denseQuery = denseQuery; self.lexicalTerms = lexicalTerms; self.retrievalMode = retrievalMode
        self.candidateLimit = candidateLimit; self.useReranker = useReranker
        self.expansionMode = expansionMode; self.expansionMaxTokens = expansionMaxTokens
    }
}

public struct PastThoughtRetrievalPlan: Hashable, Codable, Sendable {
    public let query: String
    public let purpose: PastThoughtPurpose
    public let maximumEvidenceCount: Int
    public init(query: String, purpose: PastThoughtPurpose, maximumEvidenceCount: Int) {
        self.query = query; self.purpose = purpose; self.maximumEvidenceCount = maximumEvidenceCount
    }
}

public enum RetrievalMode: String, Hashable, Codable, Sendable {
    case dense, lexical, hybrid
}

public enum ContextExpansionMode: String, Hashable, Codable, Sendable {
    /// Expand from a hit child to a bounded sibling window inside its parent,
    /// re-checking the reading boundary before emitting evidence.
    case boundedWindow
}

public struct MemoryRetrievalPlan: Hashable, Codable, Sendable {
    public let query: String
    public let maximumEvidenceCount: Int
    public init(query: String, maximumEvidenceCount: Int) {
        self.query = query; self.maximumEvidenceCount = maximumEvidenceCount
    }
}

public struct ResponseGuidance: Hashable, Codable, Sendable {
    public let targetLength: ResponseLength
    public let allowQuestion: Bool
    public let shouldNaturallyEnd: Bool
    public init(targetLength: ResponseLength, allowQuestion: Bool, shouldNaturallyEnd: Bool) {
        self.targetLength = targetLength; self.allowQuestion = allowQuestion; self.shouldNaturallyEnd = shouldNaturallyEnd
    }
}

/// Legacy persisted plan shape (planner schema v1). No longer produced by the
/// LLM path — the router emits `SemanticContextPlan` — but kept intact because
/// `ContextPlanTrace` embeds it, and every historical routingTraces row must
/// keep decoding. New traces also carry this shape (compiled from the
/// `ContextExecutionPlan`) so Settings diagnostics decode unchanged.
public struct ReaderContextPlan: Hashable, Codable, Sendable {
    public let intent: ReflectionIntent
    public let nearbyPassage: NearbyPassagePlan
    public let bookRetrieval: BookRetrievalPlan?
    public let pastThoughtRetrieval: PastThoughtRetrievalPlan?
    /// Evidence-only memory source (never a ReflectionConnection). Optional so
    /// pre-evolution plans decode; the validator defaults it on to preserve the
    /// current always-consulted behavior.
    public let memoryRetrieval: MemoryRetrievalPlan?
    public let responseGuidance: ResponseGuidance
    public let rationale: String?
    public init(intent: ReflectionIntent, nearbyPassage: NearbyPassagePlan,
                bookRetrieval: BookRetrievalPlan?, pastThoughtRetrieval: PastThoughtRetrievalPlan?,
                memoryRetrieval: MemoryRetrievalPlan? = nil,
                responseGuidance: ResponseGuidance, rationale: String? = nil) {
        self.intent = intent; self.nearbyPassage = nearbyPassage; self.bookRetrieval = bookRetrieval
        self.pastThoughtRetrieval = pastThoughtRetrieval; self.memoryRetrieval = memoryRetrieval
        self.responseGuidance = responseGuidance; self.rationale = rationale
    }
}

/// Optional per-reply context-pipeline metrics (small-to-big expansion, hybrid
/// reflection/memory retrieval, assembly). Every field is optional so traces
/// persisted before this evolution keep decoding (diagnostics() decodes all rows).
public struct ContextPipelineMetrics: Hashable, Codable, Sendable {
    public var retrievalMode: RetrievalMode?
    /// True when the planner provided a denseQuery distinct from the plain query.
    public var denseQueryCustomized: Bool?
    public var lexicalTermsCustomized: Bool?
    /// Book evidence units actually emitted (parent-anchored expanded windows).
    public var expandedEvidenceCount: Int?
    public var reflectionEvidenceCount: Int?
    public var memoryEvidenceCount: Int?
    /// Candidates removed by dedup in the assembly layer.
    public var deduplicatedCount: Int?
    public var contextTokenBudget: Int?
    public var actualContextTokens: Int?
    public var assemblyDurationSeconds: Double?
    public var semanticCacheHits: Int?
    public var semanticCacheMisses: Int?
    public var semanticUnavailable: Bool?

    public init() {}
}

public struct ContextBudget: Hashable, Codable, Sendable {
    public let totalCharacters: Int
    public let nearbyCharacters: Int
    public let bookEvidenceCharacters: Int
    public let pastThoughtCharacters: Int
    public let conversationCharacters: Int

    public init(totalCharacters: Int, nearbyCharacters: Int, bookEvidenceCharacters: Int,
                pastThoughtCharacters: Int, conversationCharacters: Int) {
        self.totalCharacters = totalCharacters
        self.nearbyCharacters = nearbyCharacters
        self.bookEvidenceCharacters = bookEvidenceCharacters
        self.pastThoughtCharacters = pastThoughtCharacters
        self.conversationCharacters = conversationCharacters
    }
}

/// Legacy validated-plan shape (planner schema v1). Kept as the persisted
/// trace representation of a `ContextExecutionPlan`; runtime code consumes the
/// execution plan directly.
public struct ValidatedContextPlan: Hashable, Codable, Sendable {
    public let intent: ReflectionIntent
    public let nearbyPassage: NearbyPassagePlan
    public let bookRetrieval: BookRetrievalPlan?
    public let pastThoughtRetrieval: PastThoughtRetrievalPlan?
    /// Optional so traces persisted before this evolution keep decoding; the
    /// assembly layer treats nil as "memory not planned" and defaults it on.
    public let memoryRetrieval: MemoryRetrievalPlan?
    public let responseGuidance: ResponseGuidance
    public let budget: ContextBudget
    public init(intent: ReflectionIntent, nearbyPassage: NearbyPassagePlan,
                bookRetrieval: BookRetrievalPlan?, pastThoughtRetrieval: PastThoughtRetrievalPlan?,
                memoryRetrieval: MemoryRetrievalPlan? = nil,
                responseGuidance: ResponseGuidance, budget: ContextBudget) {
        self.intent = intent; self.nearbyPassage = nearbyPassage; self.bookRetrieval = bookRetrieval
        self.pastThoughtRetrieval = pastThoughtRetrieval; self.memoryRetrieval = memoryRetrieval
        self.responseGuidance = responseGuidance; self.budget = budget
    }
}

public enum RoutingFallbackReason: String, Hashable, Codable, Sendable { case invalidStructuredOutput, modelFailure }
public struct ContextRoutingResult: Hashable, Sendable {
    /// The strict semantic plan (v2): either decoded from the LLM's wire plan or
    /// produced by the deterministic fallback. Both flow through the same
    /// validator + policy compiler.
    public let plan: SemanticContextPlan
    public let usedFallback: Bool
    public let fallbackReason: RoutingFallbackReason?
    /// Granular fallback cause (e.g. the underlying `AgentFailure` name) when
    /// the coarse `fallbackReason` is not enough. Kept as text so routing stays
    /// independent of the AgentRuntime error type's identity.
    public let fallbackDetail: String?
    public let tokenUsage: TokenUsage?
    /// Model calls spent decoding the plan (1 = clean decode, 2 = repair used).
    /// Feeds repair/fallback-rate observability without expanding retries.
    public let decodeAttempts: Int?

    public init(
        plan: SemanticContextPlan,
        usedFallback: Bool,
        fallbackReason: RoutingFallbackReason?,
        fallbackDetail: String? = nil,
        tokenUsage: TokenUsage? = nil,
        decodeAttempts: Int? = nil
    ) {
        self.plan = plan
        self.usedFallback = usedFallback
        self.fallbackReason = fallbackReason
        self.fallbackDetail = fallbackDetail
        self.tokenUsage = tokenUsage
        self.decodeAttempts = decodeAttempts
    }
}

/// Seconds extracted from a `Duration` for trace encoding and diagnostics.
/// Internal to ContextRouting; other modules use `ContextPlanTrace`/`RoutingTraceDiagnostics`.
extension Duration {
    var seconds: Double {
        let components = self.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

/// Immutable record of one Reader Agent reply's context-planning decisions and
/// timing. Persisted as derived observability data — it intentionally stores plan
/// summaries, statistics, durations, evidence IDs and token usage, never raw
/// user text or the full Reflection body (ADR 0001).
///
/// Plan snapshots keep the v1 persisted shapes (`ReaderContextPlan` /
/// `ValidatedContextPlan`) so every historical row keeps decoding; v2 adds the
/// schema version, the validator's corrections and the router's decode-attempt
/// count as optional fields (nil on legacy rows).
public struct ContextPlanTrace: Hashable, Codable, Sendable {
    public let id: UUID
    /// `ReflectionID.description` of the reflection being replied to.
    public let reflectionID: String
    public let createdAt: Date
    /// Raw plan produced by the router (may have been rejected by the validator).
    public let proposedPlan: ReaderContextPlan?
    /// Plan actually used to assemble context.
    public let validatedPlan: ValidatedContextPlan
    public let usedFallback: Bool
    public let fallbackReason: RoutingFallbackReason?
    public let fallbackDetail: String?
    public let routingDuration: Duration
    public let retrievalDuration: Duration
    public let replyDuration: Duration
    /// `BookChunkID.rawValue` for the book evidence actually selected.
    public let selectedBookEvidenceIDs: [String]
    /// `ReflectionID.description` of the linked past thought, if any.
    public let connectedReflectionID: String?
    public let routingTokenUsage: TokenUsage?
    public let replyTokenUsage: TokenUsage?
    public let pipelineMetrics: ContextPipelineMetrics?
    /// Planner wire-schema version (v2 onward); nil on legacy rows.
    public let planSchemaVersion: Int?
    /// Corrections `SemanticPlanValidator` applied to the proposed plan.
    public let validationCorrections: [String]?
    /// Model calls the router spent decoding the plan (1 = clean, 2 = repaired).
    public let routingDecodeAttempts: Int?

    public init(
        id: UUID = UUID(),
        reflectionID: String,
        createdAt: Date = Date(),
        proposedPlan: ReaderContextPlan?,
        validatedPlan: ValidatedContextPlan,
        usedFallback: Bool,
        fallbackReason: RoutingFallbackReason?,
        fallbackDetail: String? = nil,
        routingDuration: Duration,
        retrievalDuration: Duration,
        replyDuration: Duration,
        selectedBookEvidenceIDs: [String],
        connectedReflectionID: String? = nil,
        routingTokenUsage: TokenUsage? = nil,
        replyTokenUsage: TokenUsage? = nil,
        pipelineMetrics: ContextPipelineMetrics? = nil,
        planSchemaVersion: Int? = nil,
        validationCorrections: [String]? = nil,
        routingDecodeAttempts: Int? = nil
    ) {
        self.id = id
        self.reflectionID = reflectionID
        self.createdAt = createdAt
        self.proposedPlan = proposedPlan
        self.validatedPlan = validatedPlan
        self.usedFallback = usedFallback
        self.fallbackReason = fallbackReason
        self.fallbackDetail = fallbackDetail
        self.routingDuration = routingDuration
        self.retrievalDuration = retrievalDuration
        self.replyDuration = replyDuration
        self.selectedBookEvidenceIDs = selectedBookEvidenceIDs
        self.connectedReflectionID = connectedReflectionID
        self.routingTokenUsage = routingTokenUsage
        self.replyTokenUsage = replyTokenUsage
        self.pipelineMetrics = pipelineMetrics
        self.planSchemaVersion = planSchemaVersion
        self.validationCorrections = validationCorrections
        self.routingDecodeAttempts = routingDecodeAttempts
    }
}

extension ContextPlanTrace {
    private enum CodingKeys: String, CodingKey {
        case id, reflectionID, createdAt, proposedPlan, validatedPlan, usedFallback
        case fallbackReason, fallbackDetail
        case routingDurationSeconds, retrievalDurationSeconds, replyDurationSeconds
        case selectedBookEvidenceIDs, connectedReflectionID, routingTokenUsage, replyTokenUsage
        case pipelineMetrics
        case planSchemaVersion, validationCorrections, routingDecodeAttempts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        reflectionID = try container.decode(String.self, forKey: .reflectionID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        proposedPlan = try container.decodeIfPresent(ReaderContextPlan.self, forKey: .proposedPlan)
        validatedPlan = try container.decode(ValidatedContextPlan.self, forKey: .validatedPlan)
        usedFallback = try container.decode(Bool.self, forKey: .usedFallback)
        fallbackReason = try container.decodeIfPresent(RoutingFallbackReason.self, forKey: .fallbackReason)
        fallbackDetail = try container.decodeIfPresent(String.self, forKey: .fallbackDetail)
        routingDuration = .seconds(try container.decode(Double.self, forKey: .routingDurationSeconds))
        retrievalDuration = .seconds(try container.decode(Double.self, forKey: .retrievalDurationSeconds))
        replyDuration = .seconds(try container.decode(Double.self, forKey: .replyDurationSeconds))
        selectedBookEvidenceIDs = try container.decode([String].self, forKey: .selectedBookEvidenceIDs)
        connectedReflectionID = try container.decodeIfPresent(String.self, forKey: .connectedReflectionID)
        routingTokenUsage = try container.decodeIfPresent(TokenUsage.self, forKey: .routingTokenUsage)
        replyTokenUsage = try container.decodeIfPresent(TokenUsage.self, forKey: .replyTokenUsage)
        pipelineMetrics = try container.decodeIfPresent(ContextPipelineMetrics.self, forKey: .pipelineMetrics)
        planSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .planSchemaVersion)
        validationCorrections = try container.decodeIfPresent([String].self, forKey: .validationCorrections)
        routingDecodeAttempts = try container.decodeIfPresent(Int.self, forKey: .routingDecodeAttempts)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(reflectionID, forKey: .reflectionID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(proposedPlan, forKey: .proposedPlan)
        try container.encode(validatedPlan, forKey: .validatedPlan)
        try container.encode(usedFallback, forKey: .usedFallback)
        try container.encodeIfPresent(fallbackReason, forKey: .fallbackReason)
        try container.encodeIfPresent(fallbackDetail, forKey: .fallbackDetail)
        try container.encode(routingDuration.seconds, forKey: .routingDurationSeconds)
        try container.encode(retrievalDuration.seconds, forKey: .retrievalDurationSeconds)
        try container.encode(replyDuration.seconds, forKey: .replyDurationSeconds)
        try container.encode(selectedBookEvidenceIDs, forKey: .selectedBookEvidenceIDs)
        try container.encodeIfPresent(connectedReflectionID, forKey: .connectedReflectionID)
        try container.encodeIfPresent(routingTokenUsage, forKey: .routingTokenUsage)
        try container.encodeIfPresent(replyTokenUsage, forKey: .replyTokenUsage)
        try container.encodeIfPresent(pipelineMetrics, forKey: .pipelineMetrics)
        try container.encodeIfPresent(planSchemaVersion, forKey: .planSchemaVersion)
        try container.encodeIfPresent(validationCorrections, forKey: .validationCorrections)
        try container.encodeIfPresent(routingDecodeAttempts, forKey: .routingDecodeAttempts)
    }
}

/// Aggregated routing observability used by the Settings diagnostics screen.
/// Computed on demand from stored traces (personal-app trace volume is small).
public struct RoutingTraceDiagnostics: Hashable, Sendable {
    public let totalTraces: Int
    /// Fallback counts keyed by `fallbackDetail` (e.g. "network", "rateLimited"),
    /// falling back to the coarse `fallbackReason`.
    public let fallbackCounts: [String: Int]
    public let averageRoutingDuration: Duration?
    public let averageRetrievalDuration: Duration?
    public let averageReplyDuration: Duration?

    public init(traces: [ContextPlanTrace]) {
        totalTraces = traces.count
        var counts: [String: Int] = [:]
        for trace in traces where trace.usedFallback {
            let key = trace.fallbackDetail ?? trace.fallbackReason?.rawValue ?? "unknown"
            counts[key, default: 0] += 1
        }
        fallbackCounts = counts
        averageRoutingDuration = Self.average(\.routingDuration, in: traces)
        averageRetrievalDuration = Self.average(\.retrievalDuration, in: traces)
        averageReplyDuration = Self.average(\.replyDuration, in: traces)
    }

    private static func average(_ keyPath: KeyPath<ContextPlanTrace, Duration>, in traces: [ContextPlanTrace]) -> Duration? {
        guard !traces.isEmpty else { return nil }
        let total = traces.reduce(0.0) { $0 + $1[keyPath: keyPath].seconds }
        return .seconds(total / Double(traces.count))
    }
}

/// Persists derived routing traces. Protocol lives with its primary type so the
/// Reader Agent can depend on it without pulling persistence/GRDB into its graph.
public protocol RoutingTraceRepository: Sendable {
    func save(_ trace: ContextPlanTrace) async throws
    func latestTrace(for reflectionID: String) async throws -> ContextPlanTrace?
    func diagnostics() async throws -> RoutingTraceDiagnostics
    /// Most recent traces, newest first. Powers the per-route diagnostics list
    /// (fallback reason/detail are only persisted per trace, never aggregated).
    func recentTraces(limit: Int) async throws -> [ContextPlanTrace]
}

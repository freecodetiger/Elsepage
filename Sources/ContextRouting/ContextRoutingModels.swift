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
    public init(query: String, purpose: RetrievalPurpose, preferredScope: PreferredBookScope, maximumEvidenceCount: Int) {
        self.query = query; self.purpose = purpose; self.preferredScope = preferredScope; self.maximumEvidenceCount = maximumEvidenceCount
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

public struct ResponseGuidance: Hashable, Codable, Sendable {
    public let targetLength: ResponseLength
    public let allowQuestion: Bool
    public let shouldNaturallyEnd: Bool
    public init(targetLength: ResponseLength, allowQuestion: Bool, shouldNaturallyEnd: Bool) {
        self.targetLength = targetLength; self.allowQuestion = allowQuestion; self.shouldNaturallyEnd = shouldNaturallyEnd
    }
}

public struct ReaderContextPlan: Hashable, Codable, Sendable {
    public let intent: ReflectionIntent
    public let nearbyPassage: NearbyPassagePlan
    public let bookRetrieval: BookRetrievalPlan?
    public let pastThoughtRetrieval: PastThoughtRetrievalPlan?
    public let responseGuidance: ResponseGuidance
    public let rationale: String?
    public init(intent: ReflectionIntent, nearbyPassage: NearbyPassagePlan,
                bookRetrieval: BookRetrievalPlan?, pastThoughtRetrieval: PastThoughtRetrievalPlan?,
                responseGuidance: ResponseGuidance, rationale: String? = nil) {
        self.intent = intent; self.nearbyPassage = nearbyPassage; self.bookRetrieval = bookRetrieval
        self.pastThoughtRetrieval = pastThoughtRetrieval; self.responseGuidance = responseGuidance; self.rationale = rationale
    }
}

public struct ContextBudget: Hashable, Codable, Sendable {
    public let totalCharacters: Int
    public let nearbyCharacters: Int
    public let bookEvidenceCharacters: Int
    public let pastThoughtCharacters: Int
    public let conversationCharacters: Int
}

public struct ValidatedContextPlan: Hashable, Codable, Sendable {
    public let intent: ReflectionIntent
    public let nearbyPassage: NearbyPassagePlan
    public let bookRetrieval: BookRetrievalPlan?
    public let pastThoughtRetrieval: PastThoughtRetrievalPlan?
    public let responseGuidance: ResponseGuidance
    public let budget: ContextBudget
}

public enum RoutingFallbackReason: String, Hashable, Codable, Sendable { case invalidStructuredOutput, modelFailure }
public struct ContextRoutingResult: Hashable, Sendable {
    public let plan: ReaderContextPlan
    public let usedFallback: Bool
    public let fallbackReason: RoutingFallbackReason?
    /// Granular fallback cause (e.g. the underlying `AgentFailure` name) when
    /// the coarse `fallbackReason` is not enough. Kept as text so routing stays
    /// independent of the AgentRuntime error type's identity.
    public let fallbackDetail: String?
    public let tokenUsage: TokenUsage?

    public init(
        plan: ReaderContextPlan,
        usedFallback: Bool,
        fallbackReason: RoutingFallbackReason?,
        fallbackDetail: String? = nil,
        tokenUsage: TokenUsage? = nil
    ) {
        self.plan = plan
        self.usedFallback = usedFallback
        self.fallbackReason = fallbackReason
        self.fallbackDetail = fallbackDetail
        self.tokenUsage = tokenUsage
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
        replyTokenUsage: TokenUsage? = nil
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
    }
}

extension ContextPlanTrace {
    private enum CodingKeys: String, CodingKey {
        case id, reflectionID, createdAt, proposedPlan, validatedPlan, usedFallback
        case fallbackReason, fallbackDetail
        case routingDurationSeconds, retrievalDurationSeconds, replyDurationSeconds
        case selectedBookEvidenceIDs, connectedReflectionID, routingTokenUsage, replyTokenUsage
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
}

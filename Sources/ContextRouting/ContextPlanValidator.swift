import Foundation

public struct ContextPlanValidator: Sendable {
    public init() {}

    public func validate(_ proposed: ReaderContextPlan, input: ContextRoutingInput) -> ValidatedContextPlan {
        let nearby: NearbyPassagePlan = input.availableSources.hasNearbyPassage && proposed.nearbyPassage == .include ? .include : .omit
        let book = validatedBookPlan(proposed.bookRetrieval, input: input)
        let past = validatedPastPlan(proposed.pastThoughtRetrieval, input: input)
        let forceStop = input.previousAgentAskedQuestion
        let requestedLength: ResponseLength = input.interactionMode == .reflection && proposed.responseGuidance.targetLength == .long
            ? .medium : proposed.responseGuidance.targetLength
        let guidance = ResponseGuidance(
            targetLength: requestedLength,
            allowQuestion: forceStop ? false : proposed.responseGuidance.allowQuestion,
            shouldNaturallyEnd: forceStop ? true : proposed.responseGuidance.shouldNaturallyEnd
        )
        return ValidatedContextPlan(intent: proposed.intent, nearbyPassage: nearby,
            bookRetrieval: book, pastThoughtRetrieval: past,
            memoryRetrieval: validatedMemoryPlan(proposed.memoryRetrieval, input: input),
            responseGuidance: guidance, budget: Self.budget(for: proposed.intent))
    }

    private func validatedBookPlan(_ plan: BookRetrievalPlan?, input: ContextRoutingInput) -> BookRetrievalPlan? {
        guard let plan, input.availableSources.hasBookIndex,
              input.currentReading?.hasCurrentLocator == true,
              let query = Self.query(plan.query) else { return nil }
        // denseQuery/lexicalTerms default to the (trimmed) query when the planner
        // omitted them; retrieval knobs stay optional and are defaulted/clamped at
        // the assembly layer.
        return BookRetrievalPlan(
            query: query, purpose: plan.purpose, preferredScope: plan.preferredScope,
            maximumEvidenceCount: min(4, max(1, plan.maximumEvidenceCount)),
            denseQuery: plan.denseQuery.flatMap(Self.query) ?? Self.query(query),
            lexicalTerms: plan.lexicalTerms.flatMap(Self.query) ?? Self.query(query),
            retrievalMode: plan.retrievalMode,
            candidateLimit: plan.candidateLimit,
            useReranker: plan.useReranker,
            expansionMode: plan.expansionMode,
            expansionMaxTokens: plan.expansionMaxTokens
        )
    }

    private func validatedMemoryPlan(_ plan: MemoryRetrievalPlan?, input: ContextRoutingInput) -> MemoryRetrievalPlan? {
        // Pass the planner's memory request through (clamped). No default injection:
        // the assembly layer decides whether to consult memory when the plan omits it,
        // and doing it there keeps user-derived query text out of routingTraces (ADR 0001).
        guard let plan, let query = Self.query(plan.query) else { return nil }
        return MemoryRetrievalPlan(query: query, maximumEvidenceCount: min(4, max(1, plan.maximumEvidenceCount)))
    }

    private func validatedPastPlan(_ plan: PastThoughtRetrievalPlan?, input: ContextRoutingInput) -> PastThoughtRetrievalPlan? {
        guard let plan, input.availableSources.hasPastThoughts,
              let query = Self.query(plan.query) else { return nil }
        return PastThoughtRetrievalPlan(query: query, purpose: plan.purpose, maximumEvidenceCount: 1)
    }

    private static func query(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(240))
    }

    private static func budget(for intent: ReflectionIntent) -> ContextBudget {
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
}

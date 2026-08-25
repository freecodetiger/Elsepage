import AgentRuntime
import ContextRouting
import Foundation
import LibraryCore
import Testing

@Test func validatorEnforcesReadBoundarySourceAndQuestionPolicies() {
    let proposal = ReaderContextPlan(
        intent: .personalConnection,
        nearbyPassage: .include,
        bookRetrieval: .init(query: String(repeating: "x", count: 400), purpose: .traceConcept, preferredScope: .readSoFar, maximumEvidenceCount: 99),
        pastThoughtRetrieval: .init(query: "过去的想法", purpose: .findContinuation, maximumEvidenceCount: 20),
        responseGuidance: .init(targetLength: .medium, allowQuestion: true, shouldNaturallyEnd: false)
    )
    let input = routingInput(hasLocator: false, hasPastThoughts: false, previousAgentAskedQuestion: true)
    let validated = ContextPlanValidator().validate(proposal, input: input)
    #expect(validated.bookRetrieval == nil)
    #expect(validated.pastThoughtRetrieval == nil)
    #expect(validated.responseGuidance.allowQuestion == false)
    #expect(validated.responseGuidance.shouldNaturallyEnd)
}

@Test func validatorClampsQueriesEvidenceCountsAndContextBudget() {
    let proposal = ReaderContextPlan(
        intent: .authorDisagreement,
        nearbyPassage: .include,
        bookRetrieval: .init(query: "  作者从前提走到结论的推理  ", purpose: .clarifyCurrentPassage, preferredScope: .currentChapter, maximumEvidenceCount: 50),
        pastThoughtRetrieval: .init(query: "长期问题", purpose: .findChange, maximumEvidenceCount: 9),
        responseGuidance: .init(targetLength: .long, allowQuestion: true, shouldNaturallyEnd: false)
    )
    let validated = ContextPlanValidator().validate(proposal, input: routingInput())
    #expect(validated.bookRetrieval?.maximumEvidenceCount == 4)
    #expect(validated.pastThoughtRetrieval?.maximumEvidenceCount == 1)
    #expect(validated.bookRetrieval?.query == "作者从前提走到结论的推理")
    #expect(validated.budget.totalCharacters == 6_000)
    #expect(validated.budget.bookEvidenceCharacters <= validated.budget.totalCharacters)
}

@Test func llmRouterDecodesStrictPlanAndFallsBackOnMarkdownOrFailure() async {
    let json = """
    {"intent":"passageObservation","nearbyPassage":"include","bookRetrieval":{"query":"自由与责任","purpose":"findEarlierContrast","preferredScope":"readSoFar","maximumEvidenceCount":2},"pastThoughtRetrieval":null,"responseGuidance":{"targetLength":"short","allowQuestion":false,"shouldNaturallyEnd":true},"rationale":"需要对照已读段落"}
    """
    let validClient = FakeModelClient(events: [.completed(.init(content: json))])
    let router = LLMReaderContextRouter()
    let routed = await router.route(routingInput(), using: validClient)
    #expect(routed.usedFallback == false)
    #expect(routed.plan.bookRetrieval?.query == "自由与责任")

    let markdownClient = FakeModelClient(events: [.completed(.init(content: "```json\n\(json)\n```"))])
    let fallback = await router.route(routingInput(), using: markdownClient)
    #expect(fallback.usedFallback)
    #expect(fallback.fallbackReason == .invalidStructuredOutput)

    let failedClient = FakeModelClient(events: [], terminalFailure: .network)
    let failed = await router.route(routingInput(), using: failedClient)
    #expect(failed.usedFallback)
    #expect(failed.fallbackReason == .modelFailure)
    #expect(failed.fallbackDetail == "network")
}

@Test func llmRouterPropagatesRateLimitedAndBudgetFailuresAsFallbackDetail() async {
    let router = LLMReaderContextRouter()
    for (failure, expected) in [
        (ModelFailure.rateLimited, "rateLimited"),
        (ModelFailure.authentication, "authentication"),
    ] {
        let result = await router.route(routingInput(), using: FakeModelClient(events: [], terminalFailure: failure))
        #expect(result.usedFallback)
        #expect(result.fallbackDetail == expected)
    }
}

@Test func contextPlanTraceRoundTripsThroughCodable() throws {
    let proposed = ReaderContextPlan(
        intent: .conceptualQuestion,
        nearbyPassage: .include,
        bookRetrieval: .init(query: "自由与责任", purpose: .traceConcept, preferredScope: .readSoFar, maximumEvidenceCount: 3),
        pastThoughtRetrieval: nil,
        responseGuidance: .init(targetLength: .medium, allowQuestion: true, shouldNaturallyEnd: false),
        rationale: "对照已读段落"
    )
    let validated = ContextPlanValidator().validate(proposed, input: routingInput())
    let trace = ContextPlanTrace(
        reflectionID: "ref-1",
        proposedPlan: proposed,
        validatedPlan: validated,
        usedFallback: true,
        fallbackReason: .modelFailure,
        fallbackDetail: "network",
        routingDuration: .seconds(0.125),
        retrievalDuration: .seconds(0.35),
        replyDuration: .seconds(2),
        selectedBookEvidenceIDs: ["chunk-1", "chunk-2"],
        connectedReflectionID: "ref-0",
        routingTokenUsage: .init(inputTokens: 100, outputTokens: 20, totalTokens: 120),
        replyTokenUsage: .init(inputTokens: 500, outputTokens: 200, totalTokens: 700)
    )
    let decoded = try JSONDecoder().decode(ContextPlanTrace.self, from: JSONEncoder().encode(trace))
    #expect(decoded.reflectionID == "ref-1")
    #expect(decoded.validatedPlan.intent == .conceptualQuestion)
    #expect(decoded.proposedPlan?.bookRetrieval?.query == "自由与责任")
    #expect(decoded.usedFallback)
    #expect(decoded.fallbackDetail == "network")
    #expect(decoded.selectedBookEvidenceIDs == ["chunk-1", "chunk-2"])
    #expect(decoded.connectedReflectionID == "ref-0")
    #expect(decoded.replyTokenUsage?.totalTokens == 700)
    #expect(decoded.routingDuration == .seconds(0.125))
    #expect(decoded.retrievalDuration == .seconds(0.35))
    #expect(decoded.replyDuration == .seconds(2))
}

@Test func routingTraceDiagnosticsAggregateFallbacksAndAverages() throws {
    func trace(_ id: String, usedFallback: Bool, detail: String?, seconds: [Double]) -> ContextPlanTrace {
        let proposed = ReaderContextPlan(
            intent: .passageObservation, nearbyPassage: .include, bookRetrieval: nil,
            pastThoughtRetrieval: nil,
            responseGuidance: .init(targetLength: .short, allowQuestion: false, shouldNaturallyEnd: true)
        )
        let validated = ContextPlanValidator().validate(proposed, input: routingInput(hasLocator: true, hasPastThoughts: true))
        return ContextPlanTrace(
            reflectionID: id,
            proposedPlan: proposed,
            validatedPlan: validated,
            usedFallback: usedFallback,
            fallbackReason: usedFallback ? .modelFailure : nil,
            fallbackDetail: detail,
            routingDuration: .seconds(seconds[0]),
            retrievalDuration: .seconds(seconds[1]),
            replyDuration: .seconds(seconds[2]),
            selectedBookEvidenceIDs: [],
            connectedReflectionID: nil
        )
    }
    let diagnostics = RoutingTraceDiagnostics(traces: [
        trace("a", usedFallback: true, detail: "network", seconds: [0.5, 1.0, 2.0]),
        trace("b", usedFallback: true, detail: "rateLimited", seconds: [0.25, 0.5, 1.0]),
        trace("c", usedFallback: false, detail: nil, seconds: [0.1, 0.2, 0.3]),
    ])
    #expect(diagnostics.totalTraces == 3)
    #expect(diagnostics.fallbackCounts == ["network": 1, "rateLimited": 1])
    let routing = try #require(diagnostics.averageRoutingDuration)
    #expect(abs(durationSeconds(routing) - 0.2833) < 0.001)
    let reply = try #require(diagnostics.averageReplyDuration)
    #expect(abs(durationSeconds(reply) - 1.1) < 0.001)
}

private func durationSeconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
}

private func routingInput(
    hasLocator: Bool = true,
    hasPastThoughts: Bool = true,
    previousAgentAskedQuestion: Bool = false
) -> ContextRoutingInput {
    ContextRoutingInput(
        interactionMode: .reflection,
        currentReflection: "我开始怀疑自由是不是越多越好",
        recentConversation: [],
        currentReading: .init(bookID: BookID(), chapterTitle: "第一章", selectedText: "自由", nearbyTextPreview: "自由与责任", hasCurrentLocator: hasLocator),
        availableSources: .init(hasNearbyPassage: hasLocator, hasBookIndex: true, hasPastThoughts: hasPastThoughts),
        previousAgentAskedQuestion: previousAgentAskedQuestion
    )
}

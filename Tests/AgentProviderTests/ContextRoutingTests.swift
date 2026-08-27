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

@Test func llmRouterDecodesPlanStripsFencesAndFallsBackOnBadOrFailedOutput() async {
    let json = """
    {"intent":"passageObservation","nearbyPassage":"include","bookRetrieval":{"query":"自由与责任","purpose":"findEarlierContrast","preferredScope":"readSoFar","maximumEvidenceCount":2},"pastThoughtRetrieval":null,"responseGuidance":{"targetLength":"short","allowQuestion":false,"shouldNaturallyEnd":true},"rationale":"需要对照已读段落"}
    """
    let validClient = FakeModelClient(events: [.completed(.init(content: json))])
    let router = LLMReaderContextRouter()
    let routed = await router.route(routingInput(), using: validClient)
    #expect(routed.usedFallback == false)
    #expect(routed.plan.bookRetrieval?.query == "自由与责任")

    // A code-fenced JSON is recovered by stripping the fence — not a fallback.
    let markdownClient = FakeModelClient(events: [.completed(.init(content: "```json\n\(json)\n```"))])
    let fenced = await router.route(routingInput(), using: markdownClient)
    #expect(fenced.usedFallback == false)
    #expect(fenced.plan.bookRetrieval?.query == "自由与责任")

    // Genuinely unparseable content still falls back with a traceable reason.
    let garbageClient = FakeModelClient(events: [.completed(.init(content: "不是 JSON"))])
    let garbage = await router.route(routingInput(), using: garbageClient)
    #expect(garbage.usedFallback)
    #expect(garbage.fallbackReason == .invalidStructuredOutput)

    let failedClient = FakeModelClient(events: [], terminalFailure: .network)
    let failed = await router.route(routingInput(), using: failedClient)
    #expect(failed.usedFallback)
    #expect(failed.fallbackReason == .modelFailure)
    #expect(failed.fallbackDetail == "network")
}

@Test func llmRouterRequestsJSONModeOnlyWhenProviderSupportsStructuredOutput() async {
    let json = """
    {"intent":"passageObservation","nearbyPassage":"include","bookRetrieval":null,"pastThoughtRetrieval":null,"responseGuidance":{"targetLength":"short","allowQuestion":false,"shouldNaturallyEnd":true},"rationale":null}
    """
    let recorder = RequestRecorder()
    let supported = RecordingModelClient(
        descriptor: .init(provider: "openai", model: "m", capabilities: .init(supportsStructuredOutput: true)),
        response: .init(content: json),
        onRequest: { recorder.record($0) }
    )
    _ = await LLMReaderContextRouter().route(routingInput(), using: supported)
    #expect(recorder.all().first?.responseFormat == .jsonObject)

    let plain = RecordingModelClient(
        descriptor: .init(provider: "openai", model: "m", capabilities: .init()),
        response: .init(content: json),
        onRequest: { recorder.record($0) }
    )
    _ = await LLMReaderContextRouter().route(routingInput(), using: plain)
    #expect(recorder.all().last?.responseFormat == nil)
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

@Test func oldShapeTraceDecodesWhenContextPlanGainsOptionalFields() throws {
    // A trace persisted before the context-engineering plan evolution — no
    // denseQuery/lexicalTerms/retrieval knobs, no memoryRetrieval. It must still
    // decode so Settings diagnostics survive upgrades (diagnostics() decodes all rows).
    let json = """
    {
      "id": "00000000-0000-0000-0000-000000000001",
      "reflectionID": "ref-1",
      "createdAt": 750000000,
      "proposedPlan": {"intent":"passageObservation","nearbyPassage":"include","bookRetrieval":null,"pastThoughtRetrieval":null,"responseGuidance":{"targetLength":"short","allowQuestion":false,"shouldNaturallyEnd":true},"rationale":null},
      "validatedPlan": {"intent":"passageObservation","nearbyPassage":"include","bookRetrieval":null,"pastThoughtRetrieval":null,"responseGuidance":{"targetLength":"short","allowQuestion":false,"shouldNaturallyEnd":true},"budget":{"totalCharacters":6000,"nearbyCharacters":1200,"bookEvidenceCharacters":2200,"pastThoughtCharacters":800,"conversationCharacters":1400}},
      "usedFallback": false,
      "fallbackReason": null,
      "fallbackDetail": null,
      "routingDurationSeconds": 0.1,
      "retrievalDurationSeconds": 0.2,
      "replyDurationSeconds": 0.3,
      "selectedBookEvidenceIDs": [],
      "connectedReflectionID": null,
      "routingTokenUsage": null,
      "replyTokenUsage": null
    }
    """
    let trace = try JSONDecoder().decode(ContextPlanTrace.self, from: Data(json.utf8))
    #expect(trace.reflectionID == "ref-1")
    #expect(trace.proposedPlan?.memoryRetrieval == nil)
    #expect(trace.validatedPlan.memoryRetrieval == nil)
    #expect(trace.validatedPlan.bookRetrieval == nil)
    #expect(trace.validatedPlan.budget.totalCharacters == 6_000)
}

@Test func validatorResolvesDenseLexicalDefaultsButDoesNotInjectMemory() {
    let proposal = ReaderContextPlan(
        intent: .passageObservation,
        nearbyPassage: .include,
        bookRetrieval: .init(query: "自由与责任", purpose: .clarifyCurrentPassage, preferredScope: .readSoFar, maximumEvidenceCount: 3),
        pastThoughtRetrieval: nil,
        responseGuidance: .init(targetLength: .short, allowQuestion: false, shouldNaturallyEnd: true)
    )
    let validated = ContextPlanValidator().validate(proposal, input: routingInput())
    #expect(validated.bookRetrieval?.denseQuery == "自由与责任")
    #expect(validated.bookRetrieval?.lexicalTerms == "自由与责任")
    // Omitted memory must NOT default to currentReflection: that would persist raw
    // user text into routingTraces (ADR 0001). The assembly layer owns the default.
    #expect(validated.memoryRetrieval == nil)
}

@Test func validatorCarriesExplicitRetrievalConfigAndClampsMemoryCount() {
    let proposal = ReaderContextPlan(
        intent: .conceptualQuestion,
        nearbyPassage: .include,
        bookRetrieval: .init(
            query: "作者对自由的态度", purpose: .traceConcept, preferredScope: .currentChapter, maximumEvidenceCount: 2,
            denseQuery: "  作者如何看待自由与责任的张力  ", lexicalTerms: "自由 责任 作者",
            retrievalMode: .hybrid, candidateLimit: 12, useReranker: false
        ),
        pastThoughtRetrieval: nil,
        memoryRetrieval: .init(query: "自由观", maximumEvidenceCount: 99),
        responseGuidance: .init(targetLength: .medium, allowQuestion: true, shouldNaturallyEnd: false)
    )
    let validated = ContextPlanValidator().validate(proposal, input: routingInput())
    let book = validated.bookRetrieval
    #expect(book?.denseQuery == "作者如何看待自由与责任的张力")
    #expect(book?.lexicalTerms == "自由 责任 作者")
    #expect(book?.retrievalMode == .hybrid)
    #expect(book?.candidateLimit == 12)
    #expect(book?.useReranker == false)
    #expect(validated.memoryRetrieval?.query == "自由观")
    #expect(validated.memoryRetrieval?.maximumEvidenceCount == 4)  // clamped 1...4
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

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [ModelRequest] = []
    func record(_ request: ModelRequest) { lock.withLock { stored.append(request) } }
    func all() -> [ModelRequest] { lock.withLock { stored } }
}

private struct RecordingModelClient: ModelClient {
    let descriptor: ModelDescriptor
    let response: ModelResponse
    let onRequest: @Sendable (ModelRequest) -> Void
    func stream(request: ModelRequest) -> AsyncThrowingStream<ModelEvent, Error> {
        onRequest(request)
        return AsyncThrowingStream { continuation in
            continuation.yield(.completed(response))
            continuation.finish()
        }
    }
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

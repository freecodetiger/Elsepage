import AgentRuntime
import ContextRouting
import Foundation
import LibraryCore
import Testing

// MARK: - Fixtures

private let v2PlanJSON = """
{"intent":"passageObservation","nearbyPassage":"include","bookRetrieval":{"query":"自由与责任","purpose":"findEarlierContrast","scope":"readSoFar"},"pastThoughtRetrieval":null,"response":{"length":"short","posture":"respondOnly"}}
"""

private func routingInput(
    hasLocator: Bool = true,
    hasPastThoughts: Bool = true,
    previousAgentAskedQuestion: Bool = false,
    interactionMode: ReaderInteractionMode = .reflection
) -> ContextRoutingInput {
    ContextRoutingInput(
        interactionMode: interactionMode,
        currentReflection: "我开始怀疑自由是不是越多越好",
        recentConversation: [],
        currentReading: .init(bookID: BookID(), chapterTitle: "第一章", selectedText: "自由", nearbyTextPreview: "自由与责任", hasCurrentLocator: hasLocator),
        availableSources: .init(hasNearbyPassage: hasLocator, hasBookIndex: true, hasPastThoughts: hasPastThoughts),
        previousAgentAskedQuestion: previousAgentAskedQuestion
    )
}

// MARK: - A. Schema / decoding

@Test func llmRouterDecodesV2PlanStripsFencesAndFallsBackOnBadOrFailedOutput() async {
    let validClient = FakeModelClient(events: [.completed(.init(content: v2PlanJSON))])
    let router = LLMReaderContextRouter()
    let routed = await router.route(routingInput(), using: validClient)
    #expect(routed.usedFallback == false)
    #expect(routed.plan.bookRequest?.query == "自由与责任")
    #expect(routed.plan.pastThoughtRequest == nil, "absent request means not planned")
    #expect(routed.plan.nearbyRequested)

    // A code-fenced JSON is recovered by stripping the fence — not a fallback.
    let markdownClient = FakeModelClient(events: [.completed(.init(content: "```json\n\(v2PlanJSON)\n```"))])
    let fenced = await router.route(routingInput(), using: markdownClient)
    #expect(fenced.usedFallback == false)
    #expect(fenced.plan.bookRequest?.query == "自由与责任")

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
    let recorder = RequestRecorder()
    let supported = RecordingModelClient(
        descriptor: .init(provider: "openai", model: "m", capabilities: .init(supportsStructuredOutput: true)),
        response: .init(content: v2PlanJSON),
        onRequest: { recorder.record($0) }
    )
    _ = await LLMReaderContextRouter().route(routingInput(), using: supported)
    #expect(recorder.all().first?.responseFormat == .jsonObject)

    let plain = RecordingModelClient(
        descriptor: .init(provider: "openai", model: "m", capabilities: .init()),
        response: .init(content: v2PlanJSON),
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

@Test func invalidEnumValueRejectsTheWholePlanAndFallsBack() async {
    let offSchemaJSON = """
    {"intent":"passageObservation","nearbyPassage":"sometimes","bookRetrieval":null,"response":{"length":"short","posture":"respondOnly"}}
    """
    let client = FakeModelClient(events: [.completed(.init(content: offSchemaJSON))])
    let result = await LLMReaderContextRouter().route(routingInput(), using: client)
    #expect(result.usedFallback, "closed enums are validated by the decoder, not the prompt")
    #expect(result.fallbackReason == .invalidStructuredOutput)
}

@Test func everyTaggedRequestVariantDecodesIntoTheDomainModel() throws {
    let json = """
    {"intent":"conceptualQuestion","nearbyPassage":"omit",
     "bookRetrieval":{"query":"  作者如何论证自由  ","purpose":"traceConcept","scope":"currentChapter","denseQuery":"  作者对自由的论证结构  ","lexicalTerms":"自由 论证"},
     "pastThoughtRetrieval":{"query":"过去的追问","purpose":"findRecurringQuestion"},
     "response":{"length":"medium","posture":"mayAskQuestion"}}
    """
    let wire = try JSONDecoder().decode(PlannerWirePlan.self, from: Data(json.utf8))
    let plan = wire.normalized()
    #expect(plan.intent == .conceptualQuestion)
    #expect(!plan.nearbyRequested)
    let book = try #require(plan.bookRequest)
    #expect(book.query == "作者如何论证自由")
    #expect(book.purpose == .traceConcept)
    #expect(book.scope == .currentChapter)
    #expect(book.denseQuery == "作者对自由的论证结构")
    #expect(book.lexicalTerms == "自由 论证")
    let past = try #require(plan.pastThoughtRequest)
    #expect(past.purpose == .findRecurringQuestion)
    #expect(plan.response == SemanticResponsePlan(length: .medium, posture: .mayAskQuestion))
}

@Test func normalizationDefaultsQueriesAndTrimsToBound() throws {
    // denseQuery/lexicalTerms omitted → fall back to the (trimmed) query.
    let minimal = PlannerWirePlan(
        intent: .passageObservation, nearbyPassage: .include,
        bookRetrieval: .init(query: "  自由与责任  ", purpose: .clarifyCurrentPassage, scope: .readSoFar)
    )
    let book = try #require(minimal.normalized().bookRequest)
    #expect(book.query == "自由与责任")
    #expect(book.denseQuery == "自由与责任")
    #expect(book.lexicalTerms == "自由与责任")

    // Oversized queries are bounded deterministically.
    let oversized = PlannerWirePlan(
        intent: .passageObservation, nearbyPassage: .omit,
        bookRetrieval: .init(query: String(repeating: "长", count: 400), purpose: .traceConcept, scope: .readSoFar)
    )
    let bounded = try #require(oversized.normalized().bookRequest)
    #expect(bounded.query.count == 240)

    // Omitted response plan decodes to a conservative default.
    let noResponse = try JSONDecoder().decode(
        PlannerWirePlan.self,
        from: Data(#"{"intent":"unclear","nearbyPassage":"omit"}"#.utf8)
    )
    #expect(noResponse.normalized().response == SemanticResponsePlan(length: .short, posture: .respondOnly))
}

// MARK: - B. Illegal-state prevention

@Test func unknownLegacyKeysAreIgnoredAndMemoryNeverBecomesARequest() throws {
    // A v1-style plan (with retrieval knobs and a memory request) fed to the v2
    // decoder: unknown keys are ignored, memory is structurally impossible as a
    // request, and no book-only field can leak into another source's config —
    // each request variant carries exactly its own fields.
    let json = """
    {"intent":"passageObservation","nearbyPassage":"include",
     "bookRetrieval":{"query":"自由","purpose":"traceConcept","scope":"readSoFar","candidateLimit":99,"useReranker":false},
     "memoryRetrieval":{"query":"自由观","maximumEvidenceCount":9},
     "response":{"length":"short","posture":"respondOnly"}}
    """
    let plan = try JSONDecoder().decode(PlannerWirePlan.self, from: Data(json.utf8)).normalized()
    #expect(plan.bookRequest?.query == "自由")
    #expect(plan.requests.count == 2, "nearby + book only; memory is a compiled system policy")
}

@Test func absentRequestHasExplicitSemantics() {
    let plan = PlannerWirePlan(intent: .unclear, nearbyPassage: .omit).normalized()
    #expect(plan.requests.isEmpty)
    #expect(plan.bookRequest == nil)
    #expect(plan.pastThoughtRequest == nil)
    #expect(!plan.nearbyRequested)
}

// MARK: - C. Semantic validation

@Test func validatorDropsUnavailableSourcesAndRecordsCorrections() {
    let semantic = SemanticContextPlan(
        intent: .personalConnection,
        requests: [
            .nearby,
            .book(BookContextRequest(query: "自由", purpose: .traceConcept, scope: .readSoFar, denseQuery: "自由", lexicalTerms: "自由")),
            .pastThought(PastThoughtContextRequest(query: "过去的想法", purpose: .findContinuation)),
        ],
        response: SemanticResponsePlan(length: .medium, posture: .mayAskQuestion)
    )
    let input = routingInput(hasLocator: false, hasPastThoughts: false, previousAgentAskedQuestion: true)
    let (validated, corrections) = SemanticPlanValidator().validate(semantic, input: input)
    #expect(validated.requests.isEmpty, "no locator → no nearby, no book; no past thoughts → no reflection lane")
    #expect(validated.response.posture == .respondOnly, "hard conversation rule stays deterministic")
    #expect(validated.response.length == .medium)
    #expect(corrections.count == 4)
    #expect(corrections.contains { $0.contains("nearby") })
    #expect(corrections.contains { $0.contains("book request") })
    #expect(corrections.contains { $0.contains("past-thought") })
    #expect(corrections.contains { $0.contains("respondOnly") })
}

@Test func validatorDropsEmptyQueriesButKeepsValidRequests() {
    let semantic = SemanticContextPlan(
        intent: .passageObservation,
        requests: [
            .book(BookContextRequest(query: "   ", purpose: .traceConcept, scope: .readSoFar, denseQuery: "   ", lexicalTerms: "自由")),
            .pastThought(PastThoughtContextRequest(query: "长期问题", purpose: .findChange)),
        ],
        response: SemanticResponsePlan(length: .short, posture: .respondOnly)
    )
    let (validated, corrections) = SemanticPlanValidator().validate(semantic, input: routingInput())
    #expect(validated.bookRequest == nil)
    #expect(validated.pastThoughtRequest?.query == "长期问题")
    #expect(corrections.count == 1)
}

@Test func validatorCapsReflectionReplyLengthButNotConversationLength() {
    func validatedLength(_ mode: ReaderInteractionMode) -> ResponseLength {
        let semantic = SemanticContextPlan(
            intent: .conceptualQuestion,
            requests: [],
            response: SemanticResponsePlan(length: .long, posture: .respondOnly)
        )
        return SemanticPlanValidator().validate(semantic, input: routingInput(interactionMode: mode)).plan.response.length
    }
    #expect(validatedLength(.reflection) == .medium)
    #expect(validatedLength(.conversation) == .long)
}

// MARK: - D. Policy compiler

@Test func compilerMapsPurposeToRetrievalStrategy() throws {
    func policy(for intent: ReflectionIntent, purpose: RetrievalPurpose, scope: PreferredBookScope) -> ContextExecutionPlan {
        let semantic = SemanticContextPlan(
            intent: intent,
            requests: [.book(BookContextRequest(query: "自由", purpose: purpose, scope: scope, denseQuery: "自由", lexicalTerms: "自由"))],
            response: SemanticResponsePlan(length: .short, posture: .respondOnly)
        )
        return ContextPolicyCompiler().compile(semantic, input: routingInput())
    }

    let conceptTrace = try #require(policy(for: .conceptualQuestion, purpose: .traceConcept, scope: .readSoFar).book)
    #expect(conceptTrace.evidenceLimit == 4)
    #expect(conceptTrace.retrievalMode == .hybrid)
    #expect(conceptTrace.candidateLimit == 10)
    #expect(conceptTrace.useReranker)
    #expect(conceptTrace.expansionMode == .boundedWindow)

    let factCheck = try #require(policy(for: .conceptualQuestion, purpose: .verifyBookFact, scope: .currentSection).book)
    #expect(factCheck.evidenceLimit == 2, "fact checks stay narrow")

    let contrast = try #require(policy(for: .authorDisagreement, purpose: .findEarlierContrast, scope: .currentChapter).book)
    #expect(contrast.evidenceLimit == 3)
}

@Test func compilerAssignsIntentBudgetsAndResponseGuidance() {
    let emotional = SemanticContextPlan(
        intent: .emotionalRecord,
        requests: [.nearby],
        response: SemanticResponsePlan(length: .short, posture: .mayAskQuestion)
    )
    let execution = ContextPolicyCompiler().compile(emotional, input: routingInput())
    let budget = execution.budget
    #expect(budget.totalCharacters == 6_000)
    #expect(budget.bookEvidenceCharacters == 0, "emotional records retrieve no book evidence")
    #expect(budget.pastThoughtCharacters == 0)
    #expect(execution.book == nil)
    #expect(execution.pastThought == nil)
    #expect(execution.memory.topN == 2, "memory is an unconditional system policy")
    #expect(execution.responseGuidance.allowQuestion)
    #expect(!execution.responseGuidance.shouldNaturallyEnd)

    let respondingOnly = SemanticContextPlan(
        intent: .emotionalRecord, requests: [],
        response: SemanticResponsePlan(length: .short, posture: .respondOnly)
    )
    let compiled = ContextPolicyCompiler().compile(respondingOnly, input: routingInput())
    #expect(!compiled.responseGuidance.allowQuestion)
    #expect(compiled.responseGuidance.shouldNaturallyEnd)
}

@Test func compilerEmitsLegacyTraceShapesForCompatibility() throws {
    let semantic = SemanticContextPlan(
        intent: .conceptualQuestion,
        requests: [
            .nearby,
            .book(BookContextRequest(query: "作者对自由的态度", purpose: .traceConcept, scope: .readSoFar, denseQuery: "作者如何看待自由与责任的张力", lexicalTerms: "自由 责任")),
            .pastThought(PastThoughtContextRequest(query: "长期问题", purpose: .findChange)),
        ],
        response: SemanticResponsePlan(length: .medium, posture: .respondOnly)
    )
    let execution = ContextPolicyCompiler().compile(semantic, input: routingInput())

    // Proposal keeps the v1 persisted shape; numeric fields carry compiled values.
    let proposal = execution.legacyProposal
    #expect(proposal.intent == .conceptualQuestion)
    #expect(proposal.nearbyPassage == .include)
    #expect(proposal.bookRetrieval?.query == "作者对自由的态度")
    #expect(proposal.bookRetrieval?.denseQuery == "作者如何看待自由与责任的张力")
    #expect(proposal.bookRetrieval?.candidateLimit == nil, "execution knobs are never LLM-surface fields again")
    #expect(proposal.memoryRetrieval == nil, "memory stays out of the plan surface (ADR 0001 hygiene)")
    #expect(proposal.rationale == nil, "free-text rationale is removed from the planner protocol")
    #expect(proposal.pastThoughtRetrieval?.maximumEvidenceCount == 1)

    // Validated shape records the compiled execution policy.
    let validated = execution.legacyValidatedPlan
    #expect(validated.bookRetrieval?.retrievalMode == .hybrid)
    #expect(validated.bookRetrieval?.candidateLimit == 10)
    #expect(validated.bookRetrieval?.useReranker == true)
    #expect(validated.bookRetrieval?.expansionMode == .boundedWindow)
    #expect(validated.bookRetrieval?.maximumEvidenceCount == 4)
    #expect(validated.budget.totalCharacters == 6_000)
    #expect(validated.memoryRetrieval == nil)

    // Both legacy shapes must keep round-tripping through Codable (trace compat).
    _ = try JSONDecoder().decode(ReaderContextPlan.self, from: JSONEncoder().encode(proposal))
    _ = try JSONDecoder().decode(ValidatedContextPlan.self, from: JSONEncoder().encode(validated))
}

// MARK: - F. Trace regression (persistence shapes)

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
    #expect(trace.planSchemaVersion == nil)
    #expect(trace.validationCorrections == nil)
    #expect(trace.routingDecodeAttempts == nil)
}

@Test func v2TraceCarriesSchemaVersionCorrectionsAndDecodeAttempts() throws {
    let semantic = SemanticContextPlan(
        intent: .personalConnection,
        requests: [.book(BookContextRequest(query: "自由", purpose: .traceConcept, scope: .readSoFar, denseQuery: "自由", lexicalTerms: "自由"))],
        response: SemanticResponsePlan(length: .medium, posture: .mayAskQuestion)
    )
    let (validated, corrections) = SemanticPlanValidator().validate(semantic, input: routingInput(hasLocator: false))
    let execution = ContextPolicyCompiler().compile(validated, input: routingInput(hasLocator: false))
    let trace = ContextPlanTrace(
        reflectionID: "ref-1",
        proposedPlan: execution.legacyProposal,
        validatedPlan: execution.legacyValidatedPlan,
        usedFallback: false,
        fallbackReason: nil,
        fallbackDetail: nil,
        routingDuration: .seconds(0.1),
        retrievalDuration: .seconds(0.2),
        replyDuration: .seconds(0.3),
        selectedBookEvidenceIDs: [],
        connectedReflectionID: nil,
        pipelineMetrics: nil,
        planSchemaVersion: PlannerWirePlan.schemaVersion,
        validationCorrections: corrections,
        routingDecodeAttempts: 1
    )
    let decoded = try JSONDecoder().decode(ContextPlanTrace.self, from: JSONEncoder().encode(trace))
    #expect(decoded.planSchemaVersion == 2)
    #expect(decoded.routingDecodeAttempts == 1)
    #expect(decoded.validationCorrections?.count == 1)
    #expect(decoded.validatedPlan.bookRetrieval == nil, "unavailable source never reaches execution")
}

@Test func pipelineMetricsRoundTripAndMissingMetricsDecodeToNil() throws {
    // Old-shape traces (no pipelineMetrics key) keep decoding.
    let old = try JSONDecoder().decode(ContextPlanTrace.self, from: Data(traceJSONWithoutMetrics.utf8))
    #expect(old.pipelineMetrics == nil)

    var metrics = ContextPipelineMetrics()
    metrics.retrievalMode = .hybrid
    metrics.denseQueryCustomized = true
    metrics.expandedEvidenceCount = 3
    metrics.deduplicatedCount = 2
    metrics.actualContextTokens = 1_200
    metrics.semanticCacheHits = 4
    metrics.semanticCacheMisses = 1
    let encoded = try JSONEncoder().encode(metrics)
    let decoded = try JSONDecoder().decode(ContextPipelineMetrics.self, from: encoded)
    #expect(decoded.retrievalMode == .hybrid)
    #expect(decoded.denseQueryCustomized == true)
    #expect(decoded.expandedEvidenceCount == 3)
    #expect(decoded.deduplicatedCount == 2)
    #expect(decoded.semanticCacheMisses == 1)
}

@Test func contextPlanTraceRoundTripsThroughCodable() throws {
    let semantic = SemanticContextPlan(
        intent: .conceptualQuestion,
        requests: [
            .nearby,
            .book(BookContextRequest(query: "自由与责任", purpose: .traceConcept, scope: .readSoFar, denseQuery: "自由与责任", lexicalTerms: "自由与责任")),
        ],
        response: SemanticResponsePlan(length: .medium, posture: .mayAskQuestion)
    )
    let (validated, _) = SemanticPlanValidator().validate(semantic, input: routingInput())
    let execution = ContextPolicyCompiler().compile(validated, input: routingInput())
    let trace = ContextPlanTrace(
        reflectionID: "ref-1",
        proposedPlan: execution.legacyProposal,
        validatedPlan: execution.legacyValidatedPlan,
        usedFallback: true,
        fallbackReason: .modelFailure,
        fallbackDetail: "network",
        routingDuration: .seconds(0.125),
        retrievalDuration: .seconds(0.35),
        replyDuration: .seconds(2),
        selectedBookEvidenceIDs: ["chunk-1", "chunk-2"],
        connectedReflectionID: "ref-0",
        routingTokenUsage: .init(inputTokens: 100, outputTokens: 20, totalTokens: 120),
        replyTokenUsage: .init(inputTokens: 500, outputTokens: 200, totalTokens: 700),
        planSchemaVersion: PlannerWirePlan.schemaVersion,
        routingDecodeAttempts: 2
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
    #expect(decoded.routingDecodeAttempts == 2)
}

@Test func routingTraceDiagnosticsAggregateFallbacksAndAverages() throws {
    func trace(_ id: String, usedFallback: Bool, detail: String?, seconds: [Double]) -> ContextPlanTrace {
        let semantic = SemanticContextPlan(
            intent: .passageObservation, requests: [.nearby],
            response: SemanticResponsePlan(length: .short, posture: .respondOnly)
        )
        let execution = ContextPolicyCompiler().compile(semantic, input: routingInput(hasLocator: true, hasPastThoughts: true))
        return ContextPlanTrace(
            reflectionID: id,
            proposedPlan: execution.legacyProposal,
            validatedPlan: execution.legacyValidatedPlan,
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

/// A trace encoded BEFORE ContextPipelineMetrics existed (no pipelineMetrics key).
private let traceJSONWithoutMetrics = """
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

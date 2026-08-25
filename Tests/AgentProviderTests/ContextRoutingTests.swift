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

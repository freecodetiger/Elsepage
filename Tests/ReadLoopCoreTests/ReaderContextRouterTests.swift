import AgentRuntime
import ContextRouting
import Foundation
import LibraryCore
import Testing

/// Model client returning a different scripted response per call, so router
/// repair-retry behavior can be exercised end to end.
private final class SequentialScriptedClient: ModelClient, @unchecked Sendable {
    let descriptor = ModelDescriptor(provider: "fake", model: "scripted", capabilities: .init(supportsStreaming: true))
    private let responses: [String]
    private let lock = NSLock()
    private var callCount = 0

    init(responses: [String]) {
        self.responses = responses
    }

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return callCount
    }

    func stream(request: ModelRequest) -> AsyncThrowingStream<ModelEvent, Error> {
        lock.lock()
        let index = min(callCount, responses.count - 1)
        callCount += 1
        lock.unlock()
        let content = responses[index]
        return AsyncThrowingStream { continuation in
            continuation.yield(.started)
            continuation.yield(.completed(ModelResponse(content: content)))
            continuation.finish()
        }
    }
}

private let validPlanJSON = """
{"intent":"unclear","nearbyPassage":"include","bookRetrieval":null,"pastThoughtRetrieval":null,"response":{"length":"short","posture":"respondOnly"}}
"""

private func makeInput() -> ContextRoutingInput {
    ContextRoutingInput(
        interactionMode: .reflection,
        currentReflection: "路由重试测试",
        recentConversation: [],
        currentReading: nil,
        availableSources: .init(hasNearbyPassage: false, hasBookIndex: false, hasPastThoughts: false),
        previousAgentAskedQuestion: false
    )
}

@Suite struct ReaderContextRouterTests {
    @Test func repairsTransientStructuredOutputFailure() async {
        let client = SequentialScriptedClient(responses: ["好的，这是计划：这不是 JSON", validPlanJSON])
        let result = await LLMReaderContextRouter().route(makeInput(), using: client)
        #expect(client.calls == 2)
        #expect(!result.usedFallback)
        #expect(result.plan.intent == .unclear)
        #expect(result.decodeAttempts == 2, "repair attempt must be instrumented")
    }

    @Test func cleanDecodeReportsSingleAttempt() async {
        let client = SequentialScriptedClient(responses: [validPlanJSON])
        let result = await LLMReaderContextRouter().route(makeInput(), using: client)
        #expect(client.calls == 1)
        #expect(!result.usedFallback)
        #expect(result.decodeAttempts == 1)
    }

    @Test func fallsBackWithBoundedDecodeDetailAfterRepeatedFailures() async throws {
        let client = SequentialScriptedClient(responses: ["意图：情绪记录（非 JSON）"])
        let result = await LLMReaderContextRouter().route(makeInput(), using: client)
        #expect(result.usedFallback)
        #expect(result.fallbackReason == .invalidStructuredOutput)
        #expect(result.decodeAttempts == 2)
        let detail = try #require(result.fallbackDetail)
        #expect(detail.hasPrefix("structuredDecodeFailed"))
        #expect(detail.count <= 180)
        #expect(!detail.contains("情绪记录（非 JSON）"), "decode detail must not echo raw model output")
    }

    @Test func modelFailureStillReportsFailureName() async {
        let result = await LLMReaderContextRouter().route(
            makeInput(),
            using: FailureAfterStartClient()
        )
        #expect(result.usedFallback)
        #expect(result.fallbackReason == .modelFailure)
        #expect(result.fallbackDetail == "providerUnavailable")
    }

    @Test func structuredDecodeDetailNamesSchemaProblem() {
        let detail = LLMReaderContextRouter.structuredDecodeDetail(#"{"intent":"回忆","nearbyPassage":"include"}"#)
        #expect(detail.contains("intent"))
        #expect(detail.hasPrefix("structuredDecodeFailed"))
    }

    /// The fallback path must converge onto the same strict domain model as the
    /// LLM path so validator + policy compiler semantics are shared.
    @Test func fallbackProducesSemanticPlanReadyForValidationAndCompilation() {
        let input = ContextRoutingInput(
            interactionMode: .reflection,
            currentReflection: "  兜底计划的查询文本  ",
            recentConversation: [],
            currentReading: .init(bookID: BookID(), hasCurrentLocator: true),
            availableSources: .init(hasNearbyPassage: true, hasBookIndex: true, hasPastThoughts: true),
            previousAgentAskedQuestion: true
        )
        let fallback = DeterministicReaderContextRouter().result(for: input, reason: .modelFailure, detail: "network")
        #expect(fallback.usedFallback)
        #expect(fallback.plan.intent == .unclear)
        #expect(fallback.plan.nearbyRequested)
        #expect(fallback.plan.bookRequest?.query == "兜底计划的查询文本")
        #expect(fallback.plan.pastThoughtRequest != nil)
        #expect(fallback.plan.response.posture == .respondOnly, "hard conversation rule baked into fallback")

        let (validated, corrections) = SemanticPlanValidator().validate(fallback.plan, input: input)
        #expect(corrections.isEmpty)
        let executionPlan = ContextPolicyCompiler().compile(validated, input: input)
        #expect(executionPlan.book?.evidenceLimit == ContextPolicyCompiler.evidenceLimit(for: .traceConcept))
        #expect(executionPlan.pastThought?.evidenceLimit == 1)
        #expect(executionPlan.responseGuidance.allowQuestion == false)
    }
}

private struct FailureAfterStartClient: ModelClient {
    let descriptor = ModelDescriptor(provider: "fake", model: "scripted", capabilities: .init(supportsStreaming: true))

    func stream(request: ModelRequest) -> AsyncThrowingStream<ModelEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.started)
            continuation.finish(throwing: AgentFailure.providerUnavailable)
        }
    }
}

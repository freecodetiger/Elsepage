import AgentRuntime
import ContextRouting
import Foundation
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
{"intent":"unclear","nearbyPassage":"include","bookRetrieval":null,"pastThoughtRetrieval":null,"memoryRetrieval":null,"responseGuidance":{"targetLength":"short","allowQuestion":true,"shouldNaturallyEnd":false},"rationale":null}
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
    }

    @Test func fallsBackWithBoundedDecodeDetailAfterRepeatedFailures() async throws {
        let client = SequentialScriptedClient(responses: ["意图：情绪记录（非 JSON）"])
        let result = await LLMReaderContextRouter().route(makeInput(), using: client)
        #expect(result.usedFallback)
        #expect(result.fallbackReason == .invalidStructuredOutput)
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

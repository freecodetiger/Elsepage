import AgentRuntime
import Foundation
import Testing

@Test func executorStreamsOneBoundedModelResponse() async {
    let response = ModelResponse(
        content: "完整回应",
        usage: TokenUsage(inputTokens: 8, outputTokens: 3, totalTokens: 11)
    )
    let executor = AgentExecutor(
        client: FakeModelClient(events: [
            .started,
            .textDelta("完整"),
            .textDelta("回应"),
            .usage(response.usage!),
            .completed(response)
        ]),
        budget: .init(maxModelCalls: 1, maxWallTime: .seconds(1), maxOutputTokens: 200)
    )

    let events = await collect(executor.run(input: testInput()))

    #expect(events.count == 6)
    #expect(events.contains(.textDelta("完整")))
    #expect(events.contains(.textDelta("回应")))
    #expect(events.contains(.usageUpdated(response.usage!)))
    guard case .completed(let result) = events.last else {
        Issue.record("Expected completed event"); return
    }
    #expect(result.response == response)
    #expect(result.metadata.promptVersion == "test-v1")
}

@Test func executorRejectsMissingAndDuplicateCompletion() async {
    let missing = AgentExecutor(
        client: FakeModelClient(events: [.textDelta("没有完成事件")]),
        budget: .init(maxWallTime: .seconds(1))
    )
    let missingEvents = await collect(missing.run(input: testInput()))
    #expect(missingEvents.last == .failed(.malformedProviderResponse))

    let response = ModelResponse(content: "重复")
    let duplicate = AgentExecutor(
        client: FakeModelClient(events: [.completed(response), .completed(response)]),
        budget: .init(maxWallTime: .seconds(1))
    )
    let duplicateEvents = await collect(duplicate.run(input: testInput()))
    #expect(duplicateEvents.last == .failed(.malformedProviderResponse))
}

@Test func executorEnforcesCallAndWallTimeBudgets() async {
    let noCalls = AgentExecutor(
        client: FakeModelClient(events: [.completed(.init(content: "不应执行"))]),
        budget: .init(maxModelCalls: 0, maxWallTime: .seconds(1))
    )
    #expect(await collect(noCalls.run(input: testInput())).last == .failed(.budgetExceeded))

    let slow = AgentExecutor(
        client: FakeModelClient(
            events: [.completed(.init(content: "太晚"))],
            eventDelay: .milliseconds(100)
        ),
        budget: .init(maxModelCalls: 1, maxWallTime: .milliseconds(5))
    )
    #expect(await collect(slow.run(input: testInput())).last == .failed(.budgetExceeded))
}

@Test func executorNormalizesModelAuthenticationFailure() async {
    let executor = AgentExecutor(
        client: FakeModelClient(events: [], terminalFailure: .authentication),
        budget: .init(maxWallTime: .seconds(1))
    )
    #expect(await collect(executor.run(input: testInput())).last == .failed(.authentication))
}

@Test func cancellingConsumerPropagatesIntoModelStream() async throws {
    let probe = CancellationProbe()
    let executor = AgentExecutor(
        client: BlockingModelClient(probe: probe),
        budget: .init(maxWallTime: .seconds(5))
    )
    let task = Task { await collect(executor.run(input: testInput())) }
    try await Task.sleep(for: .milliseconds(10))
    task.cancel()
    _ = await task.value

    for _ in 0..<20 {
        if await probe.wasCancelled() { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await probe.wasCancelled())
}

private func collect(_ stream: AsyncStream<AgentEvent>) async -> [AgentEvent] {
    var events: [AgentEvent] = []
    for await event in stream { events.append(event) }
    return events
}

private func testInput() -> AgentInput {
    AgentInput(
        metadata: .init(
            agentKind: "test.agent",
            promptVersion: "test-v1",
            contextRecipeVersion: "test-context-v1"
        ),
        messages: []
    )
}

private actor CancellationProbe {
    private var cancelled = false
    func markCancelled() { cancelled = true }
    func wasCancelled() -> Bool { cancelled }
}

private struct BlockingModelClient: ModelClient {
    let probe: CancellationProbe
    let descriptor = ModelDescriptor(
        provider: "fake", model: "blocking", capabilities: .init(supportsStreaming: true)
    )

    func stream(request: ModelRequest) -> AsyncThrowingStream<ModelEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Task.sleep(for: .seconds(30))
                    continuation.finish()
                } catch {
                    await probe.markCancelled()
                    continuation.finish(throwing: CancellationError())
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

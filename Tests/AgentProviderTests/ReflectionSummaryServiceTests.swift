import AgentRuntime
import LibraryCore
import ReaderAgent
import ReflectionCore
import Testing

private struct FixedSummaryModelFactory: ModelClientFactory {
    let client: any ModelClient
    func makeClient() -> any ModelClient { client }
}

@Test func reflectionSummaryJoinsAndNormalizesModelOutput() async throws {
    let client = FakeModelClient(events: [
        .started,
        .textDelta("概要：自由意味着承担"),
        .textDelta("选择的结果。"),
        .completed(ModelResponse(content: ""))
    ])
    let service = ReflectionSummaryService(clientFactory: FixedSummaryModelFactory(client: client))
    let reflection = Reflection(
        bookID: BookID(),
        originalText: "自由不是没有重量，只是重量落回自己身上。",
        inputKind: .text
    )

    let summary = try await service.summarize(
        reflection: reflection,
        firstAgentResponse: "你把自由的重心移到了承担结果。"
    )

    #expect(summary == "自由意味着承担选择的结果。")
}

@Test func reflectionSummaryRejectsEmptyOutputAndLongUnpunctuatedOutput() async throws {
    let emptyClient = FakeModelClient(events: [.completed(ModelResponse(content: " \n "))])
    let emptyService = ReflectionSummaryService(clientFactory: FixedSummaryModelFactory(client: emptyClient))
    let reflection = Reflection(bookID: BookID(), originalText: "原话", inputKind: .text)

    await #expect(throws: ReflectionSummaryError.emptyResult) {
        _ = try await emptyService.summarize(reflection: reflection, firstAgentResponse: "回应")
    }

    let longClient = FakeModelClient(events: [
        .textDelta(String(repeating: "长", count: ReflectionSummary.maximumCharacterCount + 1)),
        .completed(ModelResponse(content: ""))
    ])
    let longService = ReflectionSummaryService(clientFactory: FixedSummaryModelFactory(client: longClient))
    await #expect(throws: ReflectionSummaryError.tooLong) {
        _ = try await longService.summarize(reflection: reflection, firstAgentResponse: "回应")
    }
}

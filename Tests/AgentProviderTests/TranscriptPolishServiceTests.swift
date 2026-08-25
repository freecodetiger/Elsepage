import AgentRuntime
import Testing

private struct FixedModelFactory: ModelClientFactory {
    let client: any ModelClient
    func makeClient() -> any ModelClient { client }
}

@Test func polishJoinsTextDeltasIntoOneResult() async throws {
    let client = FakeModelClient(events: [
        .started,
        .textDelta("整理后的"),
        .textDelta("文字"),
        .completed(ModelResponse(content: ""))
    ])
    let service = TranscriptPolishService(clientFactory: FixedModelFactory(client: client))
    let result = try await service.polish("原始 口述 乱句")
    #expect(result == "整理后的文字")
}

@Test func polishThrowsOnEmptyResult() async throws {
    let client = FakeModelClient(events: [.started, .completed(ModelResponse(content: "  \n "))])
    let service = TranscriptPolishService(clientFactory: FixedModelFactory(client: client))
    await #expect(throws: TranscriptPolishError.self) {
        _ = try await service.polish("x")
    }
}

import AgentRuntime
import Foundation
import ModelProviders
import Testing

@Test func clientEncodesJSONObjectResponseFormatInRequestBody() async throws {
    let transport = StubTransport { request in
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let format = try #require(json["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_object")
        let data = try JSONEncoder().encode(ChatResponseBody(
            id: "1",
            choices: [.init(message: .init(content: "{}"), finishReason: "stop")]
        ))
        return (data, HTTPURLResponse(
            url: URL(string: "https://api.example.com")!, statusCode: 200,
            httpVersion: nil, headerFields: nil
        )!)
    }
    let client = try OpenAICompatibleModelClient(
        configuration: ProviderConfiguration(
            provider: .openAICompatible,
            baseURL: URL(string: "https://api.example.com/v1")!,
            modelID: "chat-model",
            secretReference: .init(rawValue: "ref")
        ),
        apiKey: "k",
        transport: transport
    )
    var received = ""
    for try await event in client.stream(request: .init(
        messages: [.init(role: .user, content: "hi")],
        responseFormat: .jsonObject
    )) {
        if case .completed(let response) = event { received = response.content }
    }
    #expect(received == "{}")
}

@Test func clientOmitsResponseFormatWhenNotRequested() async throws {
    let transport = StubTransport { request in
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["response_format"] == nil)
        let data = try JSONEncoder().encode(ChatResponseBody(
            id: "1",
            choices: [.init(message: .init(content: "ok"), finishReason: "stop")]
        ))
        return (data, HTTPURLResponse(
            url: URL(string: "https://api.example.com")!, statusCode: 200,
            httpVersion: nil, headerFields: nil
        )!)
    }
    let client = try OpenAICompatibleModelClient(
        configuration: ProviderConfiguration(
            provider: .openAICompatible,
            baseURL: URL(string: "https://api.example.com/v1")!,
            modelID: "chat-model",
            secretReference: .init(rawValue: "ref")
        ),
        apiKey: "k",
        transport: transport
    )
    for try await _ in client.stream(request: .init(messages: [.init(role: .user, content: "hi")])) {}
}

private struct StubTransport: HTTPDataTransport {
    let onRequest: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try onRequest(request)
    }
}

private struct ChatResponseBody: Encodable {
    let id: String
    let choices: [Choice]

    struct Choice: Encodable {
        let message: Message
        let finishReason: String
        enum CodingKeys: String, CodingKey { case message, finishReason = "finish_reason" }
    }

    struct Message: Encodable { let content: String }
}

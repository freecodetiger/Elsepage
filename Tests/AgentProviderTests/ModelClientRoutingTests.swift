import AgentRuntime
import Foundation
import ModelProviders
import Testing

/// PROV-01: the Anthropic preset must ride the native Messages API client while
/// every OpenAI-compatible preset (and custom endpoints) keeps the existing
/// client — for both the runtime factory and the settings test-connection path.
struct ModelClientRoutingTests {
    @Test func factoryRoutesAnthropicPresetToNativeClient() async throws {
        let secrets = InMemorySecretStore()
        await secrets.save("sk-ant-key", for: .init(rawValue: "ref"))
        let factory = ConfiguredModelClientFactory(
            configurations: StaticConfigurationRepository(configuration: ProviderConfiguration(
                provider: .openAICompatible, // exactly what the settings row persists
                baseURL: ModelProviderPreset.anthropic.baseURL!,
                modelID: "claude-sonnet-4",
                secretReference: .init(rawValue: "ref")
            )),
            secrets: secrets
        )
        let client = try await factory.makeClient()
        #expect(client is AnthropicModelClient)
        #expect(client.descriptor.provider == "anthropic")
        #expect(client.descriptor.capabilities.supportsStreaming == false)
    }

    @Test func factoryKeepsOpenAICompatiblePresetsOnExistingClient() async throws {
        let secrets = InMemorySecretStore()
        await secrets.save("sk-key", for: .init(rawValue: "ref"))
        for baseURL in [ModelProviderPreset.openAI.baseURL!, ModelProviderPreset.deepSeek.baseURL!, ModelProviderPreset.moonshot.baseURL!] {
            let factory = ConfiguredModelClientFactory(
                configurations: StaticConfigurationRepository(configuration: ProviderConfiguration(
                    provider: .openAICompatible, baseURL: baseURL,
                    modelID: "any-model", secretReference: .init(rawValue: "ref")
                )),
                secrets: secrets
            )
            let client = try await factory.makeClient()
            #expect(client is OpenAICompatibleModelClient)
            #expect(client.descriptor.provider == "openAICompatible")
        }
    }

    @Test func connectionTesterSpeaksNativeMessagesForAnthropicPreset() async throws {
        let baseURL = ModelProviderPreset.anthropic.baseURL!
        let captured = CapturedRequest()
        StubURLProtocol.register(url: baseURL.appendingPathComponent("messages")) { request in
            captured.store(request)
            return (200, [:], Data(#"{"id":"msg_ok","content":[{"type":"text","text":"OK"}],"stop_reason":"end_turn"}"#.utf8))
        }
        try await ProviderConnectionTester(transport: StubURLProtocol.makeTransport()).test(
            configuration: ProviderConfiguration(
                provider: .openAICompatible, baseURL: baseURL,
                modelID: "claude-sonnet-4", secretReference: .init(rawValue: "ref")
            ),
            apiKey: "sk-ant-real"
        )
        let request = try #require(captured.value())
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-real")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    }

    @Test func connectionTesterStillUsesOpenAIProtocolForCompatiblePreset() async throws {
        let baseURL = ModelProviderPreset.deepSeek.baseURL!
        let captured = CapturedRequest()
        StubURLProtocol.register(url: baseURL.appendingPathComponent("chat/completions")) { request in
            captured.store(request)
            return (200, [:], Data(#"{"id":"1","choices":[{"message":{"content":"OK"},"finish_reason":"stop"}]}"#.utf8))
        }
        try await ProviderConnectionTester(transport: StubURLProtocol.makeTransport()).test(
            configuration: ProviderConfiguration(
                provider: .openAICompatible, baseURL: baseURL,
                modelID: "deepseek-chat", secretReference: .init(rawValue: "ref")
            ),
            apiKey: "sk-deepseek"
        )
        let request = try #require(captured.value())
        #expect(request.url?.absoluteString == "https://api.deepseek.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-deepseek")
    }
}

private actor StaticConfigurationRepository: ProviderConfigurationRepository {
    let configuration: ProviderConfiguration?

    init(configuration: ProviderConfiguration?) { self.configuration = configuration }
    func currentConfiguration() -> ProviderConfiguration? { configuration }
    func save(_ configuration: ProviderConfiguration) {}
    func deleteCurrentConfiguration() {}
}

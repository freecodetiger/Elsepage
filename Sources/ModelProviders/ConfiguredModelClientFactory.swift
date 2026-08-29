import AgentRuntime
import Foundation

/// Chooses the wire protocol for a persisted provider row. The stored `provider`
/// column only distinguishes OpenAI-compatible dialects (the `providerConfigurations`
/// CHECK constraint admits 'openAI'/'openAICompatible'), so the Anthropic-native
/// Messages API is recognized by its canonical preset endpoint — the same
/// `ModelProviderPreset.matching(baseURL:)` the settings UI already uses to
/// recover the selected preset from a persisted row. Custom/unknown endpoints
/// stay on the OpenAI-compatible client.
public enum ModelClientRouting {
    public static func isNativeAnthropic(_ baseURL: URL) -> Bool {
        ModelProviderPreset.matching(baseURL: baseURL) == .anthropic
    }

    public static func makeClient(
        configuration: ProviderConfiguration, apiKey: String,
        transport: any HTTPDataTransport = URLSessionDataTransport()
    ) throws -> any ModelClient {
        if configuration.provider == .anthropic || isNativeAnthropic(configuration.baseURL) {
            return try AnthropicModelClient(configuration: configuration, apiKey: apiKey, transport: transport)
        }
        return try OpenAICompatibleModelClient(configuration: configuration, apiKey: apiKey, transport: transport)
    }
}

/// Resolves non-secret configuration and its Keychain credential only when a run starts.
public struct ConfiguredModelClientFactory: ModelClientFactory {
    private let configurations: any ProviderConfigurationRepository
    private let secrets: any SecretStore

    public init(
        configurations: any ProviderConfigurationRepository,
        secrets: any SecretStore
    ) {
        self.configurations = configurations
        self.secrets = secrets
    }

    public func makeClient() async throws -> any ModelClient {
        guard let configuration = try await configurations.currentConfiguration(),
              let key = try await secrets.secret(for: configuration.secretReference),
              !key.isEmpty else {
            throw ModelFailure.invalidConfiguration
        }
        return try ModelClientRouting.makeClient(configuration: configuration, apiKey: key)
    }
}

public struct ProviderConnectionTester: Sendable {
    private let transport: any HTTPDataTransport

    public init(transport: any HTTPDataTransport = URLSessionDataTransport()) {
        self.transport = transport
    }

    public func test(configuration: ProviderConfiguration, apiKey: String) async throws {
        let client = try ModelClientRouting.makeClient(
            configuration: configuration,
            apiKey: apiKey,
            transport: transport
        )
        var visibleText: String?
        for try await event in client.stream(request: ModelRequest(
            messages: [ModelMessage(role: .user, content: "Reply with OK.")],
            temperature: 0,
            maxOutputTokens: 8
        )) {
            if case .completed(let response) = event {
                visibleText = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard let visibleText, !visibleText.isEmpty else { throw ModelFailure.invalidResponse }
    }
}

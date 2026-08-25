import AgentRuntime
import Foundation

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
        return try OpenAICompatibleModelClient(configuration: configuration, apiKey: key)
    }
}

public struct ProviderConnectionTester: Sendable {
    public init() {}

    public func test(configuration: ProviderConfiguration, apiKey: String) async throws {
        let client = try OpenAICompatibleModelClient(configuration: configuration, apiKey: apiKey)
        var completed = false
        for try await event in client.stream(request: ModelRequest(
            messages: [ModelMessage(role: .user, content: "Reply with OK.")],
            temperature: 0,
            maxOutputTokens: 8
        )) {
            if case .completed = event { completed = true }
        }
        guard completed else { throw ModelFailure.invalidResponse }
    }
}

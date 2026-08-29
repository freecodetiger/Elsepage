import AgentRuntime
import Foundation
import ModelProviders
import Persistence
import Testing

/// PROV-01, no-migration proof: the row shape the settings model persists for
/// the Anthropic preset (provider stays 'openAICompatible' per the schema CHECK
/// constraint) round-trips through SQLite unchanged, and the loaded row routes
/// to the native Anthropic Messages client at client-construction time.
struct AnthropicProviderPersistenceTests {
    @Test func anthropicPresetRowRoundTripsAndRoutesToNativeClient() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBProviderConfigurationRepository(database: database)
        // Exactly what ProviderSettingsModel.configuration() builds when the
        // Anthropic preset is selected (baseURL comes from the preset default).
        let configuration = ProviderConfiguration(
            provider: .openAICompatible,
            baseURL: ModelProviderPreset.anthropic.baseURL!,
            modelID: "claude-sonnet-4",
            secretReference: .init(rawValue: "primary-model-provider")
        )
        try await repository.save(configuration)

        let loaded = try await #require(repository.currentConfiguration())
        #expect(loaded.baseURL == ModelProviderPreset.anthropic.baseURL!)
        #expect(loaded.modelID == "claude-sonnet-4")
        // The settings UI recovers the Anthropic preset from the persisted URL.
        #expect(ModelProviderPreset.matching(baseURL: loaded.baseURL) == .anthropic)

        let client = try ModelClientRouting.makeClient(configuration: loaded, apiKey: "sk-ant-key")
        #expect(client is AnthropicModelClient)
        #expect(client.descriptor.provider == "anthropic")
    }
}

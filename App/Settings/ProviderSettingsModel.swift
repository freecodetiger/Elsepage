import AgentRuntime
import Foundation
import ModelProviders
import Observation

/// Chat provider configuration (BYOK). Owns the shared provider row: its
/// `configuration()` builder carries the embedding/reranker role fields from the
/// persisted row so other role models can read/write them without duplicating
/// state. Diagnostics, RAG roles and data actions live in their own models.
@MainActor @Observable
final class ProviderSettingsModel {
    static let secretReference = SecretReference(rawValue: "primary-model-provider")
    static let embeddingSecretReference = SecretReference(rawValue: "embedding-model-provider")
    static let rerankerSecretReference = SecretReference(rawValue: "reranker-model-provider")

    /// SiliconFlow embedding model presets (selectable; custom stays editable).
    static let siliconFlowEmbeddingModels: [(name: String, model: String)] = [
        ("Qwen3-VL Embedding 8B（多模态）", "Qwen/Qwen3-VL-Embedding-8B"),
        ("BGE-M3（多语言，推荐）", "BAAI/bge-m3"),
        ("BGE Large ZH（中文）", "BAAI/bge-large-zh-v1.5"),
        ("BGE Small ZH（中文轻量）", "BAAI/bge-small-zh-v1.5"),
        ("BGE Large EN（英文）", "BAAI/bge-large-en-v1.5"),
        ("BCE Embedding（中英）", "netease-youdao/bce-embedding-base_v1"),
    ]
    /// SiliconFlow cross-encoder rerank presets (RAG precision gate).
    static let siliconFlowRerankerModels: [(name: String, model: String)] = [
        ("Qwen3-VL Reranker 8B（多模态）", "Qwen/Qwen3-VL-Reranker-8B"),
        ("BGE Reranker V2 M3（推荐）", "BAAI/bge-reranker-v2-m3"),
        ("Jina Reranker V2（多语言）", "jina-reranker-v2-base-multilingual"),
    ]

    private let configurations: any ProviderConfigurationRepository
    let secrets: any SecretStore
    /// The persisted provider row (embedding/reranker role fields included), so
    /// the chat builder can carry the other roles' values through without owning
    /// their state.
    private var loadedConfiguration: ProviderConfiguration?

    var selectedPreset: ModelProviderPreset = .openAI
    var baseURL = "https://api.openai.com/v1"
    var modelID = ""
    var apiKey = ""
    var streamingEnabled = false
    private(set) var hasSavedKey = false
    private(set) var isWorking = false
    private(set) var statusMessage: String?
    /// Outcome of the most recent `testConnection()` (Onboarding uses it to
    /// unlock its 继续 affordance without matching on localized strings).
    private(set) var lastConnectionTestSucceeded = false
    var errorMessage: String?

    /// True when a provider row or a saved key already exists — lets Onboarding
    /// recognize an already-configured user without duplicating load logic.
    var isConfigured: Bool { hasSavedKey || loadedConfiguration != nil }

    init(configurations: any ProviderConfigurationRepository, secrets: any SecretStore) {
        self.configurations = configurations
        self.secrets = secrets
    }

    func load() async {
        do {
            guard let configuration = try await configurations.currentConfiguration() else { return }
            loadedConfiguration = configuration
            selectedPreset = .matching(baseURL: configuration.baseURL)
            baseURL = configuration.baseURL.absoluteString
            modelID = configuration.modelID
            streamingEnabled = configuration.streamingEnabled
            hasSavedKey = try await secrets.secret(for: Self.secretReference) != nil
        } catch { errorMessage = Self.message(for: error) }
    }

    func selectPreset(_ preset: ModelProviderPreset) {
        guard selectedPreset != preset else { return }
        selectedPreset = preset
        if let url = preset.baseURL { baseURL = url.absoluteString }
        else { baseURL = "" }
        modelID = ""
    }

    func save() async -> Bool {
        guard let configuration = configuration(), let key = keyForSave() else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            let typedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let previousKey = try await secrets.secret(for: Self.secretReference)
            if !typedKey.isEmpty { try await secrets.save(key, for: Self.secretReference) }
            do {
                try await configurations.save(configuration)
            } catch {
                if !typedKey.isEmpty {
                    if let previousKey { try await secrets.save(previousKey, for: Self.secretReference) }
                    else { try await secrets.removeSecret(for: Self.secretReference) }
                }
                throw error
            }
            apiKey = ""
            hasSavedKey = true
            statusMessage = "配置已保存在本机"
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    func testConnection() async {
        guard let configuration = configuration() else {
            lastConnectionTestSucceeded = false
            return
        }
        isWorking = true
        statusMessage = nil
        lastConnectionTestSucceeded = false
        defer { isWorking = false }
        do {
            let key = try await resolvedKey()
            try await ProviderConnectionTester().test(configuration: configuration, apiKey: key)
            statusMessage = "连接成功"
            lastConnectionTestSucceeded = true
        } catch { errorMessage = Self.message(for: error) }
    }

    /// Deletes the whole provider configuration plus every role's API Key.
    /// Role models reset their own UI state by reloading after this.
    func deleteConfiguration() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let previousKey = try await secrets.secret(for: Self.secretReference)
            try await secrets.removeSecret(for: Self.secretReference)
            do {
                try await configurations.deleteCurrentConfiguration()
            } catch {
                if let previousKey { try await secrets.save(previousKey, for: Self.secretReference) }
                throw error
            }
            try? await secrets.removeSecret(for: Self.embeddingSecretReference)
            try? await secrets.removeSecret(for: Self.rerankerSecretReference)
            apiKey = ""
            hasSavedKey = false
            loadedConfiguration = nil
            statusMessage = "配置和 API Key 已删除"
        } catch { errorMessage = Self.message(for: error) }
    }

    /// The full provider row: chat fields from this model, role (embedding/
    /// reranker) fields from the persisted row. Role models build their own
    /// rows on top of this base and persist via `saveRoleConfiguration`.
    func configuration() -> ProviderConfiguration? {
        let model = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil,
              !model.isEmpty else {
            errorMessage = "请填写有效的 Base URL 和模型名称。"
            return nil
        }
        return ProviderConfiguration(
            provider: selectedPreset.providerKind,
            baseURL: url,
            modelID: model,
            secretReference: Self.secretReference,
            streamingEnabled: streamingEnabled,
            embeddingModelID: loadedConfiguration?.embeddingModelID,
            embeddingBaseURL: loadedConfiguration?.embeddingBaseURL,
            embeddingSecretReference: Self.embeddingSecretReference,
            rerankerModelID: loadedConfiguration?.rerankerModelID,
            rerankerBaseURL: loadedConfiguration?.rerankerBaseURL,
            rerankerSecretReference: Self.rerankerSecretReference
        )
    }

    /// Persists a role-merged row and refreshes the cached copy.
    func saveRoleConfiguration(_ configuration: ProviderConfiguration) async throws {
        try await configurations.save(configuration)
        loadedConfiguration = configuration
    }

    /// The raw persisted row (role fields included), or nil when nothing is stored.
    func persistedConfiguration() -> ProviderConfiguration? { loadedConfiguration }

    func clearTransientSecret() {
        apiKey = ""
    }

    private func keyForSave() -> String? {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty || hasSavedKey else {
            errorMessage = "请填写 API Key。"
            return nil
        }
        return key
    }

    private func resolvedKey() async throws -> String {
        let typed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        if let saved = try await secrets.secret(for: Self.secretReference), !saved.isEmpty { return saved }
        throw ModelFailure.invalidConfiguration
    }

    static func message(for error: Error) -> String {
        if let provider = error as? ModelFailure {
            switch provider {
            case .invalidConfiguration: return "Provider 配置或 API Key 无效。"
            case .invalidResponse: return "Provider 返回了无法识别的响应。"
            case .authentication: return "API Key 无效或没有访问权限。"
            case .rateLimited: return "Provider 请求过于频繁，请稍后再试。"
            case .providerUnavailable: return "Provider 暂时不可用。"
            case .network: return "网络连接失败。"
            case .providerMessage(let message): return message
            }
        }
        return error.localizedDescription
    }
}

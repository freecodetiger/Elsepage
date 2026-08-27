import AgentRuntime
import Foundation
import LibraryCore
import ModelProviders
import Observation
import RetrievalCore

/// Semantic retrieval (RAG) role configuration: the embedding model/endpoint/key
/// and the reranker (cross-encoder precision gate). Each role has its own row
/// fields on the shared provider configuration; the chat model owns that row and
/// provides the base — this model only owns the two roles' state + actions.
@MainActor @Observable
final class RAGSettingsModel {
    private let chat: ProviderSettingsModel
    private let books: any BookRepository
    private let indexCoordinator: BookIndexCoordinator?

    var embeddingModelID = ""
    var embeddingBaseURL = "https://api.siliconflow.cn/v1"
    var embeddingApiKey = ""
    private(set) var embeddingHasSavedKey = false
    private(set) var embeddingEnabled = false
    private(set) var isEmbeddingWorking = false
    private(set) var embeddingStatusMessage: String?

    var rerankerModelID = ""
    var rerankerBaseURL = "https://api.siliconflow.cn/v1"
    var rerankerApiKey = ""
    private(set) var rerankerHasSavedKey = false
    private(set) var rerankerEnabled = false
    private(set) var isRerankerWorking = false
    private(set) var rerankerStatusMessage: String?

    var errorMessage: String?

    init(
        chat: ProviderSettingsModel,
        books: any BookRepository,
        indexCoordinator: BookIndexCoordinator? = nil
    ) {
        self.chat = chat
        self.books = books
        self.indexCoordinator = indexCoordinator
    }

    func load() async {
        guard let configuration = chat.persistedConfiguration() else { return }
        embeddingModelID = configuration.embeddingModelID ?? ""
        embeddingBaseURL = configuration.embeddingBaseURL?.absoluteString ?? configuration.baseURL.absoluteString
        embeddingHasSavedKey = (try? await chat.secrets.secret(for: ProviderSettingsModel.embeddingSecretReference)) != nil
        embeddingEnabled = configuration.embeddingModelID != nil
        rerankerModelID = configuration.rerankerModelID ?? ""
        rerankerBaseURL = configuration.rerankerBaseURL?.absoluteString ?? configuration.baseURL.absoluteString
        rerankerHasSavedKey = (try? await chat.secrets.secret(for: ProviderSettingsModel.rerankerSecretReference)) != nil
        rerankerEnabled = configuration.rerankerModelID != nil
    }

    func clearTransientSecrets() {
        embeddingApiKey = ""
        rerankerApiKey = ""
    }

    /// Chat config deleted: every role's UI state returns to the unconfigured defaults.
    func resetAfterConfigDelete() {
        embeddingModelID = ""
        embeddingBaseURL = "https://api.siliconflow.cn/v1"
        embeddingApiKey = ""
        embeddingHasSavedKey = false
        embeddingEnabled = false
        embeddingStatusMessage = nil
        rerankerModelID = ""
        rerankerBaseURL = "https://api.siliconflow.cn/v1"
        rerankerApiKey = ""
        rerankerHasSavedKey = false
        rerankerEnabled = false
        rerankerStatusMessage = nil
    }

    // MARK: - Embedding role

    /// Picker selection: the matching preset model, or "" for custom/free text.
    /// Selecting a preset also points the role's Base URL at SiliconFlow.
    var embeddingPresetSelection: String {
        get { ProviderSettingsModel.siliconFlowEmbeddingModels.first(where: { $0.model == embeddingModelID })?.model ?? "" }
        set {
            embeddingModelID = newValue
            if !newValue.isEmpty {
                embeddingBaseURL = ModelProviderPreset.siliconFlow.baseURL?.absoluteString ?? embeddingBaseURL
            }
        }
    }

    func testEmbedding() async {
        guard let configuration = embeddingConfiguration() else { return }
        isEmbeddingWorking = true
        embeddingStatusMessage = nil
        defer { isEmbeddingWorking = false }
        do {
            let key = try await embeddingResolvedKey()
            try await ProviderEmbeddingTester().test(configuration: configuration, apiKey: key)
            embeddingStatusMessage = "Embedding 连接成功"
        } catch { errorMessage = ProviderSettingsModel.message(for: error) }
    }

    /// Persists the embedding role (model + its own endpoint/key), then
    /// re-enqueues existing books so the index pipeline picks them up for
    /// semantic indexing (`.lexicalReady` books get an embed-only pass; model
    /// switches get a re-embed).
    func enableEmbedding() async {
        guard let configuration = embeddingConfiguration() else { return }
        isEmbeddingWorking = true
        embeddingStatusMessage = nil
        defer { isEmbeddingWorking = false }
        do {
            let key = try await embeddingResolvedKey()
            try await ProviderEmbeddingTester().test(configuration: configuration, apiKey: key)
            try await chat.saveRoleConfiguration(configuration)
            try await chat.secrets.save(key, for: ProviderSettingsModel.embeddingSecretReference)
            embeddingApiKey = ""
            embeddingHasSavedKey = true
            embeddingEnabled = true
            embeddingStatusMessage = "语义检索已启用，正在为已有书籍建立索引"
            let allBooks = try await books.allBooks()
            await indexCoordinator?.resume(allBooks)
        } catch { errorMessage = ProviderSettingsModel.message(for: error) }
    }

    func disableEmbedding() async {
        guard let base = chat.configuration() else { return }
        let cleared = ProviderConfiguration(
            id: base.id, provider: base.provider, baseURL: base.baseURL,
            modelID: base.modelID, secretReference: base.secretReference,
            streamingEnabled: base.streamingEnabled, embeddingModelID: nil,
            embeddingBaseURL: base.embeddingBaseURL, embeddingSecretReference: base.embeddingSecretReference,
            rerankerModelID: base.rerankerModelID, rerankerBaseURL: base.rerankerBaseURL,
            rerankerSecretReference: base.rerankerSecretReference
        )
        try? await chat.saveRoleConfiguration(cleared)
        embeddingModelID = ""
        embeddingEnabled = false
        embeddingStatusMessage = "语义检索已停用"
    }

    private func embeddingConfiguration() -> ProviderConfiguration? {
        guard let base = chat.configuration() else { return nil }
        let embedding = embeddingModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !embedding.isEmpty else {
            errorMessage = "请填写 Embedding 模型名称。"
            return nil
        }
        guard let url = parsedEndpoint(embeddingBaseURL) else {
            errorMessage = "请填写有效的 Embedding Base URL。"
            return nil
        }
        return ProviderConfiguration(
            id: base.id, provider: base.provider, baseURL: base.baseURL,
            modelID: base.modelID, secretReference: base.secretReference,
            streamingEnabled: base.streamingEnabled, embeddingModelID: embedding,
            embeddingBaseURL: url, embeddingSecretReference: ProviderSettingsModel.embeddingSecretReference,
            rerankerModelID: base.rerankerModelID, rerankerBaseURL: base.rerankerBaseURL,
            rerankerSecretReference: base.rerankerSecretReference
        )
    }

    // MARK: - Reranker role

    var rerankerPresetSelection: String {
        get { ProviderSettingsModel.siliconFlowRerankerModels.first(where: { $0.model == rerankerModelID })?.model ?? "" }
        set {
            rerankerModelID = newValue
            if !newValue.isEmpty {
                rerankerBaseURL = ModelProviderPreset.siliconFlow.baseURL?.absoluteString ?? rerankerBaseURL
            }
        }
    }

    func testReranker() async {
        guard let configuration = rerankerConfiguration() else { return }
        isRerankerWorking = true
        rerankerStatusMessage = nil
        defer { isRerankerWorking = false }
        do {
            let key = try await rerankerResolvedKey()
            try await ProviderRerankerTester().test(configuration: configuration, apiKey: key)
            rerankerStatusMessage = "Reranker 连接成功"
        } catch { errorMessage = ProviderSettingsModel.message(for: error) }
    }

    /// Persists the reranker role. No re-embedding needed — reranking happens
    /// at query time on existing fused candidates.
    func enableReranker() async {
        guard let configuration = rerankerConfiguration() else { return }
        isRerankerWorking = true
        rerankerStatusMessage = nil
        defer { isRerankerWorking = false }
        do {
            let key = try await rerankerResolvedKey()
            try await ProviderRerankerTester().test(configuration: configuration, apiKey: key)
            try await chat.saveRoleConfiguration(configuration)
            try await chat.secrets.save(key, for: ProviderSettingsModel.rerankerSecretReference)
            rerankerApiKey = ""
            rerankerHasSavedKey = true
            rerankerEnabled = true
            rerankerStatusMessage = "Reranker 已启用（检索精排门禁）"
        } catch { errorMessage = ProviderSettingsModel.message(for: error) }
    }

    func disableReranker() async {
        guard let base = chat.configuration() else { return }
        let cleared = ProviderConfiguration(
            id: base.id, provider: base.provider, baseURL: base.baseURL,
            modelID: base.modelID, secretReference: base.secretReference,
            streamingEnabled: base.streamingEnabled, embeddingModelID: base.embeddingModelID,
            embeddingBaseURL: base.embeddingBaseURL, embeddingSecretReference: base.embeddingSecretReference,
            rerankerModelID: nil,
            rerankerBaseURL: base.rerankerBaseURL, rerankerSecretReference: base.rerankerSecretReference
        )
        try? await chat.saveRoleConfiguration(cleared)
        rerankerModelID = ""
        rerankerEnabled = false
        rerankerStatusMessage = "Reranker 已停用"
    }

    private func rerankerConfiguration() -> ProviderConfiguration? {
        guard let base = chat.configuration() else { return nil }
        let reranker = rerankerModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reranker.isEmpty else {
            errorMessage = "请填写 Reranker 模型名称。"
            return nil
        }
        guard let url = parsedEndpoint(rerankerBaseURL) else {
            errorMessage = "请填写有效的 Reranker Base URL。"
            return nil
        }
        return ProviderConfiguration(
            id: base.id, provider: base.provider, baseURL: base.baseURL,
            modelID: base.modelID, secretReference: base.secretReference,
            streamingEnabled: base.streamingEnabled, embeddingModelID: base.embeddingModelID,
            embeddingBaseURL: base.embeddingBaseURL, embeddingSecretReference: base.embeddingSecretReference,
            rerankerModelID: reranker,
            rerankerBaseURL: url, rerankerSecretReference: ProviderSettingsModel.rerankerSecretReference
        )
    }

    // MARK: - Key resolution

    private func embeddingResolvedKey() async throws -> String {
        let typed = embeddingApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        if let saved = try await chat.secrets.secret(for: ProviderSettingsModel.embeddingSecretReference), !saved.isEmpty { return saved }
        throw ModelFailure.invalidConfiguration
    }

    private func rerankerResolvedKey() async throws -> String {
        let typed = rerankerApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        if let saved = try await chat.secrets.secret(for: ProviderSettingsModel.rerankerSecretReference), !saved.isEmpty { return saved }
        throw ModelFailure.invalidConfiguration
    }

    private func parsedEndpoint(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return nil }
        return url
    }
}

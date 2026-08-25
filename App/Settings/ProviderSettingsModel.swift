import AgentRuntime
import AppInfrastructure
import ContextRouting
import Foundation
import LibraryCore
import ModelProviders
import Observation
import ReflectionCore

@MainActor @Observable
final class ProviderSettingsModel {
    private static let secretReference = SecretReference(rawValue: "primary-model-provider")

    /// SiliconFlow embedding model presets (selectable; custom stays editable).
    static let siliconFlowEmbeddingModels: [(name: String, model: String)] = [
        ("BGE-M3（多语言，推荐）", "BAAI/bge-m3"),
        ("BGE Large ZH（中文）", "BAAI/bge-large-zh-v1.5"),
        ("BGE Small ZH（中文轻量）", "BAAI/bge-small-zh-v1.5"),
        ("BGE Large EN（英文）", "BAAI/bge-large-en-v1.5"),
        ("BCE Embedding（中英）", "netease-youdao/bce-embedding-base_v1"),
    ]
    /// SiliconFlow cross-encoder rerank presets (RAG precision gate).
    static let siliconFlowRerankerModels: [(name: String, model: String)] = [
        ("BGE Reranker V2 M3（推荐）", "BAAI/bge-reranker-v2-m3"),
        ("Jina Reranker V2（多语言）", "jina-reranker-v2-base-multilingual"),
    ]

    private let configurations: any ProviderConfigurationRepository
    private let secrets: any SecretStore
    private let traceRepository: (any RoutingTraceRepository)?
    private let books: any BookRepository
    private let files: BookFileStore
    private let exporter: PersonalDataExporter
    private let indexCoordinator: BookIndexCoordinator?
    let ragManagement: RAGManagementModel?
    private let onDataDeleted: (@MainActor () async -> Void)?

    /// Set after a successful export, drives the ShareLink in the 数据 section.
    var exportedDataURL: URL?
    private(set) var isDeletingAllBooks = false

    var selectedPreset: ModelProviderPreset = .openAI
    var baseURL = "https://api.openai.com/v1"
    var modelID = ""
    var apiKey = ""
    var streamingEnabled = false
    /// Separate embedding model for semantic retrieval (independent of the chat model).
    var embeddingModelID = ""
    private(set) var embeddingEnabled = false
    private(set) var isEmbeddingWorking = false
    private(set) var embeddingStatusMessage: String?
    /// Separate cross-encoder rerank model (RAG precision gate).
    var rerankerModelID = ""
    private(set) var rerankerEnabled = false
    private(set) var isRerankerWorking = false
    private(set) var rerankerStatusMessage: String?
    private(set) var hasSavedKey = false
    private(set) var isWorking = false
    private(set) var statusMessage: String?
    private(set) var routingDiagnostics: RoutingTraceDiagnostics?
    var errorMessage: String?

    init(
        configurations: any ProviderConfigurationRepository,
        secrets: any SecretStore,
        traceRepository: (any RoutingTraceRepository)? = nil,
        books: any BookRepository,
        files: BookFileStore,
        exporter: PersonalDataExporter,
        indexCoordinator: BookIndexCoordinator? = nil,
        ragManagement: RAGManagementModel? = nil,
        onDataDeleted: (@MainActor () async -> Void)? = nil
    ) {
        self.configurations = configurations
        self.secrets = secrets
        self.traceRepository = traceRepository
        self.books = books
        self.files = files
        self.exporter = exporter
        self.indexCoordinator = indexCoordinator
        self.ragManagement = ragManagement
        self.onDataDeleted = onDataDeleted
    }

    func load() async {
        do {
            guard let configuration = try await configurations.currentConfiguration() else { return }
            selectedPreset = .matching(baseURL: configuration.baseURL)
            baseURL = configuration.baseURL.absoluteString
            modelID = configuration.modelID
            streamingEnabled = configuration.streamingEnabled
            embeddingModelID = configuration.embeddingModelID ?? ""
            embeddingEnabled = configuration.embeddingModelID != nil
            rerankerModelID = configuration.rerankerModelID ?? ""
            rerankerEnabled = configuration.rerankerModelID != nil
            hasSavedKey = try await secrets.secret(for: configuration.secretReference) != nil
        } catch { errorMessage = Self.message(for: error) }
        await loadDiagnostics()
    }

    func loadDiagnostics() async {
        guard let traceRepository else { return }
        routingDiagnostics = try? await traceRepository.diagnostics()
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
        guard let configuration = configuration() else { return }
        isWorking = true
        statusMessage = nil
        defer { isWorking = false }
        do {
            let key = try await resolvedKey()
            try await ProviderConnectionTester().test(configuration: configuration, apiKey: key)
            statusMessage = "连接成功"
        } catch { errorMessage = Self.message(for: error) }
    }

    // MARK: - 语义检索 (RAG)

    func testEmbedding() async {
        guard let configuration = embeddingConfiguration() else { return }
        isEmbeddingWorking = true
        embeddingStatusMessage = nil
        defer { isEmbeddingWorking = false }
        do {
            let key = try await resolvedKey()
            try await ProviderEmbeddingTester().test(configuration: configuration, apiKey: key)
            embeddingStatusMessage = "Embedding 连接成功"
        } catch { errorMessage = Self.message(for: error) }
    }

    /// Persists the embedding model, then re-enqueues existing books so the
    /// index pipeline picks them up for semantic indexing (`.lexicalReady` books
    /// get an embed-only pass; model switches get a re-embed).
    func enableEmbedding() async {
        guard let configuration = embeddingConfiguration() else { return }
        isEmbeddingWorking = true
        embeddingStatusMessage = nil
        defer { isEmbeddingWorking = false }
        do {
            let key = try await resolvedKey()
            try await ProviderEmbeddingTester().test(configuration: configuration, apiKey: key)
            try await configurations.save(configuration)
            embeddingEnabled = true
            embeddingStatusMessage = "语义检索已启用，正在为已有书籍建立索引"
            let allBooks = try await books.allBooks()
            await indexCoordinator?.resume(allBooks)
        } catch { errorMessage = Self.message(for: error) }
    }

    func disableEmbedding() async {
        guard let base = configuration() else { return }
        let config = ProviderConfiguration(
            id: base.id, provider: base.provider, baseURL: base.baseURL,
            modelID: base.modelID, secretReference: base.secretReference,
            streamingEnabled: base.streamingEnabled, embeddingModelID: nil,
            rerankerModelID: base.rerankerModelID
        )
        try? await configurations.save(config)
        embeddingModelID = ""
        embeddingEnabled = false
        embeddingStatusMessage = "语义检索已停用"
    }

    // MARK: - Reranker（RAG 精排门禁）

    func testReranker() async {
        guard let configuration = rerankerConfiguration() else { return }
        isRerankerWorking = true
        rerankerStatusMessage = nil
        defer { isRerankerWorking = false }
        do {
            let key = try await resolvedKey()
            try await ProviderRerankerTester().test(configuration: configuration, apiKey: key)
            rerankerStatusMessage = "Reranker 连接成功"
        } catch { errorMessage = Self.message(for: error) }
    }

    /// Persists the reranker model. No re-embedding needed — reranking happens
    /// at query time on existing fused candidates.
    func enableReranker() async {
        guard let configuration = rerankerConfiguration() else { return }
        isRerankerWorking = true
        rerankerStatusMessage = nil
        defer { isRerankerWorking = false }
        do {
            let key = try await resolvedKey()
            try await ProviderRerankerTester().test(configuration: configuration, apiKey: key)
            try await configurations.save(configuration)
            rerankerEnabled = true
            rerankerStatusMessage = "Reranker 已启用（检索精排门禁）"
        } catch { errorMessage = Self.message(for: error) }
    }

    func disableReranker() async {
        guard let base = configuration() else { return }
        let config = ProviderConfiguration(
            id: base.id, provider: base.provider, baseURL: base.baseURL,
            modelID: base.modelID, secretReference: base.secretReference,
            streamingEnabled: base.streamingEnabled, embeddingModelID: base.embeddingModelID,
            rerankerModelID: nil
        )
        try? await configurations.save(config)
        rerankerModelID = ""
        rerankerEnabled = false
        rerankerStatusMessage = "Reranker 已停用"
    }

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
            apiKey = ""
            hasSavedKey = false
            statusMessage = "配置和 API Key 已删除"
        } catch { errorMessage = Self.message(for: error) }
    }

    private func configuration() -> ProviderConfiguration? {
        let model = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let embedding = embeddingModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let reranker = rerankerModelID.trimmingCharacters(in: .whitespacesAndNewlines)
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
            embeddingModelID: embedding.isEmpty ? nil : embedding,
            rerankerModelID: reranker.isEmpty ? nil : reranker
        )
    }

    /// Picker selection: the matching preset model, or "" for custom/free text.
    var embeddingPresetSelection: String {
        get { Self.siliconFlowEmbeddingModels.first(where: { $0.model == embeddingModelID })?.model ?? "" }
        set { embeddingModelID = newValue }
    }

    var rerankerPresetSelection: String {
        get { Self.siliconFlowRerankerModels.first(where: { $0.model == rerankerModelID })?.model ?? "" }
        set { rerankerModelID = newValue }
    }

    private func embeddingConfiguration() -> ProviderConfiguration? {
        guard let base = configuration() else { return nil }
        let embedding = embeddingModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !embedding.isEmpty else {
            errorMessage = "请填写 Embedding 模型名称。"
            return nil
        }
        return ProviderConfiguration(
            id: base.id, provider: base.provider, baseURL: base.baseURL,
            modelID: base.modelID, secretReference: base.secretReference,
            streamingEnabled: base.streamingEnabled, embeddingModelID: embedding,
            rerankerModelID: base.rerankerModelID
        )
    }

    private func rerankerConfiguration() -> ProviderConfiguration? {
        guard let base = configuration() else { return nil }
        let reranker = rerankerModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reranker.isEmpty else {
            errorMessage = "请填写 Reranker 模型名称。"
            return nil
        }
        return ProviderConfiguration(
            id: base.id, provider: base.provider, baseURL: base.baseURL,
            modelID: base.modelID, secretReference: base.secretReference,
            streamingEnabled: base.streamingEnabled, embeddingModelID: base.embeddingModelID,
            rerankerModelID: reranker
        )
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

    // MARK: - 数据控制

    /// Runs the exporter and writes the pretty JSON to a temp file the view can
    /// hand to a ShareLink. Provider configuration and Keychain are never read.
    func exportMyData() async {
        do {
            let data = try await exporter.export()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("elsepage-my-data.json")
            try data.write(to: url, options: .atomic)
            exportedDataURL = url
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Deletes every book's DB record (FK cascade removes positions, highlights,
    /// notes, preferences, sessions, reflections, journal and index rows) plus
    /// its sandbox EPUB file, mirroring LibraryModel's two-phase trash flow per
    /// book. Provider configuration and Keychain stay untouched.
    func deleteAllBooks() async {
        guard !isDeletingAllBooks else { return }
        isDeletingAllBooks = true
        defer { isDeletingAllBooks = false }
        indexCoordinator?.cancelAll()
        do {
            let allBooks = try await books.allBooks()
            for book in allBooks {
                let trashed = try files.stageDeletion(bookID: book.id)
                do {
                    try await books.delete(book.id)
                    files.commitDeletion(trashed)
                } catch {
                    if let trashed { try? files.restore(trashed, for: book.id) }
                    throw error
                }
            }
            exportedDataURL = nil
            await onDataDeleted?()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func clearTransientSecret() { apiKey = "" }

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

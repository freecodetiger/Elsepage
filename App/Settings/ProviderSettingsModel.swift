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

    private let configurations: any ProviderConfigurationRepository
    private let secrets: any SecretStore
    private let traceRepository: (any RoutingTraceRepository)?
    private let books: any BookRepository
    private let files: BookFileStore
    private let exporter: PersonalDataExporter
    private let indexCoordinator: BookIndexCoordinator?
    private let onDataDeleted: (@MainActor () async -> Void)?

    /// Set after a successful export, drives the ShareLink in the 数据 section.
    var exportedDataURL: URL?
    private(set) var isDeletingAllBooks = false

    var selectedPreset: ModelProviderPreset = .openAI
    var baseURL = "https://api.openai.com/v1"
    var modelID = ""
    var apiKey = ""
    var streamingEnabled = false
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
        onDataDeleted: (@MainActor () async -> Void)? = nil
    ) {
        self.configurations = configurations
        self.secrets = secrets
        self.traceRepository = traceRepository
        self.books = books
        self.files = files
        self.exporter = exporter
        self.indexCoordinator = indexCoordinator
        self.onDataDeleted = onDataDeleted
    }

    func load() async {
        do {
            guard let configuration = try await configurations.currentConfiguration() else { return }
            selectedPreset = .matching(baseURL: configuration.baseURL)
            baseURL = configuration.baseURL.absoluteString
            modelID = configuration.modelID
            streamingEnabled = configuration.streamingEnabled
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
            streamingEnabled: streamingEnabled
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

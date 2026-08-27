import AgentRuntime
import AppInfrastructure
import ContextEngineering
import Foundation
import ModelProviders
import Observation
import Persistence
import ReaderAgent
import ReadingSessionCore
import ReflectionCore
import RetrievalCore

@MainActor @Observable
final class AppModel {
    private(set) var library: LibraryModel?
    private(set) var thoughts: ThoughtsModel?
    private(set) var myMind: MyMindModel?
    private(set) var settings: SettingsRootModel?
    private(set) var startupError: String?
    /// A file URL received via "用 ReadLoop 打开" (Files / Share Sheet / AirDrop)
    /// while the library wasn't ready yet (e.g. during cold launch). Buffered until
    /// `start()` has finished wiring the object graph, then imported once.
    private var pendingImportURL: URL?
    /// Set when an external document import lands, so AppShell can surface the
    /// result by switching to 书架.
    var openLibraryAfterExternalImport = false

    func start() async {
        guard library == nil, startupError == nil else { return }
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let databaseDirectory = support.appendingPathComponent("Database", isDirectory: true)
            try FileManager.default.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
            let database = try AppDatabase(path: databaseDirectory.appendingPathComponent("readloop.sqlite").path)
            let books = GRDBBookRepository(database: database)
            let reading = GRDBReadingRepository(database: database)
            let sessions = GRDBReadingSessionRepository(database: database)
            let reflections = GRDBReflectionRepository(database: database)
            let journal = GRDBJournalRepository(database: database)
            let memories = GRDBMemoryRepository(database: database)
            let bookIndex = GRDBBookIndexRepository(database: database)
            let providerConfigurations = GRDBProviderConfigurationRepository(database: database)
            let secrets = KeychainSecretStore()
            let routingTraces = GRDBRoutingTraceRepository(database: database)
            let modelClientFactory = ConfiguredModelClientFactory(
                configurations: providerConfigurations,
                secrets: secrets
            )
            // Resolves the configured embedding provider (separate model, enabled
            // in Settings) at run time. Returns nil when disabled, so semantic
            // retrieval degrades to lexical without rebuilding the object graph.
            let makeEmbeddingProvider: @Sendable () async -> (any EmbeddingProvider)? = { [providerConfigurations, secrets] in
                guard let configuration = try? await providerConfigurations.currentConfiguration(),
                      let model = configuration.embeddingModelID, !model.isEmpty,
                      let key = try? await secrets.secret(for: configuration.effectiveEmbeddingSecretReference), !key.isEmpty else { return nil }
                return try? OpenAICompatibleEmbeddingProvider(configuration: configuration, apiKey: key)
            }
            // Optional cross-encoder rerank gate (RAG precision). Resolved at
            // query time so Settings enable/disable takes effect immediately.
            let makeReranker: @Sendable () async -> (any Reranker)? = { [providerConfigurations, secrets] in
                guard let configuration = try? await providerConfigurations.currentConfiguration(),
                      let model = configuration.rerankerModelID, !model.isEmpty,
                      let key = try? await secrets.secret(for: configuration.effectiveRerankerSecretReference), !key.isEmpty else { return nil }
                return try? SiliconFlowReranker(configuration: configuration, apiKey: key)
            }
            let readerAgent = ReaderAgent(
                reflections: reflections,
                models: modelClientFactory,
                contextBuilder: ReaderAgentContextBuilder(
                    retriever: LocalBookRetriever(repository: bookIndex, embeddingProvider: makeEmbeddingProvider, reranker: makeReranker),
                    repository: bookIndex
                ),
                sessionContextBuilder: SessionContextBuilder(
                    sessions: sessions,
                    reading: reading,
                    reflections: reflections
                ),
                traceRepository: routingTraces,
                memories: memories,
                // Reflection/Memory semantic recall lane (Phase 5): query-time embed
                // behind a process-local cache; nil provider degrades to lexical.
                semanticRanking: QueryTimeSemanticRanking(embeddingFactory: makeEmbeddingProvider)
            )
            // Standalone voice-polish chain sharing the same BYOK provider (independent of ReaderAgent).
            // Re-checked every time a reflection sheet opens, so the polish button appears as soon
            // as a provider is configured even if the key is added after launch.
            let makePolishService: @MainActor () async -> TranscriptPolishService? = { [providerConfigurations, modelClientFactory] in
                guard (try? await providerConfigurations.currentConfiguration()) != nil else { return nil }
                return TranscriptPolishService(clientFactory: modelClientFactory)
            }
            let files = try BookFileStore(directory: support.appendingPathComponent("Books", isDirectory: true))
            let readium = ReadiumServices()
            let indexCoordinator = BookIndexCoordinator(
                repository: bookIndex,
                readium: readium,
                files: files,
                embeddings: makeEmbeddingProvider
            )
            let ragManagement = RAGManagementModel(
                service: BookIndexStatusService(
                    books: books,
                    repository: bookIndex,
                    currentEmbeddingModel: { await makeEmbeddingProvider()?.modelIdentifier }
                ),
                coordinator: indexCoordinator
            )
            library = LibraryModel(
                books: books,
                reading: reading,
                sessions: sessions,
                reflections: reflections,
                readerAgent: readerAgent,
                makePolishService: makePolishService,
                files: files,
                metadataReader: ReadiumMetadataReader(readium: readium),
                readium: readium,
                indexCoordinator: indexCoordinator
            )
            let chatSettings = ProviderSettingsModel(configurations: providerConfigurations, secrets: secrets)
            let ragSettings = RAGSettingsModel(chat: chatSettings, books: books, indexCoordinator: indexCoordinator)
            let diagnosticsSettings = DiagnosticsModel(traceRepository: routingTraces)
            let dataSettings = DataSettingsModel(
                books: books,
                files: files,
                exporter: PersonalDataExporter(
                    books: books,
                    reading: reading,
                    sessions: sessions,
                    reflections: reflections,
                    journal: journal
                ),
                indexCoordinator: indexCoordinator,
                onDataDeleted: { [weak self] in
                    await self?.library?.reload()
                    await self?.thoughts?.reload()
                }
            )
            settings = SettingsRootModel(
                chat: chatSettings,
                rag: ragSettings,
                diagnostics: diagnosticsSettings,
                data: dataSettings,
                ragManagement: ragManagement
            )
            thoughts = ThoughtsModel(
                books: books,
                reflections: reflections,
                sessions: sessions,
                reading: reading,
                index: bookIndex,
                journal: journal,
                readerAgent: readerAgent,
                traceRepository: routingTraces,
                memoryRepository: memories
            )
            myMind = MyMindModel(
                memories: memories,
                reflections: reflections,
                books: books
            )
            await settings?.loadAll()
            await library?.reload()
            await library?.resumeBookIndexing()
            await importPendingIfReady()
        } catch {
            startupError = error.localizedDescription
        }
    }

    /// Entry point for documents delivered by the system ("用 ReadLoop 打开").
    /// Safe to call before or after startup; the URL is drained once the library exists.
    func handleIncoming(_ url: URL) async {
        pendingImportURL = url
        await importPendingIfReady()
    }

    private func importPendingIfReady() async {
        guard let url = pendingImportURL, let library else { return }
        pendingImportURL = nil
        await library.importBook(url)
        openLibraryAfterExternalImport = true
    }
}

import AgentRuntime
import AppInfrastructure
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
    private(set) var providerSettings: ProviderSettingsModel?
    private(set) var startupError: String?

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
                      let key = try? await secrets.secret(for: configuration.secretReference), !key.isEmpty else { return nil }
                return try? OpenAICompatibleEmbeddingProvider(configuration: configuration, apiKey: key)
            }
            // Optional cross-encoder rerank gate (RAG precision). Resolved at
            // query time so Settings enable/disable takes effect immediately.
            let makeReranker: @Sendable () async -> (any Reranker)? = { [providerConfigurations, secrets] in
                guard let configuration = try? await providerConfigurations.currentConfiguration(),
                      let model = configuration.rerankerModelID, !model.isEmpty,
                      let key = try? await secrets.secret(for: configuration.secretReference), !key.isEmpty else { return nil }
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
                memories: memories
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
            providerSettings = ProviderSettingsModel(
                configurations: providerConfigurations,
                secrets: secrets,
                traceRepository: routingTraces,
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
                ragManagement: ragManagement,
                onDataDeleted: { [weak self] in
                    await self?.library?.reload()
                    await self?.thoughts?.reload()
                }
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
            await providerSettings?.load()
            await library?.reload()
            await library?.resumeBookIndexing()
        } catch {
            startupError = error.localizedDescription
        }
    }
}

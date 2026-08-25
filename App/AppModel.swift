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
            let bookIndex = GRDBBookIndexRepository(database: database)
            let providerConfigurations = GRDBProviderConfigurationRepository(database: database)
            let secrets = KeychainSecretStore()
            let routingTraces = GRDBRoutingTraceRepository(database: database)
            let modelClientFactory = ConfiguredModelClientFactory(
                configurations: providerConfigurations,
                secrets: secrets
            )
            let readerAgent = ReaderAgent(
                reflections: reflections,
                models: modelClientFactory,
                contextBuilder: ReaderAgentContextBuilder(
                    retriever: LocalBookRetriever(repository: bookIndex),
                    repository: bookIndex
                ),
                sessionContextBuilder: SessionContextBuilder(
                    sessions: sessions,
                    reading: reading,
                    reflections: reflections
                ),
                traceRepository: routingTraces
            )
            // Standalone voice-polish chain sharing the same BYOK provider (independent of ReaderAgent).
            let polishService = TranscriptPolishService(clientFactory: modelClientFactory)
            let files = try BookFileStore(directory: support.appendingPathComponent("Books", isDirectory: true))
            let readium = ReadiumServices()
            let indexCoordinator = BookIndexCoordinator(repository: bookIndex, readium: readium, files: files)
            library = LibraryModel(
                books: books,
                reading: reading,
                sessions: sessions,
                reflections: reflections,
                readerAgent: readerAgent,
                polishService: polishService,
                files: files,
                metadataReader: ReadiumMetadataReader(readium: readium),
                readium: readium,
                indexCoordinator: indexCoordinator
            )
            providerSettings = ProviderSettingsModel(
                configurations: providerConfigurations,
                secrets: secrets,
                traceRepository: routingTraces
            )
            thoughts = ThoughtsModel(
                books: books,
                reflections: reflections,
                sessions: sessions,
                reading: reading,
                index: bookIndex,
                journal: journal,
                readerAgent: readerAgent,
                traceRepository: routingTraces
            )
            await providerSettings?.load()
            await library?.reload()
            await library?.resumeBookIndexing()
        } catch {
            startupError = error.localizedDescription
        }
    }
}

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
            let bookIndex = GRDBBookIndexRepository(database: database)
            let providerConfigurations = GRDBProviderConfigurationRepository(database: database)
            let secrets = KeychainSecretStore()
            let readerAgent = ReaderAgent(
                reflections: reflections,
                models: ConfiguredModelClientFactory(
                    configurations: providerConfigurations,
                    secrets: secrets
                ),
                contextBuilder: ReaderAgentContextBuilder(
                    retriever: LocalBookRetriever(repository: bookIndex),
                    repository: bookIndex
                ),
                sessionContextBuilder: SessionContextBuilder(
                    sessions: sessions,
                    reading: reading,
                    reflections: reflections
                )
            )
            let files = try BookFileStore(directory: support.appendingPathComponent("Books", isDirectory: true))
            let readium = ReadiumServices()
            let indexCoordinator = BookIndexCoordinator(repository: bookIndex, readium: readium, files: files)
            library = LibraryModel(
                books: books,
                reading: reading,
                sessions: sessions,
                reflections: reflections,
                readerAgent: readerAgent,
                files: files,
                metadataReader: ReadiumMetadataReader(readium: readium),
                readium: readium,
                indexCoordinator: indexCoordinator
            )
            providerSettings = ProviderSettingsModel(
                configurations: providerConfigurations,
                secrets: secrets
            )
            thoughts = ThoughtsModel(
                books: books,
                reflections: reflections,
                readerAgent: readerAgent
            )
            await providerSettings?.load()
            await library?.reload()
            await library?.resumeBookIndexing()
        } catch {
            startupError = error.localizedDescription
        }
    }
}

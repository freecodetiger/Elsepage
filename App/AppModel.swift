import AppInfrastructure
import Foundation
import Observation
import Persistence
import ReadingSessionCore
import ReflectionCore

@MainActor @Observable
final class AppModel {
    private(set) var library: LibraryModel?
    private(set) var thoughts: ThoughtsModel?
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
            let files = try BookFileStore(directory: support.appendingPathComponent("Books", isDirectory: true))
            let readium = ReadiumServices()
            library = LibraryModel(
                books: books,
                reading: reading,
                sessions: sessions,
                reflections: reflections,
                files: files,
                metadataReader: ReadiumMetadataReader(readium: readium),
                readium: readium
            )
            thoughts = ThoughtsModel(books: books, reflections: reflections)
            await library?.reload()
        } catch {
            startupError = error.localizedDescription
        }
    }
}

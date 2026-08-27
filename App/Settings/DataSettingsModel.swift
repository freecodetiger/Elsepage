import AppInfrastructure
import Foundation
import LibraryCore
import Observation
import ReflectionCore

/// Data / privacy settings: export the personal data store and destructive
/// "delete every book + index" (with the existing two-phase trash flow).
@MainActor @Observable
final class DataSettingsModel {
    private let books: any BookRepository
    private let files: BookFileStore
    private let exporter: PersonalDataExporter
    private let indexCoordinator: BookIndexCoordinator?
    private let onDataDeleted: (@MainActor () async -> Void)?

    /// Set after a successful export, drives the ShareLink in the data page.
    var exportedDataURL: URL?
    private(set) var isDeletingAllBooks = false
    var errorMessage: String?

    init(
        books: any BookRepository,
        files: BookFileStore,
        exporter: PersonalDataExporter,
        indexCoordinator: BookIndexCoordinator? = nil,
        onDataDeleted: (@MainActor () async -> Void)? = nil
    ) {
        self.books = books
        self.files = files
        self.exporter = exporter
        self.indexCoordinator = indexCoordinator
        self.onDataDeleted = onDataDeleted
    }

    /// Runs the exporter and writes the pretty JSON to a temp file the view can
    /// hand to a ShareLink. Provider configuration and Keychain are never read.
    func exportMyData() async {
        do {
            let data = try await exporter.export()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("elsepage-my-data.json")
            try data.write(to: url, options: .atomic)
            exportedDataURL = url
        } catch {
            errorMessage = ProviderSettingsModel.message(for: error)
        }
    }

    /// Deletes every book's DB record (FK cascade removes positions, highlights,
    /// notes, preferences, sessions, reflections, journal and index rows) plus
    /// its sandbox EPUB file. Provider configuration and Keychain stay untouched.
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
            errorMessage = ProviderSettingsModel.message(for: error)
        }
    }
}

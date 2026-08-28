import AppInfrastructure
import Foundation
import LibraryCore
import Observation
import Persistence
import ReflectionCore

/// Data / privacy settings: export the personal data store, the destructive
/// "delete every book + index" (with the existing two-phase trash flow), and
/// the one-tap "清除所有本地数据" reset (two-stage confirmation in the view).
@MainActor @Observable
final class DataSettingsModel {
    private let books: any BookRepository
    private let files: BookFileStore
    private let exporter: PersonalDataExporter
    private let indexCoordinator: BookIndexCoordinator?
    private let wipeService: LocalDataWipeService?
    private let clearUserDefaults: () -> Void
    private let onDataDeleted: (@MainActor () async -> Void)?
    private let onAllDataWiped: (@MainActor () async -> Void)?

    /// Set after a successful export, drives the ShareLink in the data page.
    var exportedDataURL: URL?
    private(set) var isDeletingAllBooks = false
    private(set) var isWipingAllData = false
    var errorMessage: String?

    init(
        books: any BookRepository,
        files: BookFileStore,
        exporter: PersonalDataExporter,
        indexCoordinator: BookIndexCoordinator? = nil,
        wipeService: LocalDataWipeService? = nil,
        onDataDeleted: (@MainActor () async -> Void)? = nil,
        onAllDataWiped: (@MainActor () async -> Void)? = nil,
        clearUserDefaults: @escaping () -> Void = {
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
            }
        }
    ) {
        self.books = books
        self.files = files
        self.exporter = exporter
        self.indexCoordinator = indexCoordinator
        self.wipeService = wipeService
        self.onDataDeleted = onDataDeleted
        self.onAllDataWiped = onAllDataWiped
        self.clearUserDefaults = clearUserDefaults
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

    /// 清除所有本地数据 (PRD §13.3): every book + file, index, position, highlight,
    /// note, session, reflection (incl. journal tables), memory, achievement,
    /// provider configuration and Keychain credential, plus the app's own
    /// UserDefaults domain — after which the app returns to first-launch state.
    /// Files follow the same two-phase trash flow as `deleteAllBooks`, so a
    /// database failure restores every EPUB before the error surfaces.
    func wipeAllLocalData() async {
        guard let wipeService, !isWipingAllData else { return }
        isWipingAllData = true
        defer { isWipingAllData = false }
        indexCoordinator?.cancelAll()
        do {
            let staged = try await stageAllBookFilesForDeletion()
            do {
                try await wipeService.wipeAllUserData()
            } catch {
                restoreStagedBookFiles(staged)
                throw error
            }
            staged.forEach { files.commitDeletion($0.trashed) }
            files.removeAllBookFiles()
            clearUserDefaults()
            exportedDataURL = nil
            await onAllDataWiped?()
        } catch {
            errorMessage = ProviderSettingsModel.message(for: error)
        }
    }

    private struct StagedBookDeletion {
        let bookID: BookID
        let trashed: TrashedBookFile?
    }

    private func stageAllBookFilesForDeletion() async throws -> [StagedBookDeletion] {
        try await books.allBooks().map { book in
            StagedBookDeletion(bookID: book.id, trashed: try files.stageDeletion(bookID: book.id))
        }
    }

    private func restoreStagedBookFiles(_ staged: [StagedBookDeletion]) {
        for entry in staged.reversed() {
            if let trashed = entry.trashed { try? files.restore(trashed, for: entry.bookID) }
        }
    }
}

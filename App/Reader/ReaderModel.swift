import Foundation
import LibraryCore
import Observation
import ReaderCore

@MainActor @Observable
final class ReaderModel {
    let book: Book
    let fileURL: URL
    let repository: any ReadingRepository
    private let books: any BookRepository
    let readium: ReadiumServices
    var initialLocatorJSON: Data?
    var errorMessage: String?
    private(set) var isPrepared = false

    init(book: Book, fileURL: URL, repository: any ReadingRepository, books: any BookRepository, readium: ReadiumServices) {
        self.book = book; self.fileURL = fileURL; self.repository = repository; self.books = books
        self.readium = readium
    }
    func prepare() async {
        defer { isPrepared = true }
        do {
            initialLocatorJSON = try await repository.position(for: book.id)?.locator.json
            try await books.markOpened(book.id, at: Date())
        } catch { errorMessage = error.localizedDescription }
    }
    func save(locator: BookLocator) {
        Task { await reportPersistenceError { try await repository.save(position: .init(bookID: book.id, locator: locator)) } }
    }
    func saveHighlight(locator: BookLocator) {
        Task { await reportPersistenceError { try await repository.save(highlight: .init(bookID: book.id, locator: locator)) } }
    }
    func saveNote(locator: BookLocator, body: String) {
        Task { await reportPersistenceError { try await repository.save(note: .init(bookID: book.id, locator: locator, body: body)) } }
    }
    private func reportPersistenceError(_ operation: @escaping @Sendable () async throws -> Void) async {
        do { try await operation() }
        catch { errorMessage = error.localizedDescription }
    }
}

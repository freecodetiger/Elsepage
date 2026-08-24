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
    var preferences: ReaderPreferences = .default
    var highlights: [Highlight] = []
    var chapters: [ReaderChapter] = []
    var currentChapterTitle: String?
    var progress: Double = 0
    var showsControls = true
    var jumpTargetJSON: Data?
    private(set) var isPrepared = false

    init(book: Book, fileURL: URL, repository: any ReadingRepository, books: any BookRepository, readium: ReadiumServices) {
        self.book = book; self.fileURL = fileURL; self.repository = repository; self.books = books
        self.readium = readium
    }
    func prepare() async {
        defer { isPrepared = true }
        do {
            let position = try await repository.position(for: book.id)
            initialLocatorJSON = position?.locator.json
            progress = position?.locator.totalProgression ?? 0
            preferences = try await repository.preferences(for: book.id)
            highlights = try await repository.highlights(for: book.id)
            try await books.markOpened(book.id, at: Date())
        } catch { errorMessage = error.localizedDescription }
    }
    func save(locator: BookLocator) {
        progress = locator.totalProgression ?? progress
        let resource = locator.href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? locator.href
        currentChapterTitle = chapters.last { chapter in
            (chapter.href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? chapter.href) == resource
        }?.title ?? currentChapterTitle
        Task { await reportPersistenceError { try await self.repository.save(position: .init(bookID: self.book.id, locator: locator)) } }
    }
    func saveHighlight(locator: BookLocator) {
        let highlight = Highlight(bookID: book.id, locator: locator)
        highlights.append(highlight)
        Task {
            do { try await repository.save(highlight: highlight) }
            catch {
                highlights.removeAll { $0.id == highlight.id }
                errorMessage = error.localizedDescription
            }
        }
    }
    func saveNote(locator: BookLocator, body: String) {
        Task { await reportPersistenceError { try await self.repository.save(note: .init(bookID: self.book.id, locator: locator, body: body)) } }
    }
    func savePreferences() {
        let value = preferences
        Task { await reportPersistenceError { try await self.repository.save(preferences: value, for: self.book.id) } }
    }
    func jump(to chapter: ReaderChapter) {
        jumpTargetJSON = chapter.locatorJSON
        currentChapterTitle = chapter.title
    }
    func toggleControls() {
        showsControls.toggle()
    }
    private func reportPersistenceError(_ operation: @escaping @Sendable () async throws -> Void) async {
        do { try await operation() }
        catch { errorMessage = error.localizedDescription }
    }
}

struct ReaderChapter: Identifiable, Hashable {
    let id: String
    let title: String
    let depth: Int
    let href: String
    let locatorJSON: Data
}

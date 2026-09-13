#if DEBUG
import Foundation
import LibraryCore
import ReaderCore
import ReadingSessionCore

/// An isolated real GRDB graph for device scenarios and package tests.
/// Never opens the user's database, files, defaults or Keychain.
public struct ReflectionTestEnvironment: Sendable {
    public let reflections: GRDBReflectionRepository
    public let sessions: GRDBReadingSessionRepository
    public let book: Book
    public let session: ReadingSession
    public let locator: BookLocator

    public static func make() async throws -> Self {
        let database = try AppDatabase.inMemory()
        let books = GRDBBookRepository(database: database)
        let sessions = GRDBReadingSessionRepository(database: database)
        let reflections = GRDBReflectionRepository(database: database)
        let book = Book(fingerprint: .init(rawValue: "debug-loop-fixture"),
                        title: "测试书籍", fileName: "fixture.epub", fileSize: 0)
        let locator = try BookLocator(json: Data("{\"href\":\"chapter.xhtml\"}".utf8), href: "chapter.xhtml")
        let session = ReadingSession(bookID: book.id, startedAt: Date(timeIntervalSince1970: 100),
                                     endedAt: Date(timeIntervalSince1970: 400),
                                     startLocator: locator, endLocator: locator)
        try await books.insert(book)
        try await sessions.insert(session)
        return Self(reflections: reflections, sessions: sessions, book: book, session: session, locator: locator)
    }
}
#endif

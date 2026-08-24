import Foundation
import LibraryCore

/// A read-only projection of local Reflection source data for the Thoughts feature.
public struct ReflectionArchiveEntry: Hashable, Sendable, Identifiable {
    public let reflection: Reflection
    public let book: Book
    public let derivedAgentResponse: ReflectionMessage?

    public var id: ReflectionID { reflection.id }

    public init(reflection: Reflection, book: Book, derivedAgentResponse: ReflectionMessage?) {
        self.reflection = reflection
        self.book = book
        self.derivedAgentResponse = derivedAgentResponse
    }
}

/// Loads the source archive without inferring Memory, profile, or connections.
public struct ReflectionArchiveService: Sendable {
    private let books: any BookRepository
    private let reflections: any ReflectionRepository

    public init(books: any BookRepository, reflections: any ReflectionRepository) {
        self.books = books
        self.reflections = reflections
    }

    public func recentEntries() async throws -> [ReflectionArchiveEntry] {
        let library = try await books.allBooks()
        var entries: [ReflectionArchiveEntry] = []
        for book in library {
            let items = try await reflections.reflections(for: book.id)
            for reflection in items {
                let messages = try await reflections.messages(for: reflection.id)
                entries.append(.init(
                    reflection: reflection,
                    book: book,
                    derivedAgentResponse: messages.last(where: { $0.source == .agentGenerated })
                ))
            }
        }
        return entries.sorted { $0.reflection.createdAt > $1.reflection.createdAt }
    }
}

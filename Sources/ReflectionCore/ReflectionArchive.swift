import Foundation
import LibraryCore
import ReaderCore

/// A read-only projection of local Reflection source data for the Thoughts feature.
public struct ReflectionArchiveEntry: Hashable, Sendable, Identifiable {
    public let reflection: Reflection
    public let book: Book
    public let messages: [ReflectionMessage]
    public let evidence: [ReflectionEvidence]
    public let connections: [ReflectionArchiveConnection]
    public let responseProvenance: [UUID: AgentResponseProvenance]

    public var derivedAgentResponse: ReflectionMessage? {
        messages.last(where: { $0.source == .agentGenerated })
    }

    public var sourceLocator: BookLocator? {
        evidence.first(where: { $0.sourceType == .bookLocator })?.locator
    }

    public var id: ReflectionID { reflection.id }

    public init(
        reflection: Reflection,
        book: Book,
        messages: [ReflectionMessage] = [],
        evidence: [ReflectionEvidence] = [],
        connections: [ReflectionArchiveConnection] = [],
        responseProvenance: [UUID: AgentResponseProvenance] = [:]
    ) {
        self.reflection = reflection
        self.book = book
        self.messages = messages
        self.evidence = evidence
        self.connections = connections
        self.responseProvenance = responseProvenance
    }
}

public struct ReflectionArchiveConnection: Hashable, Sendable, Identifiable {
    public let connection: ReflectionConnection
    public let sourceReflection: Reflection
    public let sourceBook: Book
    public let sourceLocator: BookLocator?
    public var id: UUID { connection.id }

    public init(
        connection: ReflectionConnection,
        sourceReflection: Reflection,
        sourceBook: Book,
        sourceLocator: BookLocator?
    ) {
        self.connection = connection
        self.sourceReflection = sourceReflection
        self.sourceBook = sourceBook
        self.sourceLocator = sourceLocator
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
        let booksByID = Dictionary(uniqueKeysWithValues: library.map { ($0.id, $0) })
        var entries: [ReflectionArchiveEntry] = []
        for book in library {
            let items = try await reflections.reflections(for: book.id)
            for reflection in items {
                let messages = try await reflections.messages(for: reflection.id)
                let evidence = try await reflections.evidence(for: reflection.id)
                var responseProvenance: [UUID: AgentResponseProvenance] = [:]
                for message in messages where message.author == .agent {
                    responseProvenance[message.id] = try await reflections.provenance(for: message.id)
                }
                let connections = try await reflections.connections(for: reflection.id)
                var archiveConnections: [ReflectionArchiveConnection] = []
                for connection in connections {
                    guard let source = try await reflections.reflection(id: connection.sourceReflectionID),
                          let sourceBook = booksByID[source.bookID] else { continue }
                    let sourceEvidence = try await reflections.evidence(for: source.id)
                    archiveConnections.append(.init(
                        connection: connection,
                        sourceReflection: source,
                        sourceBook: sourceBook,
                        sourceLocator: sourceEvidence.first(where: { $0.sourceType == .bookLocator })?.locator
                    ))
                }
                entries.append(.init(
                    reflection: reflection,
                    book: book,
                    messages: messages,
                    evidence: evidence,
                    connections: archiveConnections,
                    responseProvenance: responseProvenance
                ))
            }
        }
        return entries.sorted { $0.reflection.createdAt > $1.reflection.createdAt }
    }
}

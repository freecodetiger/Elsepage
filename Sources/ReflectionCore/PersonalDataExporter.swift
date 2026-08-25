import Foundation
import LibraryCore
import ReaderCore
import ReadingSessionCore

/// A snapshot of everything the user has authored or produced while reading.
/// Deliberately excludes provider configuration, API keys, secret references,
/// routing traces and any other non-user data.
public struct PersonalDataArchive: Codable, Sendable {
    public var exportedAt: Date
    public var books: [BookEntry]

    public struct BookEntry: Codable, Sendable {
        public var book: Book
        public var readingPosition: ReadingPosition?
        public var highlights: [Highlight]
        public var notes: [Note]
        public var preferences: ReaderPreferences
        public var sessions: [ReadingSession]
        public var reflections: [ReflectionEntry]

        public init(
            book: Book,
            readingPosition: ReadingPosition?,
            highlights: [Highlight],
            notes: [Note],
            preferences: ReaderPreferences,
            sessions: [ReadingSession],
            reflections: [ReflectionEntry]
        ) {
            self.book = book
            self.readingPosition = readingPosition
            self.highlights = highlights
            self.notes = notes
            self.preferences = preferences
            self.sessions = sessions
            self.reflections = reflections
        }
    }

    public struct ReflectionEntry: Codable, Sendable {
        public var reflection: Reflection
        public var messages: [ReflectionMessage]
        public var evidence: [ReflectionEvidence]
        public var connections: [ReflectionConnection]
        public var thoughts: [JournalThought]
        public var questions: [AgentQuestion]
        public var citations: [ReflectionCitation]
        public var memoryChanges: [JournalMemoryChange]

        public init(
            reflection: Reflection,
            messages: [ReflectionMessage],
            evidence: [ReflectionEvidence],
            connections: [ReflectionConnection],
            thoughts: [JournalThought],
            questions: [AgentQuestion],
            citations: [ReflectionCitation],
            memoryChanges: [JournalMemoryChange]
        ) {
            self.reflection = reflection
            self.messages = messages
            self.evidence = evidence
            self.connections = connections
            self.thoughts = thoughts
            self.questions = questions
            self.citations = citations
            self.memoryChanges = memoryChanges
        }
    }

    public init(exportedAt: Date, books: [BookEntry]) {
        self.exportedAt = exportedAt
        self.books = books
    }
}

/// Collects the user's own data through the repository protocols and encodes
/// it as pretty-printed JSON. Purely additive reads; never writes, never
/// touches provider configuration or secrets.
public struct PersonalDataExporter: Sendable {
    private let books: any BookRepository
    private let reading: any ReadingRepository
    private let sessions: any ReadingSessionRepository
    private let reflections: any ReflectionRepository
    private let journal: any JournalRepository

    public init(
        books: any BookRepository,
        reading: any ReadingRepository,
        sessions: any ReadingSessionRepository,
        reflections: any ReflectionRepository,
        journal: any JournalRepository
    ) {
        self.books = books
        self.reading = reading
        self.sessions = sessions
        self.reflections = reflections
        self.journal = journal
    }

    public func export() async throws -> Data {
        let archive = try await makeArchive()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    private func makeArchive() async throws -> PersonalDataArchive {
        var entries: [PersonalDataArchive.BookEntry] = []
        for book in try await books.allBooks() {
            var reflectionEntries: [PersonalDataArchive.ReflectionEntry] = []
            for reflection in try await reflections.reflections(for: book.id) {
                let messages = try await reflections.messages(for: reflection.id)
                let evidence = try await reflections.evidence(for: reflection.id)
                let connections = try await reflections.connections(for: reflection.id)
                let thoughts = try await journal.thoughts(for: reflection.id)
                let questions = try await journal.questions(for: reflection.id)
                let citations = try await journal.citations(for: reflection.id)
                let memoryChanges = try await journal.memoryChanges(for: reflection.id)
                reflectionEntries.append(PersonalDataArchive.ReflectionEntry(
                    reflection: reflection,
                    messages: messages,
                    evidence: evidence,
                    connections: connections,
                    thoughts: thoughts,
                    questions: questions,
                    citations: citations,
                    memoryChanges: memoryChanges
                ))
            }
            entries.append(PersonalDataArchive.BookEntry(
                book: book,
                readingPosition: try await reading.position(for: book.id),
                highlights: try await reading.highlights(for: book.id),
                notes: try await reading.notes(for: book.id),
                preferences: try await reading.preferences(for: book.id),
                sessions: try await sessions.sessions(for: book.id),
                reflections: reflectionEntries
            ))
        }
        return PersonalDataArchive(exportedAt: Date(), books: entries)
    }
}

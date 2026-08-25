import Foundation
import LibraryCore
import ReaderCore
import ReadingSessionCore
import RetrievalCore

/// Assembles the structured Journal for a Reflection: session context, chapters,
/// linked highlights, parsed What-I-Think / Agent Question / Citations / Memory
/// change snapshots. Reads are local and deterministic; the only writes are the
/// idempotent materialization of structured Agent output into Journal tables.
public struct JournalEntryService: Sendable {
    private let books: any BookRepository
    private let reflections: any ReflectionRepository
    private let sessions: any ReadingSessionRepository
    private let index: any BookIndexRepository
    private let reading: any ReadingRepository
    private let journal: any JournalRepository
    private let memoryApplication: MemoryApplicationService?

    public init(
        books: any BookRepository,
        reflections: any ReflectionRepository,
        sessions: any ReadingSessionRepository,
        index: any BookIndexRepository,
        reading: any ReadingRepository,
        journal: any JournalRepository,
        memoryRepository: (any MemoryRepository)? = nil
    ) {
        self.books = books
        self.reflections = reflections
        self.sessions = sessions
        self.index = index
        self.reading = reading
        self.journal = journal
        memoryApplication = memoryRepository.map { MemoryApplicationService(repository: $0) }
    }

    public func recentEntries() async throws -> [JournalEntry] {
        let library = try await books.allBooks()
        let booksByID = Dictionary(uniqueKeysWithValues: library.map { ($0.id, $0) })
        var entries: [JournalEntry] = []
        for book in library {
            let items = try await reflections.reflections(for: book.id)
            for reflection in items {
                entries.append(try await entry(for: reflection, book: book, booksByID: booksByID))
            }
        }
        return entries.sorted { $0.reflection.createdAt > $1.reflection.createdAt }
    }

    // MARK: - Private

    private func entry(
        for reflection: Reflection,
        book: Book,
        booksByID: [BookID: Book]
    ) async throws -> JournalEntry {
        let messages = try await reflections.messages(for: reflection.id)
        try await materializeStructuredOutput(for: reflection, messages: messages)

        let evidence = try await reflections.evidence(for: reflection.id)
        var archiveConnections: [ReflectionArchiveConnection] = []
        for connection in try await reflections.connections(for: reflection.id) {
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

        let session: ReadingSession?
        if let sessionID = reflection.sessionID {
            session = try await sessions.session(id: sessionID)
        } else {
            session = nil
        }

        let linkedHighlights = try await highlights(for: reflection)
        let chapters = try await chapters(for: reflection, session: session, evidence: evidence)

        return JournalEntry(
            reflection: reflection,
            book: book,
            messages: messages,
            evidence: evidence,
            connections: archiveConnections,
            session: session,
            chapters: chapters,
            linkedHighlights: linkedHighlights,
            whatIThink: try await journal.thoughts(for: reflection.id),
            questions: try await journal.questions(for: reflection.id),
            citations: try await journal.citations(for: reflection.id),
            memoryChanges: try await journal.memoryChanges(for: reflection.id)
        )
    }

    private func highlights(for reflection: Reflection) async throws -> [Highlight] {
        let ids = try await reflections.linkedHighlightIDs(for: reflection.id)
        guard !ids.isEmpty else { return [] }
        let allHighlights = try await reading.highlights(for: reflection.bookID)
        let byID = Dictionary(uniqueKeysWithValues: allHighlights.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    private func chapters(
        for reflection: Reflection,
        session: ReadingSession?,
        evidence: [ReflectionEvidence]
    ) async throws -> [BookChapterRef] {
        if let session {
            return try await index.chapters(for: reflection.bookID, from: session.startLocator, to: session.endLocator)
        }
        guard let locator = evidence.first(where: { $0.sourceType == .bookLocator })?.locator else { return [] }
        return try await index.chapters(for: reflection.bookID, from: locator, to: nil)
    }

    /// Parses structured Agent output once per message and persists the derived
    /// rows. `hasStructuredData` keeps this idempotent across reloads.
    private func materializeStructuredOutput(
        for reflection: Reflection,
        messages: [ReflectionMessage]
    ) async throws {
        for message in messages where message.author == .agent {
            guard !(try await journal.hasStructuredData(for: reflection.id, messageID: message.id)) else { continue }
            let parsed = JournalStructuredParser.parse(message.content)
            guard !parsed.thoughts.isEmpty || parsed.question != nil
                || !parsed.memoryProposals.isEmpty || !parsed.citations.isEmpty else { continue }
            for thought in parsed.thoughts {
                try await journal.saveThought(.init(
                    reflectionID: reflection.id, messageID: message.id,
                    thought: thought, createdAt: message.createdAt
                ))
            }
            if let question = parsed.question {
                try await journal.saveQuestion(.init(
                    reflectionID: reflection.id, messageID: message.id,
                    text: question, createdAt: message.createdAt
                ))
            }
            for citation in parsed.citations {
                try await journal.saveCitation(.init(
                    reflectionID: reflection.id, messageID: message.id,
                    sourceType: .bookLocator, bookID: reflection.bookID,
                    locator: citation.locator, title: citation.title,
                    excerpt: citation.excerpt, createdAt: message.createdAt
                ))
            }
            for memory in parsed.memoryProposals {
                let change = JournalMemoryChange(
                    journalID: reflection.id, changeType: memory.changeType,
                    memoryID: memory.memoryID, summary: memory.summary,
                    createdAt: message.createdAt
                )
                try await journal.saveMemoryChange(change)
                if let memoryApplication {
                    try await memoryApplication.apply(
                        change,
                        sourceReflectionID: reflection.id,
                        evidence: ["refl:\(reflection.id)", "msg:\(message.id.uuidString.lowercased())"]
                    )
                }
            }
        }
    }
}

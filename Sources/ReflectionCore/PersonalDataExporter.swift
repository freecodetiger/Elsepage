import BrainCore
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
    /// The user's Personal Brain (Thought / Question / Memory items and the
    /// relations between them) — the same store My Mind ("我的大脑") renders.
    public var brain: BrainExport

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
        /// Base64 keeps the single-file JSON export self-contained. Nil means the
        /// Reflection had no saved audio or the file was unavailable.
        public var audioBase64: String?

        public init(
            reflection: Reflection,
            messages: [ReflectionMessage],
            evidence: [ReflectionEvidence],
            connections: [ReflectionConnection],
            thoughts: [JournalThought],
            questions: [AgentQuestion],
            citations: [ReflectionCitation],
            memoryChanges: [JournalMemoryChange],
            audioBase64: String? = nil
        ) {
            self.reflection = reflection
            self.messages = messages
            self.evidence = evidence
            self.connections = connections
            self.thoughts = thoughts
            self.questions = questions
            self.citations = citations
            self.memoryChanges = memoryChanges
            self.audioBase64 = audioBase64
        }
    }

    public init(exportedAt: Date, books: [BookEntry], brain: BrainExport) {
        self.exportedAt = exportedAt
        self.books = books
        self.brain = brain
    }
}

/// The Personal Brain as export payload. BrainCore domain structs deliberately
/// stay non-Codable; these DTOs carry the fields the UI renders (state, origin,
/// confidence) plus relations, so the JSON reconstructs My Mind's view.
public struct BrainExport: Codable, Sendable {
    public var thoughts: [BrainItemExport]
    public var questions: [BrainItemExport]
    public var memories: [BrainItemExport]
    public var relations: [BrainRelationExport]

    public init(
        thoughts: [BrainItemExport],
        questions: [BrainItemExport],
        memories: [BrainItemExport],
        relations: [BrainRelationExport]
    ) {
        self.thoughts = thoughts
        self.questions = questions
        self.memories = memories
        self.relations = relations
    }
}

public struct BrainItemExport: Codable, Sendable {
    public let id: String
    public let title: String?
    public let content: String
    public let state: String
    public let origin: String?
    public let confidence: String?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String, title: String?, content: String, state: String,
        origin: String?, confidence: String?, createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.state = state
        self.origin = origin
        self.confidence = confidence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct BrainRelationExport: Codable, Sendable {
    public let sourceItemID: String
    public let targetItemID: String
    public let relation: String
    public let weight: Double
    public let createdAt: Date

    public init(sourceItemID: String, targetItemID: String, relation: String, weight: Double, createdAt: Date) {
        self.sourceItemID = sourceItemID
        self.targetItemID = targetItemID
        self.relation = relation
        self.weight = weight
        self.createdAt = createdAt
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
    private let brain: any BrainRepository
    private let audioData: @Sendable (String) -> Data?

    public init(
        books: any BookRepository,
        reading: any ReadingRepository,
        sessions: any ReadingSessionRepository,
        reflections: any ReflectionRepository,
        journal: any JournalRepository,
        brain: any BrainRepository,
        audioData: @escaping @Sendable (String) -> Data? = { _ in nil }
    ) {
        self.books = books
        self.reading = reading
        self.sessions = sessions
        self.reflections = reflections
        self.journal = journal
        self.brain = brain
        self.audioData = audioData
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
                    memoryChanges: memoryChanges,
                    audioBase64: reflection.audioFileName.flatMap(audioData)?.base64EncodedString()
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
        return PersonalDataArchive(
            exportedAt: Date(),
            books: entries,
            brain: try await makeBrainExport()
        )
    }

    private func makeBrainExport() async throws -> BrainExport {
        let items = try await brain.items()
        var thoughts: [BrainItemExport] = []
        var questions: [BrainItemExport] = []
        var memories: [BrainItemExport] = []
        var relationSet: [String: BrainRelationExport] = [:]
        for item in items {
            switch item {
            case .thought(let thought):
                thoughts.append(BrainItemExport(
                    id: thought.id.rawValue, title: thought.title, content: thought.statement,
                    state: thought.stage.rawValue, origin: nil, confidence: nil,
                    createdAt: thought.createdAt, updatedAt: thought.updatedAt
                ))
            case .question(let question):
                questions.append(BrainItemExport(
                    id: question.id.rawValue, title: nil, content: question.question,
                    state: question.state.rawValue, origin: nil, confidence: nil,
                    createdAt: question.createdAt, updatedAt: question.updatedAt
                ))
            case .memory(let memory):
                memories.append(BrainItemExport(
                    id: memory.id.rawValue, title: nil, content: memory.content,
                    state: memory.state.rawValue, origin: memory.origin.rawValue, confidence: memory.confidence.rawValue,
                    createdAt: memory.createdAt, updatedAt: memory.updatedAt
                ))
            }
            for relation in try await brain.relations(of: item.id) {
                let key = "\(relation.sourceItemID.rawValue)|\(relation.targetItemID.rawValue)|\(relation.relation.rawValue)"
                if relationSet[key] == nil {
                    relationSet[key] = BrainRelationExport(
                        sourceItemID: relation.sourceItemID.rawValue,
                        targetItemID: relation.targetItemID.rawValue,
                        relation: relation.relation.rawValue,
                        weight: relation.weight,
                        createdAt: relation.createdAt
                    )
                }
            }
        }
        return BrainExport(
            thoughts: thoughts, questions: questions, memories: memories,
            relations: relationSet.values.sorted { $0.sourceItemID < $1.sourceItemID }
        )
    }
}

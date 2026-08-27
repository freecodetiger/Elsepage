import Foundation
import LibraryCore
import ReaderCore

public struct BookTextBlockID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct BookChunkID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct BookTextBlock: Hashable, Sendable {
    public let id: BookTextBlockID
    public let bookID: BookID
    public let resourceHref: String
    public let chapterID: String?
    public let chapterTitle: String?
    public let sectionID: String?
    public let sectionTitle: String?
    public let resourceOrdinal: Int
    public let ordinal: Int
    public let text: String
    public let startLocator: BookLocator
    public let endLocator: BookLocator

    public init(id: BookTextBlockID, bookID: BookID, resourceHref: String,
                chapterID: String? = nil, chapterTitle: String? = nil,
                sectionID: String? = nil, sectionTitle: String? = nil,
                resourceOrdinal: Int, ordinal: Int, text: String,
                startLocator: BookLocator, endLocator: BookLocator) {
        self.id = id; self.bookID = bookID; self.resourceHref = resourceHref
        self.chapterID = chapterID; self.chapterTitle = chapterTitle
        self.sectionID = sectionID; self.sectionTitle = sectionTitle
        self.resourceOrdinal = resourceOrdinal; self.ordinal = ordinal; self.text = text
        self.startLocator = startLocator; self.endLocator = endLocator
    }
}

/// Retrieval-role of a persisted chunk row. Parents are the larger structural
/// context unit (900–1400 chars, the evidence/expansion unit); children are the
/// smaller retrieval unit (≈350 chars) that owns FTS + embeddings.
public enum BookChunkRole: String, Hashable, Codable, Sendable {
    case parent, child
}

public struct BookChunk: Hashable, Sendable, Identifiable {
    public let id: BookChunkID
    public let bookID: BookID
    public let resourceHref: String
    public let chapterID: String?
    public let chapterTitle: String?
    public let sectionID: String?
    public let sectionTitle: String?
    public let resourceOrdinal: Int
    public let ordinal: Int
    public let text: String
    public let normalizedText: String
    public let startLocator: BookLocator
    public let endLocator: BookLocator
    public let sourceBlockIDs: [BookTextBlockID]
    /// `.parent` for the large structural chunks, `.child` for retrieval children.
    /// Defaults keep pre-evolution construction sites (and test fixtures) producing parents.
    public let role: BookChunkRole
    /// Set on children only: the parent chunk this retrieval child belongs to.
    public let parentID: BookChunkID?

    public init(id: BookChunkID, bookID: BookID, resourceHref: String,
                chapterID: String? = nil, chapterTitle: String? = nil,
                sectionID: String? = nil, sectionTitle: String? = nil,
                resourceOrdinal: Int, ordinal: Int, text: String, normalizedText: String,
                startLocator: BookLocator, endLocator: BookLocator,
                sourceBlockIDs: [BookTextBlockID],
                role: BookChunkRole = .parent, parentID: BookChunkID? = nil) {
        self.id = id; self.bookID = bookID; self.resourceHref = resourceHref
        self.chapterID = chapterID; self.chapterTitle = chapterTitle
        self.sectionID = sectionID; self.sectionTitle = sectionTitle
        self.resourceOrdinal = resourceOrdinal; self.ordinal = ordinal; self.text = text
        self.normalizedText = normalizedText; self.startLocator = startLocator
        self.endLocator = endLocator; self.sourceBlockIDs = sourceBlockIDs
        self.role = role; self.parentID = parentID
    }
}

public enum BookIndexState: String, Codable, Sendable {
    case pending, extracting, lexicalReady, embedding, ready, failed
}

public struct BookIndexJob: Hashable, Sendable {
    public let bookID: BookID
    public let indexVersion: Int
    public var state: BookIndexState
    public var nextResourceOrdinal: Int
    public var lastError: String?
    public var updatedAt: Date
    /// The embedding model this book's vectors were produced with. A job that is
    /// `.ready` but whose `embeddingModel` differs from the currently configured
    /// model needs a re-embed (no full re-chunk).
    public var embeddingModel: String?

    public init(bookID: BookID, indexVersion: Int, state: BookIndexState = .pending,
                nextResourceOrdinal: Int = 0, lastError: String? = nil, updatedAt: Date = .init(),
                embeddingModel: String? = nil) {
        self.bookID = bookID; self.indexVersion = indexVersion; self.state = state
        self.nextResourceOrdinal = nextResourceOrdinal; self.lastError = lastError; self.updatedAt = updatedAt
        self.embeddingModel = embeddingModel
    }
}

public struct ReadingBoundary: Hashable, Sendable {
    public let resourceOrdinal: Int
    public let progression: Double?
    public init(resourceOrdinal: Int, progression: Double? = nil) {
        self.resourceOrdinal = resourceOrdinal; self.progression = progression
    }

    public func contains(_ chunk: BookChunk) -> Bool {
        if chunk.resourceOrdinal != resourceOrdinal { return chunk.resourceOrdinal < resourceOrdinal }
        guard let limit = progression else { return true }
        return (chunk.startLocator.progression ?? 0) <= limit
    }
}

public struct BookEvidence: Hashable, Sendable, Identifiable {
    public let id: BookChunkID
    public let bookID: BookID
    public let chapterTitle: String?
    public let sectionTitle: String?
    public let excerpt: String
    public let locator: BookLocator
    public let score: Double
}

/// A lightweight chapter reference resolved from the persisted book index.
public struct BookChapterRef: Hashable, Sendable {
    public let id: String
    public let title: String?
    public let resourceOrdinal: Int

    public init(id: String, title: String?, resourceOrdinal: Int) {
        self.id = id
        self.title = title
        self.resourceOrdinal = resourceOrdinal
    }
}

public struct RetrievalQuery: Hashable, Sendable {
    public let bookID: BookID
    public let text: String
    public let boundary: ReadingBoundary?
    public let limit: Int
    public let scope: BookRetrievalScope
    public init(bookID: BookID, text: String, boundary: ReadingBoundary?, limit: Int = 4, scope: BookRetrievalScope = .readSoFar) {
        self.bookID = bookID; self.text = text; self.boundary = boundary; self.limit = limit; self.scope = scope
    }
}

public enum BookRetrievalScope: Hashable, Sendable { case currentResource, readSoFar }

public protocol BookRetriever: Sendable {
    func retrieve(_ query: RetrievalQuery) async throws -> [BookEvidence]
}

public protocol BookIndexRepository: Sendable {
    func job(for bookID: BookID, version: Int) async throws -> BookIndexJob?
    func save(job: BookIndexJob) async throws
    func replace(chunks: [BookChunk], for bookID: BookID, version: Int) async throws
    func replace(chunks: [BookChunk], inResource href: String, for bookID: BookID, version: Int) async throws
    func replace(blocks: [BookTextBlock], inResource href: String, for bookID: BookID, version: Int) async throws
    func chunks(for bookID: BookID, version: Int) async throws -> [BookChunk]
    func chunk(id: BookChunkID, bookID: BookID, version: Int) async throws -> BookChunk?
    /// Retrieval children under a parent chunk (for small-to-big expansion).
    func children(of parentID: BookChunkID, bookID: BookID, version: Int) async throws -> [BookChunk]
    func lexicalSearch(bookID: BookID, query: String, boundary: ReadingBoundary?, limit: Int, scope: BookRetrievalScope) async throws -> [(BookChunk, Double)]
    func readingBoundary(bookID: BookID, locator: BookLocator) async throws -> ReadingBoundary?
    /// Resolve the chapters a reading span covers (reusing bookChunks for
    /// locator→resourceOrdinal and bookChapters for ordinal→chapter).
    func chapters(for bookID: BookID, from startLocator: BookLocator, to endLocator: BookLocator?) async throws -> [BookChapterRef]
    func saveEmbeddings(_ embeddings: [BookChunkID: [Float]], model: String, dimensions: Int) async throws
    func embeddings(bookID: BookID, model: String) async throws -> [BookChunkID: [Float]]
    /// Clears a book's persisted index (blocks/chunks/chapters/sections/job) for
    /// one version, so a later `index` run rebuilds from scratch. Embeddings and
    /// FTS rows cascade with their chunks.
    func deleteIndex(for bookID: BookID, version: Int) async throws
}

public protocol BookContentExtractor: Sendable {
    func blocks(for bookID: BookID, startingAtResource ordinal: Int) async throws -> AsyncThrowingStream<BookTextBlock, Error>
}

public struct ReaderAgentBookContext: Hashable, Sendable {
    public let evidence: [BookEvidence]
    public init(evidence: [BookEvidence]) { self.evidence = evidence }
}

public struct ReaderAgentContextBuilder: Sendable {
    private let retriever: any BookRetriever
    public let repository: any BookIndexRepository
    private let characterBudget: Int
    public init(retriever: any BookRetriever, repository: any BookIndexRepository, characterBudget: Int = 4_000) {
        self.retriever = retriever; self.repository = repository; self.characterBudget = max(0, characterBudget)
    }
    public func isAvailable(for bookID: BookID) async -> Bool {
        guard let job = try? await repository.job(for: bookID, version: BookIndexPipeline.currentVersion) else { return false }
        return job.state == .lexicalReady || job.state == .embedding || job.state == .ready
    }

    /// Resolves the read-so-far boundary for a locator, for local citation validation.
    public func readingBoundary(for bookID: BookID, locator: BookLocator) async -> ReadingBoundary? {
        try? await repository.readingBoundary(bookID: bookID, locator: locator)
    }

    public func build(bookID: BookID, reflection: String, currentLocator: BookLocator?,
                      evidenceLimit: Int = 4, characterBudget overrideBudget: Int? = nil,
                      scope: BookRetrievalScope = .readSoFar) async throws -> ReaderAgentBookContext {
        let boundary: ReadingBoundary?
        if let currentLocator {
            boundary = try await repository.readingBoundary(bookID: bookID, locator: currentLocator)
        } else {
            boundary = nil
        }
        // No known reading boundary means no broad book retrieval. This is the
        // conservative anti-spoiler default, not an invitation to search all.
        guard boundary != nil else { return ReaderAgentBookContext(evidence: []) }
        let retrieved = try await retriever.retrieve(.init(bookID: bookID, text: reflection, boundary: boundary, limit: max(1, evidenceLimit), scope: scope))
        var remaining = max(0, overrideBudget ?? characterBudget)
        let evidence = retrieved.compactMap { item -> BookEvidence? in
            guard remaining > 0 else { return nil }
            let excerpt = String(item.excerpt.prefix(remaining)); remaining -= excerpt.count
            return BookEvidence(id: item.id, bookID: item.bookID, chapterTitle: item.chapterTitle,
                sectionTitle: item.sectionTitle, excerpt: excerpt, locator: item.locator, score: item.score)
        }
        return ReaderAgentBookContext(evidence: evidence)
    }
}

public protocol EmbeddingProvider: Sendable {
    var modelIdentifier: String { get }
    var dimensions: Int { get }
    func embed(_ texts: [String]) async throws -> [[Float]]
}

/// A retrieval candidate sent to a cross-encoder reranker for re-scoring.
public struct RerankCandidate: Hashable, Sendable {
    public let id: String
    public let text: String
    public init(id: String, text: String) { self.id = id; self.text = text }
}

/// A passage re-scored by a reranker against the query.
public struct RerankedPassage: Hashable, Sendable {
    public let id: String
    public let score: Double
    public init(id: String, score: Double) { self.id = id; self.score = score }
}

/// Cross-encoder re-ranking: score `candidates` against `query` and return the
/// top `limit` by descending relevance. Used as the RAG precision gate after
/// lexical/semantic candidate fusion.
public protocol Reranker: Sendable {
    var modelIdentifier: String { get }
    func rerank(query: String, candidates: [RerankCandidate], limit: Int?) async throws -> [RerankedPassage]
}


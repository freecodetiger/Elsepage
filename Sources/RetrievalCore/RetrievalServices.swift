import Foundation
import LibraryCore

public actor FlatVectorIndex: VectorIndex {
    private var vectors: [BookChunkID: [Float]] = [:]
    public init() {}
    public func upsert(_ vectors: [BookChunkID: [Float]]) { self.vectors.merge(vectors) { _, new in new } }
    public func search(vector: [Float], candidates: Set<BookChunkID>?, limit: Int) -> [(BookChunkID, Double)] {
        vectors.lazy.filter { candidates?.contains($0.key) ?? true }
            .map { ($0.key, Self.cosine(vector, $0.value)) }
            .sorted { $0.1 > $1.1 }.prefix(max(0, limit)).map { $0 }
    }
    public static func cosine(_ lhs: [Float], _ rhs: [Float]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot: Double = 0, a: Double = 0, b: Double = 0
        for index in lhs.indices { let x = Double(lhs[index]), y = Double(rhs[index]); dot += x*y; a += x*x; b += y*y }
        guard a > 0, b > 0 else { return 0 }
        return dot / (sqrt(a) * sqrt(b))
    }
}

public enum HybridRanker {
    /// Reciprocal-rank fusion avoids comparing provider-specific raw score scales.
    public static func fuse(lexical: [(BookChunkID, Double)], semantic: [(BookChunkID, Double)], limit: Int, k: Double = 60) -> [(BookChunkID, Double)] {
        var scores: [BookChunkID: Double] = [:]
        for (rank, item) in lexical.enumerated() { scores[item.0, default: 0] += 1 / (k + Double(rank + 1)) }
        for (rank, item) in semantic.enumerated() { scores[item.0, default: 0] += 1 / (k + Double(rank + 1)) }
        return scores.sorted { $0.value > $1.value }.prefix(limit).map { ($0.key, $0.value) }
    }
}

public struct LocalBookRetriever: BookRetriever {
    private let repository: any BookIndexRepository
    /// Resolves the embedding provider at query time (a factory, not a resolved
    /// instance) so a Settings enable/disable/model-switch takes effect without
    /// rebuilding the ReaderAgent graph. Nil factory or throw → pure lexical.
    private let embeddingProvider: (@Sendable () async -> (any EmbeddingProvider)?)?
    /// Optional cross-encoder reranker (the RAG precision gate). When available,
    /// fused candidates are re-scored against the query and low-relevance ones
    /// are dropped; nil/failure → fused results as-is.
    private let reranker: (@Sendable () async -> (any Reranker)?)?
    /// How many fused candidates to hand to the reranker (cost control).
    private let rerankCandidateCount: Int
    /// Rerank score floor: passages below it never become evidence.
    private let minimumRelevance: Double

    public init(
        repository: any BookIndexRepository,
        embeddingProvider: (@Sendable () async -> (any EmbeddingProvider)?)? = nil,
        reranker: (@Sendable () async -> (any Reranker)?)? = nil,
        rerankCandidateCount: Int = 10,
        minimumRelevance: Double = 0
    ) {
        self.repository = repository
        self.embeddingProvider = embeddingProvider
        self.reranker = reranker
        self.rerankCandidateCount = max(1, rerankCandidateCount)
        self.minimumRelevance = minimumRelevance
    }

    public func retrieve(_ query: RetrievalQuery) async throws -> [BookEvidence] {
        let lexical = try await repository.lexicalSearch(bookID: query.bookID, query: query.text, boundary: query.boundary, limit: max(12, query.limit * 3), scope: query.scope)
        var ranked = lexical.map { ($0.0.id, $0.1) }
        var chunks = Dictionary(uniqueKeysWithValues: lexical.map { ($0.0.id, $0.0) })
        if let embeddingProvider,
           let provider = await embeddingProvider(),
           let queryVector = try? await provider.embed([query.text]).first {
            let stored = try await repository.embeddings(bookID: query.bookID, model: provider.modelIdentifier)
            let allChunks = try await repository.chunks(for: query.bookID, version: BookIndexPipeline.currentVersion)
                .filter { chunk in
                    guard query.boundary?.contains(chunk) ?? true else { return false }
                    return query.scope == .readSoFar || chunk.resourceOrdinal == query.boundary?.resourceOrdinal
                }
            chunks.merge(Dictionary(uniqueKeysWithValues: allChunks.map { ($0.id, $0) })) { current, _ in current }
            let allowed = Set(allChunks.map(\.id))
            let semantic = stored.filter { allowed.contains($0.key) }
                .map { ($0.key, FlatVectorIndex.cosine(queryVector, $0.value)) }.sorted { $0.1 > $1.1 }
            ranked = HybridRanker.fuse(lexical: ranked, semantic: semantic, limit: max(query.limit, rerankCandidateCount))
        }
        // Reranker gate: re-score the fused top-K against the query and drop
        // passages below the relevance floor. Failure degrades to fused results.
        if let reranker, let provider = await reranker(), !ranked.isEmpty {
            let candidates = ranked.prefix(rerankCandidateCount).compactMap { id, _ -> RerankCandidate? in
                guard let chunk = chunks[id] else { return nil }
                return RerankCandidate(id: id.rawValue, text: chunk.text)
            }
            if !candidates.isEmpty,
               let reranked = try? await provider.rerank(query: query.text, candidates: candidates, limit: query.limit) {
                let scoreByID = Dictionary(uniqueKeysWithValues: reranked.map { ($0.id, $0.score) })
                ranked = candidates
                    .map { (BookChunkID(rawValue: $0.id), scoreByID[$0.id] ?? 0) }
                    .filter { $0.1 > minimumRelevance }
                    .sorted { $0.1 > $1.1 }
            }
        }
        return ranked.prefix(query.limit).compactMap { id, score in
            guard let chunk = chunks[id], query.boundary?.contains(chunk) ?? true else { return nil }
            return BookEvidence(id: id, bookID: chunk.bookID, chapterTitle: chunk.chapterTitle,
                sectionTitle: chunk.sectionTitle, excerpt: chunk.text, locator: chunk.startLocator, score: score)
        }
    }
}

public struct BookIndexPipeline: Sendable {
    public static let currentVersion = 1
    /// Batches per `/embeddings` request. Keeps payloads small and lets the
    /// `bookChunkEmbeddings` table count double as live progress.
    public static let embeddingBatchSize = 100
    private let extractor: (any BookContentExtractor)?
    private let repository: any BookIndexRepository
    private let chunker: StructureAwareChunker
    private let embeddings: (@Sendable () async -> (any EmbeddingProvider)?)?
    public init(extractor: (any BookContentExtractor)? = nil, repository: any BookIndexRepository,
                chunker: StructureAwareChunker = .init(), embeddings: (@Sendable () async -> (any EmbeddingProvider)?)? = nil) {
        self.extractor = extractor; self.repository = repository; self.chunker = chunker; self.embeddings = embeddings
    }

    public func index(bookID: BookID) async throws {
        guard let extractor else { throw RetrievalError.missingExtractor }
        var job = try await repository.job(for: bookID, version: Self.currentVersion)
            ?? BookIndexJob(bookID: bookID, indexVersion: Self.currentVersion)
        job.state = .extracting; job.lastError = nil; job.updatedAt = .init(); try await repository.save(job: job)
        do {
            var resourceBlocks: [BookTextBlock] = []
            var currentResource: String?
            let stream = try await extractor.blocks(for: bookID, startingAtResource: job.nextResourceOrdinal)
            for try await block in stream {
                try Task.checkCancellation()
                if let currentResource, currentResource != block.resourceHref {
                    try await persist(resourceBlocks, href: currentResource, bookID: bookID)
                    job.nextResourceOrdinal = block.resourceOrdinal
                    job.updatedAt = .init(); try await repository.save(job: job)
                    resourceBlocks.removeAll(keepingCapacity: true)
                }
                currentResource = block.resourceHref; resourceBlocks.append(block)
            }
            if let currentResource {
                try await persist(resourceBlocks, href: currentResource, bookID: bookID)
                job.nextResourceOrdinal = (resourceBlocks.last?.resourceOrdinal ?? job.nextResourceOrdinal) + 1
            }
            let chunks = try await repository.chunks(for: bookID, version: Self.currentVersion)
            job.state = .lexicalReady; job.updatedAt = .init(); try await repository.save(job: job)
            if let embeddings, !chunks.isEmpty, let provider = await embeddings() {
                try await embed(chunks: chunks, provider: provider, job: &job)
            }
        } catch is CancellationError { throw CancellationError() }
        catch {
            job.state = .failed; job.lastError = String(describing: error); job.updatedAt = .init()
            try? await repository.save(job: job); throw error
        }
    }

    /// Runs just the embedding phase over an already-indexed book. Used when
    /// semantic indexing is enabled after the book is `.lexicalReady`, or when
    /// the configured embedding model changes (no full re-chunk needed).
    public func embed(bookID: BookID, force: Bool = false) async throws {
        var job = try await repository.job(for: bookID, version: Self.currentVersion)
            ?? BookIndexJob(bookID: bookID, indexVersion: Self.currentVersion)
        guard job.state == .lexicalReady || job.state == .ready else { return }
        let chunks = try await repository.chunks(for: bookID, version: Self.currentVersion)
        guard !chunks.isEmpty, let embeddings, let provider = await embeddings() else { return }
        if !force, job.state == .ready, job.embeddingModel == provider.modelIdentifier {
            let existing = try await repository.embeddings(bookID: bookID, model: provider.modelIdentifier)
            guard existing.count < chunks.count else { return } // already fully embedded with this model
        }
        do {
            try await embed(chunks: chunks, provider: provider, job: &job)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            job.state = .failed; job.lastError = String(describing: error); job.updatedAt = .init()
            try? await repository.save(job: job); throw error
        }
    }

    private func embed(chunks: [BookChunk], provider: any EmbeddingProvider, job: inout BookIndexJob) async throws {
        job.state = .embedding
        job.embeddingModel = provider.modelIdentifier
        job.lastError = nil
        job.updatedAt = .init()
        try await repository.save(job: job)
        for batch in chunks.batched(by: Self.embeddingBatchSize) {
            try Task.checkCancellation()
            let vectors = try await provider.embed(batch.map(\.text))
            guard vectors.count == batch.count, vectors.allSatisfy({ $0.count == provider.dimensions }) else { throw RetrievalError.invalidEmbeddings }
            try await repository.saveEmbeddings(
                Dictionary(uniqueKeysWithValues: zip(batch.map(\.id), vectors)),
                model: provider.modelIdentifier, dimensions: provider.dimensions
            )
            job.updatedAt = .init(); try await repository.save(job: job)
        }
        job.state = .ready
        job.updatedAt = .init()
        try await repository.save(job: job)
    }

    private func persist(_ blocks: [BookTextBlock], href: String, bookID: BookID) async throws {
        try await repository.replace(blocks: blocks, inResource: href, for: bookID, version: Self.currentVersion)
        let chunks = chunker.chunks(from: blocks, indexVersion: Self.currentVersion)
        try await repository.replace(chunks: chunks, inResource: href, for: bookID, version: Self.currentVersion)
    }
}

private extension Array {
    func batched(by size: Int) -> [[Element]] {
        let strideSize = Swift.max(1, size)
        return Swift.stride(from: 0, to: count, by: strideSize).map { start in
            Array(self[start..<Swift.min(start + strideSize, count)])
        }
    }
}

public enum RetrievalError: Error { case invalidEmbeddings, missingExtractor }

public struct AnnotationContext: Hashable, Sendable {
    public let nearby: [BookEvidence]
    public init(nearby: [BookEvidence]) { self.nearby = nearby }
}

public struct AnnotationContextBuilder: Sendable {
    private let retriever: any BookRetriever
    public init(retriever: any BookRetriever) { self.retriever = retriever }
    public func build(bookID: BookID, selectedText: String, boundary: ReadingBoundary?) async throws -> AnnotationContext {
        AnnotationContext(nearby: try await retriever.retrieve(.init(bookID: bookID, text: selectedText, boundary: boundary)))
    }
}

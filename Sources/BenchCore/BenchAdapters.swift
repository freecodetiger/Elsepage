import CryptoKit
import Foundation
import LibraryCore
import ReaderCore
import ReflectionCore
import RetrievalCore

// MARK: - Deterministic identity

/// Derives a stable UUID (RFC 4122 v4-shaped) from a string, so the same sample
/// maps to the same reflection/past-thought/book IDs across runs and reports.
func stableUUID(_ seed: String) -> UUID {
    let digest = SHA256.hash(data: Data(seed.utf8))
    var bytes = Array(digest.prefix(16))
    // Set version 4 and variant bits so the value looks like a normal UUID.
    bytes[6] = (bytes[6] & 0x0F) | 0x40
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
}

/// Builds a lossless Readium-style locator from a sample's locator fields.
func makeBookLocator(_ locator: BenchLocator) throws -> BookLocator {
    var object: [String: Any] = ["href": locator.href]
    if let progression = locator.progression { object["progression"] = progression }
    let json = try JSONSerialization.data(withJSONObject: object, options: [])
    return try BookLocator(
        json: json, href: locator.href, progression: locator.progression,
        textBefore: locator.textBefore, textHighlight: locator.textHighlight, textAfter: locator.textAfter
    )
}

// MARK: - Memory repository (boundary adapter)

/// In-memory `MemoryRepository` fed from a sample's memory claims. The bench
/// never writes memories; `save`/`delete` are no-ops kept for protocol conformance.
final class BenchMemoryRepository: MemoryRepository, @unchecked Sendable {
    private let stored: [ReaderMemory]

    init(_ claims: [BenchMemoryClaim], sampleID: String) {
        stored = claims.enumerated().map { index, claim in
            ReaderMemory(
                id: stableUUID("memory:\(sampleID):\(index)"),
                kind: MemoryKind(rawValue: claim.kind ?? "") ?? .semantic,
                claim: claim.claim,
                confidence: 0.8,
                status: .active,
                createdAt: Date(timeIntervalSinceNow: -Double(index + 1) * 86_400)
            )
        }
    }

    func memories() async throws -> [ReaderMemory] { stored }
    func memories(kind: MemoryKind) async throws -> [ReaderMemory] { stored.filter { $0.kind == kind } }
    func save(_ memory: ReaderMemory) async throws {}
    func delete(id: UUID) async throws {}
    func deleteAll() async throws {}
    func markInaccurate(id: UUID) async throws {}
}

// MARK: - Book index boundary adapters

/// The fixed retrieval lane: a sample's `retrievalEvidence` IS the retrieval
/// result. Retrieval quality is not under test (PRD §16 evaluates the reply);
/// passage selection is fixed so runs stay comparable.
struct BenchBookRetriever: BookRetriever {
    let evidence: [BookEvidence]

    init(sample: BenchSample, bookID: BookID) {
        evidence = sample.retrievalEvidence.enumerated().map { index, passage in
            BookEvidence(
                id: BookChunkID(rawValue: "benchchunk-\(sample.id)-\(index + 1)"),
                bookID: bookID,
                chapterTitle: passage.chapterTitle,
                sectionTitle: passage.sectionTitle,
                excerpt: passage.text,
                locator: Self.passageLocator(passage: passage, sample: sample),
                score: 1.0 - Double(index) * 0.1
            )
        }
    }

    func retrieve(_ query: RetrievalQuery) async throws -> [BookEvidence] { evidence }

    /// Evidence locators sit at the reading position so the read-so-far boundary
    /// always contains them (samples may only cite what was read).
    private static func passageLocator(passage: BenchEvidencePassage, sample: BenchSample) -> BookLocator {
        let href = passage.href ?? sample.currentLocator?.href ?? "bench.xhtml"
        let progression = sample.currentLocator?.progression ?? 0.5
        let object: [String: Any] = ["href": href, "progression": progression]
        let json = (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data("{}".utf8)
        return (try? BookLocator(json: json, href: href, progression: progression)) ??
            (try! BookLocator(json: Data("{}".utf8), href: href))
    }
}

/// Minimal `BookIndexRepository` backing the real `ReaderAgentContextBuilder`
/// with sample data: availability (job), read-so-far boundary resolution, and
/// chunk lookup for citation validation. Mutating/indexing methods are no-ops —
/// the bench never builds an index. All state is immutable after init.
final class BenchBookIndexRepository: BookIndexRepository, @unchecked Sendable {
    private let bookID: BookID
    private let hasIndex: Bool
    private let chunks: [BookChunk]
    private let chunkByID: [BookChunkID: BookChunk]

    init(sample: BenchSample, bookID: BookID) {
        self.bookID = bookID
        hasIndex = !sample.retrievalEvidence.isEmpty
        let retriever = BenchBookRetriever(sample: sample, bookID: bookID)
        chunks = retriever.evidence.map { evidence in
            BookChunk(
                id: evidence.id, bookID: evidence.bookID,
                resourceHref: evidence.locator.href,
                chapterID: nil, chapterTitle: evidence.chapterTitle,
                sectionID: nil, sectionTitle: evidence.sectionTitle,
                resourceOrdinal: 0, ordinal: 0,
                text: evidence.excerpt, normalizedText: evidence.excerpt,
                startLocator: evidence.locator, endLocator: evidence.locator,
                sourceBlockIDs: []
            )
        }
        chunkByID = Dictionary(uniqueKeysWithValues: chunks.map { ($0.id, $0) })
    }

    func job(for bookID: BookID, version: Int) async throws -> BookIndexJob? {
        guard bookID == self.bookID, hasIndex else { return nil }
        return BookIndexJob(bookID: bookID, indexVersion: version, state: .ready)
    }
    func save(job: BookIndexJob) async throws {}
    func replace(chunks: [BookChunk], for bookID: BookID, version: Int) async throws {}
    func replace(chunks: [BookChunk], inResource href: String, for bookID: BookID, version: Int) async throws {}
    func replace(blocks: [BookTextBlock], inResource href: String, for bookID: BookID, version: Int) async throws {}
    func chunks(for bookID: BookID, version: Int) async throws -> [BookChunk] {
        bookID == self.bookID ? chunks : []
    }
    func chunk(id: BookChunkID, bookID: BookID, version: Int) async throws -> BookChunk? {
        guard bookID == self.bookID else { return nil }
        return chunkByID[id]
    }
    func children(of parentID: BookChunkID, bookID: BookID, version: Int) async throws -> [BookChunk] { [] }
    func lexicalSearch(bookID: BookID, query: String, boundary: ReadingBoundary?, limit: Int, scope: BookRetrievalScope) async throws -> [(BookChunk, Double)] { [] }
    func readingBoundary(bookID: BookID, locator: BookLocator) async throws -> ReadingBoundary? {
        guard bookID == self.bookID else { return nil }
        // All bench chunks live in resource ordinal 0; the boundary progression
        // comes from the reading position so chunk containment behaves like the app.
        return ReadingBoundary(resourceOrdinal: 0, progression: locator.progression)
    }
    func chapters(for bookID: BookID, from startLocator: BookLocator, to endLocator: BookLocator?) async throws -> [BookChapterRef] { [] }
    func saveEmbeddings(_ embeddings: [BookChunkID: [Float]], model: String, dimensions: Int) async throws {}
    func embeddings(bookID: BookID, model: String) async throws -> [BookChunkID: [Float]] { [:] }
    func deleteIndex(for bookID: BookID, version: Int) async throws {}
    func deleteIndex(below version: Int, for bookID: BookID) async throws {}
}

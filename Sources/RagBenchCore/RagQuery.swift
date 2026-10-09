import Foundation
import LibraryCore
import Persistence
import ReaderCore
import RetrievalCore

// MARK: - Authored spec

/// What a human authors: the intent, the wording, and *where the cursor is*
/// expressed relative to a chunk rather than as a raw number. Resolving the
/// wording to a chunk and the cursor to a reachable set is the builder's job,
/// and it does both through production code.
public struct RagQuerySpec: Codable, Sendable {
    public var queries: [RagQuerySpecEntry]
    public init(queries: [RagQuerySpecEntry]) { self.queries = queries }
}

public struct RagQuerySpecEntry: Codable, Sendable {
    public var id: String
    public var book: String
    /// `legit` | `paraphrase` | `adversarial` | `edge`
    public var intent: String
    /// `dev` | `holdout`
    public var split: String
    public var text: String
    /// The query's primary target: the chunk whose text contains this string
    /// gets relevance grade 2. Absent on adversarial queries, whose correct
    /// answer is nothing.
    public var gold: String?
    /// Optional second target (the paraphrase twin), grade 1.
    public var paraphrase: String?
    public var cursor: RagCursorSpec
    /// Adversarial queries name the chunks the boundary must exclude. A late
    /// term can land in more than one retrieval child, and every one of them
    /// has to be hidden.
    public var mustStayUnreachable: [String]?
    public var note: String?
}

/// Cursor placement. Every case is anchored to a chunk, so placement and
/// verification both go through the same production predicate instead of a
/// second, hand-rolled notion of "the reader is here".
public struct RagCursorSpec: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Strictly inside a multi-block chunk's span — the ordinary case.
        case insideChunk
        /// Exactly at a chunk's end: the cursor sits between two spans.
        case atChunkEnd
        /// Strictly between one chunk's end and the next chunk's start.
        case gapAfterChunk
        /// At a zero-width chunk's single point.
        case atZeroWidthChunk
    }

    public var kind: Kind
    public var marker: String
    /// Where in the span, for `insideChunk`. Defaults to the midpoint.
    public var fraction: Double?

    public init(kind: Kind, marker: String, fraction: Double? = nil) {
        self.kind = kind; self.marker = marker; self.fraction = fraction
    }
}

// MARK: - Resolved record

public struct RagGoldRecord: Codable, Hashable, Sendable {
    public var chunkID: String
    /// 2 = the query's own wording points here; 1 = an equally valid but
    /// differently-worded passage on the same idea.
    public var grade: Int
    public init(chunkID: String, grade: Int) { self.chunkID = chunkID; self.grade = grade }
}

public struct RagQueryRecord: Codable, Hashable, Sendable {
    public var id: String
    public var bookKey: String
    public var split: String
    public var intent: String
    public var text: String
    /// The cursor, as a locator. The boundary itself is *not* stored: the
    /// ablation re-resolves it with `readingBoundary` at run time, so a stored
    /// boundary can never go stale against the production policy.
    public var cursorHref: String
    public var cursorProgression: Double
    public var gold: [RagGoldRecord]
    public var mustStayUnreachable: [String]
    public var note: String?
}

// MARK: - Builder

public enum RagQueryBuildError: Error, CustomStringConvertible {
    case markerNotFound(String, book: String, kind: String)
    case markerAmbiguous(String, book: String, matches: Int)
    case noGap(String, book: String)
    case layoutEmpty(String)
    case goldUnreachable(String, chunkID: String)
    case adversarialTargetReachable(String, chunkID: String)

    public var description: String {
        switch self {
        case let .markerNotFound(marker, book, kind):
            return "\(book): no child chunk matches \(kind) marker 「\(marker)」"
        case let .markerAmbiguous(marker, book, matches):
            return "\(book): marker 「\(marker)」 matches \(matches) child chunks, expected exactly 1"
        case let .noGap(marker, book):
            return "\(book): no gap after the chunk containing 「\(marker)」"
        case let .layoutEmpty(book):
            return "\(book): no chunks seeded"
        case let .goldUnreachable(id, chunkID):
            return "\(id): gold chunk \(chunkID) is denied by the production boundary"
        case let .adversarialTargetReachable(id, chunkID):
            return "\(id): adversarial target \(chunkID) is reachable — the corpus does not hide it"
        }
    }
}

/// Turns the authored spec into a query set whose gold labels are *judged* by
/// production code:
///
/// 1. a marker resolves to a chunk by literal text search, never by re-deriving
///    the chunker's geometry;
/// 2. the cursor resolves to a `ResolvedReadingBoundary` through the production
///    `readingBoundary(bookID:locator:)`;
/// 3. reachability is `ResolvedReadingBoundary.contains`, the same predicate the
///    retriever applies at run time.
///
/// A query whose gold the boundary denies is a corpus bug, and it throws here
/// rather than being silently counted as a retrieval miss.
public struct RagQueryBuilder {
    public let corpus: RagCorpus

    public init(corpus: RagCorpus) { self.corpus = corpus }

    public static func load(corpusURL: URL, specURL: URL) throws -> (RagCorpus, RagQuerySpec) {
        let corpus = try RagCorpus.load(from: corpusURL)
        let spec = try JSONDecoder().decode(RagQuerySpec.self, from: Data(contentsOf: specURL))
        return (corpus, spec)
    }

    public func build(
        spec: RagQuerySpec,
        database: AppDatabase
    ) async throws -> [RagQueryRecord] {
        // Seed every book once; the spec may reference them in any order.
        var repositoryFor: [String: GRDBBookIndexRepository] = [:]
        for bookKey in corpus.bookKeys {
            repositoryFor[bookKey] = try await corpus.seed(bookKey: bookKey, database: database)
        }

        var records: [RagQueryRecord] = []
        for entry in spec.queries {
            guard let repository = repositoryFor[entry.book],
                  let bookID = corpus.bookID(forBook: entry.book) else {
                throw RagQueryBuildError.layoutEmpty(entry.book)
            }
            let children = corpus.chunks(forBook: entry.book)
                .filter { $0.role == .child }
                .sorted { ($0.resourceOrdinal, $0.ordinal) < ($1.resourceOrdinal, $1.ordinal) }
            guard !children.isEmpty else { throw RagQueryBuildError.layoutEmpty(entry.book) }

            // The cursor is anchored to its own chunk, which need not be the
            // gold's chunk — a legit query reads chapter 4 and asks about a
            // passage from chapter 2.
            let anchor = try Self.resolve(marker: entry.cursor.marker, in: children, book: entry.book, kind: "cursor")
            let progression = try Self.cursorProgression(entry.cursor, anchor: anchor, in: children, book: entry.book)

            // The locator is only a cursor: the boundary policy is production's.
            let locator = try BookLocator(
                json: try JSONSerialization.data(withJSONObject: ["href": anchor.resourceHref]),
                href: anchor.resourceHref,
                progression: progression
            )
            guard let boundary = try await repository.readingBoundary(bookID: bookID, locator: locator) else {
                throw RagQueryBuildError.layoutEmpty(entry.book)
            }

            var gold: [RagGoldRecord] = []
            if let goldMarker = entry.gold {
                let goldChunk = try Self.resolve(marker: goldMarker, in: children, book: entry.book, kind: "gold")
                gold.append(RagGoldRecord(chunkID: goldChunk.id.rawValue, grade: 2))
            }
            if let paraphraseMarker = entry.paraphrase {
                let twin = try Self.resolve(marker: paraphraseMarker, in: children, book: entry.book, kind: "paraphrase")
                gold.append(RagGoldRecord(chunkID: twin.id.rawValue, grade: 1))
            }
            for item in gold where !boundary.contains(chunk(for: item.chunkID, in: children)) {
                throw RagQueryBuildError.goldUnreachable(entry.id, chunkID: item.chunkID)
            }

            let unreachable = try (entry.mustStayUnreachable ?? []).map { marker -> String in
                let target = try Self.resolve(marker: marker, in: children, book: entry.book, kind: "unreachable")
                guard !boundary.contains(target) else {
                    throw RagQueryBuildError.adversarialTargetReachable(entry.id, chunkID: target.id.rawValue)
                }
                return target.id.rawValue
            }

            records.append(RagQueryRecord(
                id: entry.id, bookKey: entry.book, split: entry.split, intent: entry.intent,
                text: entry.text,
                cursorHref: locator.href, cursorProgression: progression,
                gold: gold, mustStayUnreachable: unreachable, note: entry.note
            ))
        }
        return records
    }

    // MARK: placement

    private func chunk(for id: String, in children: [BookChunk]) -> BookChunk {
        children.first { $0.id.rawValue == id }!
    }

    static func resolve(
        marker: String, in children: [BookChunk], book: String, kind: String
    ) throws -> BookChunk {
        let matches = children.filter { $0.text.contains(marker) }
        guard let first = matches.first else {
            throw RagQueryBuildError.markerNotFound(marker, book: book, kind: kind)
        }
        guard matches.count == 1 else {
            throw RagQueryBuildError.markerAmbiguous(marker, book: book, matches: matches.count)
        }
        return first
    }

    /// Placement only — what the cursor *means* is decided by the boundary.
    static func cursorProgression(
        _ cursor: RagCursorSpec, anchor: BookChunk, in children: [BookChunk], book: String
    ) throws -> Double {
        let start = anchor.startLocator.progression ?? 0
        let end = anchor.endLocator.progression ?? start
        // Children of one resource, in ordinal order — the chunker never spans
        // resources, so this is the cursor's neighbourhood.
        let siblings = children.filter { $0.resourceHref == anchor.resourceHref }
        let index = siblings.firstIndex { $0.id == anchor.id }!

        switch cursor.kind {
        case .insideChunk:
            guard end > start else { throw RagQueryBuildError.noGap(cursor.marker, book: book) }
            return start + (end - start) * (cursor.fraction ?? 0.5)
        case .atChunkEnd:
            return end
        case .gapAfterChunk:
            guard index + 1 < siblings.count,
                  let nextStart = siblings[index + 1].startLocator.progression,
                  nextStart > end else {
                throw RagQueryBuildError.noGap(cursor.marker, book: book)
            }
            return (end + nextStart) / 2
        case .atZeroWidthChunk:
            guard start == end else { throw RagQueryBuildError.noGap(cursor.marker, book: book) }
            return start
        }
    }
}

private extension RagCursorSpec {
    /// The cursor lives in the anchor chunk's resource.
    func hrefForCursor(chunk: BookChunk) -> String { chunk.resourceHref }
}

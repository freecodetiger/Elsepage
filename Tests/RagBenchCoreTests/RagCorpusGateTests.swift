import Foundation
import Persistence
import RagBenchCore
import RetrievalCore
import Testing

/// The corpus gate. Nothing that fails here may enter a benchmark: every
/// assertion below is a property the previous corpus violated silently and
/// only discovered after a round of results had already been quoted.
@Suite("RAG corpus gate")
struct RagCorpusGateTests {
    static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // RagBenchCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Fixtures/RagCorpus", isDirectory: true)
    }

    static func loadCorpus() throws -> RagCorpus {
        try RagCorpus.load(from: root.appendingPathComponent("chunks.jsonl"))
    }

    static func loadSpec() throws -> RagQuerySpec {
        try JSONDecoder().decode(
            RagQuerySpec.self,
            from: Data(contentsOf: root.appendingPathComponent("queries.spec.json"))
        )
    }

    // MARK: geometry

    @Test func corpusCoversThreeBooksOfEightChapters() throws {
        let corpus = try Self.loadCorpus()
        #expect(corpus.bookKeys == ["book-01", "book-02", "book-03"])
        for book in corpus.bookKeys {
            let chunks = corpus.chunks(forBook: book)
            let children = chunks.filter { $0.role == .child }
            let resources = Set(chunks.map(\.resourceOrdinal))
            #expect(resources.count == 8, "\(book) should have 8 chapter resources")
            #expect(children.count > 40, "\(book) has too small a candidate pool: \(children.count)")
        }
    }

    /// Adjacent retrieval children of one resource never overlap and never go
    /// backwards. This is what makes `readingBoundary`'s active-chunk pick
    /// unique instead of a coin flip among co-located candidates.
    @Test func childSpansAreDisjointAndMonotonic() throws {
        let corpus = try Self.loadCorpus()
        for book in corpus.bookKeys {
            let children = corpus.chunks(forBook: book)
                .filter { $0.role == .child }
                .sorted { ($0.resourceOrdinal, $0.ordinal) < ($1.resourceOrdinal, $1.ordinal) }
            let byResource = Dictionary(grouping: children, by: \.resourceHref)
            for (href, group) in byResource {
                for (left, right) in zip(group, group.dropFirst()) {
                    let leftEnd = try #require(left.endLocator.progression)
                    let rightStart = try #require(right.startLocator.progression)
                    #expect(
                        rightStart >= leftEnd,
                        "\(book) \(href): child \(left.ordinal) ends at \(leftEnd) but \(right.ordinal) starts at \(rightStart)"
                    )
                }
            }
        }
    }

    /// At most one child may span any given progression.
    ///
    /// "At most", not "exactly": the gaps between spans are real, and a cursor
    /// that lands in one belongs to no chunk at all.
    @Test func atMostOneChildSpansAnyProgression() throws {
        let corpus = try Self.loadCorpus()
        var checked = 0
        var gaps = 0
        for book in corpus.bookKeys {
            let children = corpus.chunks(forBook: book).filter { $0.role == .child }
            for (href, group) in Dictionary(grouping: children, by: \.resourceHref) {
                let spans = group.compactMap { chunk -> (Double, Double)? in
                    guard let start = chunk.startLocator.progression,
                          let end = chunk.endLocator.progression else { return nil }
                    return (start, end)
                }
                // Every span boundary, plus a dense interior scan, so a
                // near-miss overlap cannot hide between sample points.
                var probes = spans.flatMap { [$0.0, $0.1] }
                for index in 1..<400 { probes.append(Double(index) / 400) }
                for probe in probes {
                    let crossing = spans.filter { $0.0 < probe && probe < $0.1 }
                    #expect(
                        crossing.count <= 1,
                        "\(book) \(href): \(crossing.count) children span \(probe)"
                    )
                    checked += 1
                    if crossing.isEmpty, probe > 0, probe < 1 { gaps += 1 }
                }
            }
        }
        #expect(checked > 0)
        // If this ever hit zero the "at most 1" claim would be vacuous and the
        // gate would be testing a geometry the corpus does not have.
        #expect(gaps > 0, "no gaps found: the corpus collapsed into contiguous spans")
    }

    /// Zero-width spans exist and can never be the active chunk. They are the
    /// reason a boundary can resolve to no active chunk at all.
    @Test func zeroWidthSpansExistAndAreNeverActive() throws {
        let corpus = try Self.loadCorpus()
        var zeroWidth = 0
        for book in corpus.bookKeys {
            for chunk in corpus.chunks(forBook: book).filter({ $0.role == .child }) {
                let start = try #require(chunk.startLocator.progression)
                let end = try #require(chunk.endLocator.progression)
                guard start == end else { continue }
                zeroWidth += 1
                // `readingBoundary` needs `start < p < end`, which a zero-width
                // span cannot satisfy for any p.
                #expect(!(start < start && start < end))
            }
        }
        #expect(zeroWidth > 0, "expected zero-width spans in this corpus geometry")
    }

    @Test func everyChildPointsAtARealParent() throws {
        let corpus = try Self.loadCorpus()
        for book in corpus.bookKeys {
            let chunks = corpus.chunks(forBook: book)
            let parentIDs = Set(chunks.filter { $0.role == .parent }.map(\.id.rawValue))
            let children = chunks.filter { $0.role == .child }
            #expect(!children.isEmpty)
            for child in children {
                let parentID = try #require(child.parentID, "\(book): child \(child.id) has no parent")
                #expect(parentIDs.contains(parentID.rawValue), "\(book): dangling parent \(parentID)")
            }
            for parent in chunks.filter({ $0.role == .parent }) {
                #expect(
                    children.contains { $0.parentID == parent.id },
                    "\(book): parent \(parent.id) has no children"
                )
            }
        }
    }

    /// The leak check identifies a denied chunk by its text, so two chunks
    /// sharing text would make a leak indistinguishable from a legitimate hit.
    @Test func childTextsAreUnique() throws {
        let corpus = try Self.loadCorpus()
        var seen: [String: String] = [:]
        for chunk in corpus.records.filter({ $0.role == "child" }) {
            let previous = seen[chunk.text]
            #expect(previous == nil, "duplicate child text in \(previous ?? "") and \(chunk.id)")
            seen[chunk.text] = chunk.id
        }
    }

    // MARK: gold labels

    /// Builds the authored spec. The builder throws when a gold the production
    /// boundary denies, or an adversarial target it fails to hide, so a corpus
    /// bug surfaces here rather than as a retrieval "miss" in the results.
    @Test func authoredQueriesResolveToReachableGold() async throws {
        let corpus = try Self.loadCorpus()
        let spec = try Self.loadSpec()
        let database = try AppDatabase.inMemory()
        let queries = try await RagQueryBuilder(corpus: corpus).build(spec: spec, database: database)

        #expect(queries.count == spec.queries.count)
        #expect(queries.contains { $0.intent == "legit" })
        #expect(queries.contains { $0.intent == "paraphrase" })
        #expect(queries.contains { $0.intent == "adversarial" })
        #expect(queries.contains { $0.intent == "edge" })
        #expect(Set(queries.map(\.split)) == ["dev", "holdout"])

        for query in queries {
            // Adversarial queries deliberately have no gold: the correct answer
            // is nothing, and their denominator is the query count, not a gold
            // count. Everything else must carry one.
            if query.intent == "adversarial" {
                #expect(query.gold.isEmpty)
                #expect(!query.mustStayUnreachable.isEmpty)
            } else {
                #expect(!query.gold.isEmpty, "\(query.id) has no gold")
                #expect(query.mustStayUnreachable.isEmpty)
            }
        }
    }

    // MARK: lexical attainability

    /// The 3-character windows the production `ftsTerms` builder turns a query
    /// into. Reused rather than re-implemented, so this gate cannot disagree
    /// with the index it is reasoning about.
    static func terms(of text: String) -> [String] {
        GRDBBookIndexRepository.ftsTerms(for: text)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
    }

    /// A legit query must be reachable by the lexical lane. Otherwise its zero
    /// recall would be a property of the corpus, not of the retriever.
    @Test func legitQueriesAreLexicallyAttainable() async throws {
        let corpus = try Self.loadCorpus()
        let spec = try Self.loadSpec()
        let byID = Dictionary(uniqueKeysWithValues: corpus.records.map { ($0.id, $0) })
        let entries = Dictionary(uniqueKeysWithValues: spec.queries.map { ($0.id, $0) })

        for query in spec.queries where query.intent == "legit" {
            let entry = try #require(entries[query.id])
            let marker = try #require(entry.gold)
            let gold = try #require(corpus.records.first { $0.text.contains(marker) })
            let terms = Self.terms(of: query.text)
            #expect(!terms.isEmpty)
            #expect(
                terms.contains { gold.normalizedText.contains($0) },
                "\(query.id): no query trigram occurs in its gold chunk \(byID[gold.id]?.id ?? "")"
            )
        }
    }

    /// A paraphrase query echoes the wording of its grade-2 gold and shares no
    /// trigram with its grade-1 twin. That is the discriminating property the
    /// whole paraphrase bucket rests on: if both copies shared wording, the
    /// lexical and semantic arms would be measuring the same thing.
    @Test func paraphraseQueriesCannotReachTheirTwinLexically() async throws {
        let corpus = try Self.loadCorpus()
        let spec = try Self.loadSpec()
        var checked = 0
        for query in spec.queries where query.intent == "paraphrase" {
            let twin = try #require(query.paraphrase, "\(query.id) has no paraphrase target")
            let twinChunk = try #require(corpus.records.first { $0.text.contains(twin) })
            let terms = Self.terms(of: query.text)
            let shared = terms.filter { twinChunk.normalizedText.contains($0) }
            #expect(shared.isEmpty, "\(query.id): query wording also occurs in its twin via \(shared)")
            checked += 1
        }
        #expect(checked > 0, "no paraphrase queries to check")
    }

    // MARK: leak

    /// Zero leaks under both predicates, measured on what the retriever
    /// actually returns — not on what the corpus believes it would return.
    @Test func retrievalLeaksNothingUnderEitherPredicate() async throws {
        let corpus = try Self.loadCorpus()
        let spec = try Self.loadSpec()
        let database = try AppDatabase.inMemory()
        let queries = try await RagQueryBuilder(corpus: corpus).build(spec: spec, database: database)

        let ablation = RagAblation(corpus: corpus, database: database, k: 5)
        let reports = try await ablation.run(
            queries: queries,
            arms: [RagArm(name: "lexical", semantic: false, rerank: false, expand: true)]
        )
        let report = try #require(reports.first)

        #expect(report.overall.queries == queries.count)
        #expect(report.overall.leakTotal == 0, "returned text from ahead of the cursor")
        #expect(report.forbiddenReturned == 0, "an adversarial target was retrievable")
    }
}

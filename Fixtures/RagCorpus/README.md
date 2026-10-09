# RAG corpus

A controlled Chinese corpus for measuring the retrieval half of RAG: which
passages a reader's reflection should surface from the part of the book they
have already read.

It replaces a corpus that was withdrawn. That one hand-built chunk geometry and
boundary predicates in Python, silently drifted from the Swift implementation,
and left 61 of 241 gold passages unreachable by the production code. The
headline "ceiling of 74.7%" quoted from it was one arbitrary draw from
`[0.656, 1.000]`: the active chunk was picked among three or four co-located
candidates, hitting gold 22 times in 83, which is not distinguishable from a
coin flip.

Nothing here is allowed to repeat that mistake. **Every semantic property of
this corpus is produced or judged by production code.** No script re-derives
chunk geometry, tests reachability, or retokenises a query.

## Layout

```
source/<book>/         hand-written XHTML, committed, diffable
epub/<book>.epub       built by Scripts/build-corpus-epub.sh, committed
chunks.jsonl           dumped from the production pipeline (see below)
queries.spec.json      authored: intent, wording, cursor placement
queries.jsonl          resolved by RagQueryBuilder, committed
ablation.json          the run of record, with provenance
DESIGN.md              the controlled properties and where they land
WRITING.md             the spec each chapter was written against
```

## Regenerating

Three steps, in order. The middle one needs Xcode.

```sh
# 1. pack the EPUBs (deterministic; builds twice and byte-compares)
for b in book-01 book-02 book-03; do
  sh Scripts/build-corpus-epub.sh Fixtures/RagCorpus/source/$b Fixtures/RagCorpus/epub/$b.epub
done

# 2. index them with the production pipeline and dump the geometry.
#    Readium only builds for iOS, so this runs in the simulator:
xcodebuild test -project ReadLoop.xcodeproj -scheme ReadLoop \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ReadiumIntegrationTests/RagCorpusSnapshotTests

# 3. build the query set and run the ablation
SILICONFLOW_API_KEY=... swift run readloop-rag-bench
```

`chunks.jsonl` is the output of step 2 and the input of step 3. It is a dump of
`bookChunks` after `BookIndexPipeline` has indexed the EPUB — not a
reconstruction. `RagCorpusStore` loads it back into the production repository,
so the ablation queries the same code path the app does.

## The gate

`Tests/RagBenchCoreTests/RagCorpusGateTests.swift`. Ten assertions; nothing
failing here may enter a benchmark.

| assertion | why |
|---|---|
| 3 books × 8 chapter resources, >40 children each | the candidate pool has to be big enough for ranking to mean anything |
| adjacent child spans disjoint and monotonic | makes the active chunk unique instead of a coin flip |
| at most one child spans any progression | the property `readingBoundary` relies on; the scan also asserts that gaps *exist*, so the claim is not vacuous |
| zero-width spans exist and can never be active | they are why a boundary can resolve to no active chunk |
| every child's parent resolves; every parent has children | parent references are complete |
| child texts are unique | the leak check identifies a denied chunk by its text |
| every authored query's gold is reachable | judged by `ResolvedReadingBoundary.contains` via the production `readingBoundary` |
| every adversarial target is unreachable | same predicate, opposite direction |
| legit queries are lexically attainable | at least one production FTS term of the query occurs in its gold |
| paraphrase queries share no trigram with their twin | otherwise lexical and semantic retrieval measure the same thing |
| zero leaks under both predicates | measured on what the retriever returns, not on what the corpus expects |

Measured on the current corpus: 315 chunks (226 children, 89 parents) across 24
resources. 0 overlapping adjacent spans, 202 gaps, 51 zero-width spans, at most
1 child spanning any progression, 0 duplicate child texts.

## The ablation

```
swift run readloop-rag-bench [--k N] [--arms a,b,c]
```

Four arms, each a configuration of the production `LocalBookRetriever`:

| arm | semantic | rerank | small-to-big |
|---|---|---|---|
| `lexical` | – | – | off |
| `lexical+smallToBig` | – | – | on |
| `hybrid` | BAAI/bge-m3 | – | on |
| `hybrid+rerank` | BAAI/bge-m3 | BAAI/bge-reranker-v2-m3 | on |

Small-to-big is switched with the expander's own public budget knob, not a
bypass, so both settings run production code.

### Denominators

36 queries: split `dev` 21 / `holdout` 15; intent `legit` 18, `paraphrase` 3,
`adversarial` 6, `edge` 9.

- recall@k, MRR, nDCG — denominator is the **30 gold-bearing queries**, not all
  36. Adversarial queries have no gold: their correct answer is nothing.
- parent recall — denominator is the gold chunks' parents.
- edge correctness — denominator is the 9 edge queries only.
- leak — denominator is all 36.

A slice whose denominator is zero prints `n/a`, not `0`.

### Results (k=5)

| arm | recall@5 | parent recall | MRR | nDCG@5 | edge | leak | evidence |
|---|---|---|---|---|---|---|---|
| `lexical` | 0.883 | 0.850 | 0.908 | 0.897 | 1.000 | 0 | 2.2 × 792 ch |
| `lexical+smallToBig` | 0.883 | 0.850 | 0.908 | 0.897 | 1.000 | 0 | 2.2 × 2078 ch |
| `hybrid` | **0.917** | 0.850 | 0.893 | 0.897 | 1.000 | 0 | 4.1 × 3694 ch |
| `hybrid+rerank` | 0.850 | 0.783 | 0.867 | 0.858 | 1.000 | 0 | 1.4 × 1211 ch |

**Control arm.** `lexical` is the stage under test's upstream. `lexical` and
`lexical+smallToBig` must agree on every ranking metric — if a change to the
expander leaked into ranking they would diverge — and they do, exactly. That
fixes the in-corpus noise floor for ranking metrics at **0.000**.

**Sentinel arms, expected exactly zero.** `leak` is 0 in all four arms under
both predicates; adversarial queries return 0 pieces of evidence in all four
arms.

### Findings

1. **Small-to-big changes the evidence, not the ranking.** The two lexical arms
   are identical on recall, parent recall, MRR, nDCG and edge correctness. Only
   evidence size moves, 792 → 2078 characters. Expansion decides what the
   window says, not which passages win.

2. **Semantic fusion buys a little recall and costs a little rank.** recall@5
   0.883 → 0.917 (+0.034), MRR 0.908 → 0.893 (−0.015), nDCG unchanged. The
   delta is above the measured drift, so it is resolvable rather than noise —
   but it is small.

3. **The reranker hurts on this corpus.** recall 0.917 → 0.850 (−0.067), parent
   recall 0.850 → 0.783, nDCG 0.897 → 0.858, and evidence drops from 3694 to
   1211 characters. `minimumRelevance = 0.25` is discarding passages the fused
   ranking had right. The gate is tuned against bge-reranker's score
   distribution, which this run suggests is too high.

4. **The paraphrase bucket's premise fails.** All four arms score recall@5 =
   0.500 on paraphrase queries: the differently-worded twin (grade 1) is never
   retrieved. The obvious explanation — RRF fusion over a full-length semantic
   list pushes it just below the top-k cut — was tested by re-running at k=10
   and **rejected**: the twin is not in the top 10 either. On this corpus,
   bge-m3 does not connect `把白天的碎片挪进长期仓库` with
   `让新痕迹在旧网络上重新固定`. The bucket still measures something real; what
   it measures is that the design's assumption does not hold here.

5. **Nothing leaked.** Across every arm and every query, no returned excerpt
   carried text from ahead of the reader's cursor, under either the policy
   predicate or the storage predicate.

## Reproducibility

Measured, not assumed:

- The corpus, the query set and the lexical arms reproduce from the repository
  alone: three consecutive runs produced identical metrics to three decimals,
  and `ablation.json` records the SHA-256 of both input files.
- The embedding layer turned out to be reproducible too. Two calls with the
  same input returned bit-identical vectors (matching SHA-256 of the 1024-float
  response). That contradicts the working assumption that a remote embedding is
  never bit-reproducible, and it is why all three runs agreed on the semantic
  arms as well.
- This is an empirical property of one provider today, not a guarantee. A
  backend change, a batching difference or an added nondeterminism would break
  it, and nothing in the harness would notice. Assume the semantic arms are
  reproducible only until a run says otherwise.

## Known limits

- 36 queries is enough to separate the arms on recall, not enough to be
  confident about small deltas in any single slice — the `holdout` slice has 12
  gold-bearing queries.
- One embedding model and one reranker were measured. The findings are about
  those models, not about the techniques.
- `edge` correctness is 1.000 in every arm, so it currently discriminates
  nothing; it is kept as a regression guard for boundary changes.
- The corpus is three books by one author working from one design table. It is
  controlled, not representative.

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
swift run readloop-rag-bench [--k N] [--arms a,b,c] [--rerank-floors f1,f2,...]
```

`--rerank-floors` replaces the ladder's rerank arm with one arm per floor, so a
single run shows whether a reranker's harm comes from its ordering or from the
relevance threshold it filters with.

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

**Read the per-query basis before reading the aggregate.** 27 of the 30
gold-bearing queries have the *same gold rank* in `lexical` as in `hybrid`, and
the median gold rank is 1 in every arm. Columns differ by one or two queries:

| change | queries that moved at all | queries whose hit/miss flipped |
|---|---|---|
| `lexical → hybrid` | 3 of 30 | 1 (b3-legit-01, 0.000 → 1.000) |
| `hybrid → rerank` | 6 of 30 | 2 (b1-legit-03, b2-legit-02, 1.000 → 0.000) |

So none of the aggregate deltas are estimates of a rate. They are the effect of
a handful of queries, and they are reported here as such.

1. **Small-to-big changes the evidence, not the ranking.** The two lexical arms
   are identical on recall, parent recall, MRR, nDCG and edge correctness. Only
   evidence size moves, 792 → 2078 characters. This one is a property of the
   code, not a discovery: the expander runs downstream of ranking, and evidence
   ids are parent ids whatever the window size. It is kept as a regression
   guard.

2. **Semantic fusion rescues lexical failures and nothing else.** Every query
   where the two arms differ is one the lexical lane missed outright. On the 27
   queries lexical already ranks first, fusion changes nothing. The pattern is
   stable across k rather than a single-point artifact:

   | k | lexical recall | hybrid recall | lexical MRR | hybrid MRR |
   |---|---|---|---|---|
   | 3 | 0.850 | 0.867 | 0.900 | 0.878 |
   | 5 | 0.883 | 0.917 | 0.908 | 0.893 |
   | 10 | 0.883 | 0.917 | 0.908 | 0.893 |
   | 20 | 0.883 | **0.967** | 0.908 | 0.895 |

   Lexical saturates at k=5 and never improves again; the semantic lane keeps
   finding gold as k grows. But MRR is *worse* at every k. The lane buys tail
   recall with head precision — and the product's context budget is
   `evidenceLimit = 4`, which is the head.

3. **The reranker is a net loss, and the threshold is not the reason.** Sweeping
   the relevance floor separates reordering from filtering:

   | arm | recall@5 | parent | MRR | nDCG | evidence |
   |---|---|---|---|---|---|
   | `hybrid` (no rerank) | 0.917 | 0.850 | 0.893 | 0.897 | 3694 ch |
   | `rerank@0.00` | 0.883 | 0.817 | 0.873 | 0.871 | 3737 ch |
   | `rerank@0.10` | 0.883 | 0.783 | 0.873 | 0.871 | 1624 ch |
   | `rerank@0.20` | 0.883 | 0.783 | 0.873 | 0.871 | 1323 ch |
   | `rerank@0.30` | 0.850 | 0.783 | 0.867 | 0.858 | 1186 ch |
   | `rerank@0.50` | 0.850 | 0.783 | 0.867 | 0.858 | 893 ch |

   At floor 0 the reranker filters nothing at all — evidence is 3737 characters
   against the baseline's 3694 — and recall still falls 0.917 → 0.883. So the
   harm is the cross-encoder's *ordering*, and tuning `minimumRelevance` can
   only recover the part the floor added. The reranker sees the fused top 10; it
   has no access to the rank-11–20 rescues that are the semantic lane's whole
   contribution, and its reordering costs a gold that RRF had placed at rank 5.

4. **The paraphrase bucket: the twin is reachable, but deep.** At k=5 no arm
   retrieves any of the three twins (recall 0.500 in all four arms). At k=20 the
   semantic lane retrieves one of them (b2-paraphrase-01, 0.500 → 1.000). So the
   embedding does connect the two wordings — weakly, at rank 11–20. An earlier
   version of this document called the connection impossible on the strength of
   a k=10 run; that was one point on a curve and it was wrong to generalise from
   it. What holds: on this corpus the paraphrase twin is never a top-5 result,
   so the bucket measures the semantic lane's ceiling rather than its typical
   behaviour.

5. **Nothing leaked.** Across every arm and every query, no returned excerpt
   carried text from ahead of the reader's cursor, under either the policy
   predicate or the storage predicate.

### What the corpus cannot tell you

The queries were authored by someone who knew where the gold was, and the gate
*requires* every legit query to share a trigram with its gold. Both push the
corpus toward lexical success. "Lexical recall 0.883" is therefore not an
estimate of production retrieval quality, and quoting it as one would repeat the
error that got the previous corpus withdrawn.

The deeper problem is difficulty, not sample size. Gold rank is 1 for 27 of 30
queries: the corpus has no headroom at the top, so no ordering strategy can show
an improvement there. Where queries are hard enough to discriminate — the
paraphrase bucket — they are hard enough that little succeeds. There is almost
no middle. What this harness needs next is not more queries but *harder* ones:
queries anchored semantically rather than lexically, whose wording does not
appear in the passage that answers them.

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

- One embedding model and one reranker were measured. The findings are about
  those models, not about the techniques.
- `edge` correctness is 1.000 in every arm, so it currently discriminates
  nothing; it is kept as a regression guard for boundary changes.
- The corpus is three books working from one design table. It is controlled,
  not representative.

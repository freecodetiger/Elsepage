# Local Per-Book Retrieval — Execution Record

Status: implemented baseline; physical-device quality evaluation pending  
Scope: EPUB book evidence only; no Memory/Profile/Wisdom RAG

## Architecture

```text
EPUB / Readium Publication
  -> ReadiumBookContentExtractor (App adapter)
  -> BookTextBlock (full start/end Locator JSON)
  -> StructureAwareChunker
  -> GRDBBookIndexRepository
       -> chapters / sections / text blocks / chunks
       -> FTS5 trigram
       -> optional embedding BLOBs
  -> LocalBookRetriever (lexical or RRF hybrid)
  -> ReaderAgentContextBuilder (read-so-far + 4k character budget)
  -> ReaderAgentPolicy (untrusted evidence)
```

Dependency direction is deliberate: `RetrievalCore -> LibraryCore + ReaderCore`;
`Persistence -> RetrievalCore`; `ReaderAgent -> RetrievalCore + AgentRuntime`.
`AgentRuntime` has no retrieval/product dependency. Readium remains in the App
adapter and GRDB remains in Persistence.

## Lifecycle and recovery

- Import returns after the EPUB is validated, copied and its Book row commits.
- `BookIndexCoordinator.enqueue` starts only after import and never blocks Reader.
- `bookIndexJobs` stores version, state, next spine resource, diagnostic and time.
- Each completed resource replaces its blocks/chunks and FTS rows transactionally.
- A crash within a resource repeats that resource; deterministic IDs and replace
  semantics converge without duplicates.
- Startup enqueues missing/failed/incomplete jobs. `lexicalReady` is a valid
  terminal baseline when no embedding provider is configured.
- Book deletion cascades all derived rows; an explicit trigger cleans the FTS5
  virtual table.

## Retrieval behavior

- Structure/resource/section boundaries win over size; paragraph-like Readium
  elements aggregate to a 900-character target and split only above 1,400.
- FTS5 trigram is the mandatory offline baseline. Two-character queries use a
  scoped local substring fallback because trigram cannot represent them.
- Embeddings are optional behind `EmbeddingProvider`; vectors are versioned by
  model and stored as flat Float BLOBs. No network key is required by tests.
- Flat cosine search and reciprocal-rank fusion centralize hybrid ranking without
  comparing provider-specific raw score scales.
- Retrieval defaults to read-so-far using spine ordinal plus in-resource
  progression. Unknown Locator/spine boundaries produce no book evidence.
- Evidence retains exact Readium Locator JSON for later source navigation.

## Automated evidence

- deterministic structure-aware chunking and oversized split;
- stable chunk IDs and exact Locator preservation;
- migration v1 -> v7 and schema creation;
- FTS Chinese/English retrieval and read-so-far exclusion;
- transactional idempotent replacement and cascade/FTS cleanup;
- embedding BLOB round-trip, flat cosine and RRF;
- interruption -> failed job -> restart -> lexical-ready convergence;
- context character budget and spoiler boundary;
- hosted Readium test opens the legal minimal EPUB, extracts content, builds the
  index and finds navigable FTS evidence.

## Deferred within retrieval

- A production local or BYOK embedding implementation. The abstraction and
  storage/search path exist; current product behavior honestly uses FTS.
- Retrieval evaluation corpus, thresholds and ReaderAgent quality benchmarks.
- Accelerate optimization; flat Swift cosine is adequate until measured otherwise.
- Chapter/section digest generation. It must not be added before passage retrieval
  quality is measured.

## Device verification

On a physical iPhone, import a multi-chapter EPUB, immediately open/read it, kill
the app mid-index, relaunch, and verify the job converges. Create a Reflection near
the middle and inspect logs/debug data to confirm retrieved evidence is earlier
than the current Locator and opens the exact passage. This has not been claimed as
completed by automated generic-device builds.

# RAG corpus — design

The corpus exists to measure retrieval, so its *semantics* are designed, not
incidental. Everything below is a controlled property; the query set depends on
each one landing where this table says it lands.

## Provenance

`source/<book>/` is hand-written XHTML, committed, diffable. `epub/<book>.epub`
is produced by `Scripts/build-corpus-epub.sh`, which packs twice and compares
byte-for-byte. `chunks.jsonl` is **not** derived from the source by any script —
it is dumped out of GRDB after the production `BookIndexPipeline` has indexed
the EPUB in the iOS simulator (`RagCorpusSnapshotTests`). Nothing in the
pipeline re-implements chunk geometry: a second implementation is exactly the
drift that invalidated the previous corpus.

## Geometry (measured, not assumed)

Production chunker, `indexVersion = 3`, default sizing. Measured on the sample:

| property | value |
|---|---|
| adjacent child spans | never overlap; monotonically ordered within a resource |
| gaps between adjacent child spans | present (~1 per child) — so the cursor-crossing gate is **at most 1**, never *exactly* 1 |
| zero-width spans (`start == end`) | present — a single-block child can never be the active chunk |
| children spanning any given progression | **at most 1** |

That last row is the whole point. `GRDBBookIndexRepository.readingBoundary`
picks the active chunk from children whose span strictly contains the cursor.
With several co-located candidates the pick is arbitrary; here it is unique.

## Books

Three books, eight chapters each, 2800–3500 characters per chapter. Different
domains, so a query in one book has no business matching another.

### book-01 《睡眠与记忆》

| ch | title | controlled property |
|---|---|---|
| 01 | 一夜之间的三个班次 | sleep stages; sleep debt vs circadian clock |
| 02 | 记忆要过三道手 | **paraphrase W1** |
| 03 | 深睡时大脑在搬家 | 海马体, 重放 |
| 04 | 梦是夜里的排练吗 | |
| 05 | 睡不够的人会怎样 | |
| 06 | 复习为什么要趁早 | **paraphrase W2** |
| 07 | 突触稳态假说 | **late-only term** |
| 08 | 夜里清洗大脑的管道 | **late-only term** |

### book-02 《城市的呼吸》

| ch | title | controlled property |
|---|---|---|
| 01 | 街道是谁的客厅 | |
| 02 | 长椅与停留的权利 | **paraphrase W1** |
| 03 | 步行尺度从哪里来 | |
| 04 | 广场为什么空着 | |
| 05 | 边界的作用 | |
| 06 | 陌生人之间的信任 | **paraphrase W2** |
| 07 | 破窗之后 | **late-only term** |
| 08 | 一座城市的记忆装置 | **late-only term** |

### book-03 《翻译的边界》

| ch | title | controlled property |
|---|---|---|
| 01 | 译者在两种语言之间 | |
| 02 | 词没有一对一的座位 | **paraphrase W1** |
| 03 | 音译留下的痕迹 | |
| 04 | 译者的隐身与现身 | |
| 05 | 什么在翻译中丢失 | |
| 06 | 重译的必要 | **paraphrase W2** |
| 07 | 对等这件外套 | **late-only term** |
| 08 | 译本也会变老 | **late-only term** |

## The two properties, and why they exist

**Paraphrase recurrence.** One concept is stated twice, in wording that shares
no three-character substring: W1 in chapter 02, W2 in chapter 06. Lexical
retrieval (FTS trigram) can only ever reach the copy whose wording the query
echoes; semantic retrieval should reach both. Without this, the lexical and
semantic arms are measuring the same thing and the ablation says nothing.

| book | W1 (ch02) | W2 (ch06) |
|---|---|---|
| 01 | `把白天的碎片挪进长期仓库` | `让新痕迹在旧网络上重新固定` |
| 02 | `让人愿意停下脚步的余地` | `把路过的人留成在场的人` |
| 03 | `两种语言之间没有并排的座位` | `意义在换轨的地方会掉落一点` |

**Late-only terms.** A distinctive term appears in chapter 07 or 08 and
nowhere else in the corpus. A query built from it, with the cursor parked in
chapter 03, is the adversarial case: the answer exists in the book and is
behind the reader. It must be unreachable.

| book | ch07 | ch08 |
|---|---|---|
| 01 | `突触稳态假说` | `胶质淋巴系统` |
| 02 | `破窗理论` | `场所精神` |
| 03 | `动态对等` | `译本的生命周期` |

These six strings plus the six W1/W2 strings are the only strings that are
reserved. Every other word is free.

## Query wording

`ftsTerms` folds the query, splits on anything that is not a letter or digit,
turns each CJK token into all of its 3-character windows, and keeps the first
16. Two consequences the query set is built around:

- A query reaches a chunk only if some 3-character substring of the query
  appears verbatim in that chunk. Legit queries therefore echo the target's
  wording; the discriminating phrase goes near the front of the query.
- Queries stay short, so the 16-term cap does not silently truncate the part
  that mattered.

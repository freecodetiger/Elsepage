# Phase 15: Persistent Embedding + BrainRetriever - Context

**Gathered:** 2026-08-29
**Status:** Ready for planning
**Source:** PRD Express Path(docs/brain.md §6,§12,§20 Phase 4)

<domain>
## Phase Boundary

Brain 检索基建:`brainItemEmbeddings` 持久化向量表 + `BrainEmbeddingStore` 协议(GRDB 实现)+ `BrainRetriever`(lexical + 持久化 embedding + RRF,kinds 过滤,输出 BrainCandidate)。交付后 Thought/Question/Memory 可语义检索。

本 phase **不含**:检索的消费方(Phase 16 Agent Bridge 适配为 ContextCandidate;Phase 17 投影服务用它取候选)、query 向量的语义缓存接入(Phase 19 观测时评估)、App 装配(随消费方 phase 落地)。
</domain>

<decisions>
## Implementation Decisions

### 模块与协议(锁定)
- `BrainEmbeddingStore` 协议 + `BrainItemVector` 定义在 **BrainCore**;GRDB 实现在 Persistence;**BrainRetriever 落在 ContextEngineering**(复用 ReflectionLexicalMatcher.tokens、HybridFusion、EmbeddingProvider、VectorMath,与 MemoryRetriever/ReflectionRetriever 同族同模式)。Package.swift:ContextEngineering 增加 BrainCore 依赖。
- 向量表 **PK(brainItemID, model)**:换模型保留旧行(与 bookChunkEmbeddings 同策略);FK CASCADE 到 brainItems,条目删除向量自动清理,无需手动 GC。

### 刷新策略(锁定,对应"创建一次、反复检索、不重复 embed")
- 每条目存 `contentHash`(SHA256 of 参与检索的文本:thought.statement / question.question / memory.content)。检索时:比对库内 hash 与当前 hash,**仅缺失或过期者重 embed**,单次查询刷新上限 16 条(延迟上界);写回 store。内容未变 → 零 embed。
- 退化链:provider 为 nil / factory 解析失败 / embed 抛错 → 语义通道整体跳过,纯 lexical 照常(沿用 LocalBookRetriever/MemoryRetriever 的退化模式)。

### 检索语义(锁定)
- 词法通道:与 MemoryRetriever 完全同款(CJK 分词,query tokens ≥2,overlap 相关度 ≥0.30)。
- 语义通道:独立 lane,cosine 阈值 0.2;维度不符的存量向量视为过期重刷。
- 融合:HybridFusion.ranked(RRF);BrainCandidate { item, lexicalScore, semanticScore }。
- 资格过滤:kinds 集合过滤;memory 状态 superseded/forgotten 排除;thought stage archived 排除;候选池最近 30 条(与 Memory/Reflection retriever 一致)。
- evidenceSummary(brain.md §12 草图字段)延后:Phase 16 适配 ContextCandidate 时按需补,避免本 phase 逐条目 N 次证据查询。

### the agent's Discretion
- BrainRetriever 的构造参数命名与默认值;测试用假 provider 的向量映射方式;查询向量不做缓存(Phase 19 评估接入 SemanticVectorCache)。

</decisions>

<canonical_refs>
## Canonical References

- `docs/brain.md` §6(持久化 embedding 表)、§12(统一检索 primitive)、§20 Phase 4
- `Sources/ContextEngineering/MemoryRetriever.swift` — 词法/语义双通道 + HybridFusion 模式(照此模式)
- `Sources/ContextEngineering/ReflectionLexicalMatcher.swift:44` — CJK 分词
- `Sources/Persistence/BookIndexRepository.swift:184-236` — Float↔Blob 编码与模型切换策略(照抄模式)
- `Sources/Persistence/AppDatabase.swift` v22 — 迁移与 wipe 清单模式
- `Sources/BrainCore/BrainRepository.swift` — 资格过滤所需的域模型

</canonical_refs>

<deferred>
## Deferred Ideas

- evidenceSummary / 证据计数入 BrainCandidate → Phase 16(适配 ContextCandidate 时)
- query 向量接入 SemanticVectorCache + hit/miss 观测 → Phase 19
- App 装配(EmbeddingProvider factory 复用 RAG 设置)→ Phase 16/17 随消费方
- 向量行的模型清理(删旧模型行)→ 出现模型切换需求时

</deferred>

---

*Phase: 15-brain-retriever*
*Context gathered: 2026-08-29 via PRD Express Path*

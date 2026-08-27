# Context Engineering 演进 — 系统规范

> **状态**:计划 / 未实施(2026-08-27 由用户侧定义,作为后续演进的方向性规范)。
> **与现状的关系**:本文描述的是**目标形态**,不是当前实现。当前实现的权威快照见根目录 `ARCHITECTURE.md`(漂移快照,非权威真相)。
> **约束**:若源码/现有架构 invariant 与本文冲突,**以源码和现有 invariant 为准**,不要为了迎合本文强行修改正确设计。
>
> 目标不是增加更多 Agent,也不是重写现有 ReaderAgent,而是把当前:
>
> `Context Router → Retrieval → Evidence Assembly → ReaderAgent`
>
> 演进为更清晰、可扩展、可评测的:
>
> `Context Planner → Source-specific Retrieval → Context Candidates → Ranking / Budgeting → Small-to-Big Expansion → Context Bundle → ReaderAgent`
>
> 必须最大程度保持当前系统的可靠性边界、模块边界和退化链。

---

## 一、现状基线

当前 ElsePage 已具备:

- `ReaderAgent` 主回答链路
- `LLMReaderContextRouter`
- `ContextPlanValidator`
- `DeterministicReaderContextRouter` fallback
- `LocalBookRetriever`
- FTS5 / BM25 lexical retrieval
- Embedding cosine semantic retrieval
- RRF fusion
- Cross-Encoder reranker
- `ReadingBoundary` 防剧透
- `AgentCitationValidator`
- `AgentExecutor + ExecutionBudget`
- `routingTraces / ContextDisclosure`
- Reflection / Memory retrieval
- GRDB / SQLite 本地持久化

当前 Book Retrieval 约为:

```text
query
→ FTS5/BM25
→ query embedding + 全书向量 cosine
→ RRF
→ rerank
→ evidence
```

当前 chunk 大约为:

- target ≈ 900
- max ≈ 1400
- overlap ≈ 150
- structure-aware chunking

**这些都不是要被推翻的东西。**

---

## 二、本次明确要做的四项演进

### P1:ContextRouter → Context Planner

当前 Router 不应只回答:

- 是否检索 book
- 是否检索 past thoughts
- 使用多少 evidence

需要将其升级成一个真正的 **Context Plan / Retrieval Plan 生成器**。

#### 目标

Router 输出应能够表达:

```text
用户需要哪些 Context Source?
↓
每个 Source 的检索范围是什么?
↓
Dense Query 是什么?
↓
Lexical Query / Terms 是什么?
↓
使用 dense / lexical / hybrid 哪种策略?
↓
取多少候选?
↓
是否 rerank?
↓
最终 Context Budget 是多少?
↓
Book evidence 命中后使用什么 expansion policy?
```

#### 推荐数据模型

不要机械照搬下面字段名,但语义至少应覆盖:

```swift
ContextPlan {
    intent

    sources

    bookRetrieval {
        scope
        denseQuery
        lexicalTerms
        retrievalMode
        candidateLimit
        evidenceLimit
        useReranker
    }

    reflectionRetrieval
    memoryRetrieval

    contextExpansion {
        mode
        maxTokens
    }

    budgets {
        nearbyPassage
        bookEvidence
        reflection
        memory
        conversation
    }
}
```

#### 关键原则

1. Router 负责"需要什么"。
2. Retriever 负责"怎么找到"。
3. Context Assembler 负责"最终给模型什么"。
4. 不允许 Router 自己直接拼最终 Prompt。
5. 所有 Router 输出继续经过确定性的 `ContextPlanValidator`。
6. LLM 产生的 scope / limit / strategy 都必须经过代码层 clamp / validation。
7. `ReadingBoundary` 仍然由确定性代码提供,不允许 Router 自己决定用户读到了哪里。

#### Dense Query 与 Lexical Query 分离

不要默认让 Dense Retrieval 和 BM25 直接使用同一个用户字符串。

例如用户:

> "我觉得他这里不像是真的难过。"

可以生成:

```text
denseQuery:
寻找当前人物表现出的情绪疏离、悲伤反应以及此前相关心理和叙事铺垫

lexicalTerms:
角色名 / 母亲 / 葬礼 / 哭 / 悲伤 / 冷漠
```

- Dense Search 负责语义召回。
- BM25 / FTS5 负责人物名、术语、原句、实体等词法召回。
- 如果 LLM 没有生成有效 lexical terms,应能安全 fallback 到原 Query。

---

### 三、P2:引入 Child Retrieval + Small-to-Big Context Expansion

当前 900~1400 token 的结构化 chunk 同时承担:

- embedding unit
- BM25 retrieval unit
- evidence unit

请将这三个职责解耦。

#### 目标结构

保留当前较大的结构化 chunk,重新定义它为:

`Parent Context`

在 Parent 内再生成更小的:

`Retrieval Child`

推荐初始范围:

- Child target:约 250~450 tokens
- Parent:沿用当前约 900~1400 tokens 或天然 section / paragraph group
- 优先沿用章节、小节、段落结构
- 不要为了 token 数量破坏自然语义结构

形成:

```text
Parent P17
├── Child C51
├── Child C52
├── Child C53
└── Child C54
```

#### 索引策略

优先:

```text
Child
→ FTS5
→ Embedding
→ Retrieval
```

而不是直接用 Parent 作为主要语义检索单元。

每个 Child 至少保存:

```text
childID
parentID
bookID
startLocator / endLocator
startProgression / endProgression
text
indexVersion
```

Parent 保留:

```text
parentID
bookID
text
structural metadata
boundary information
```

#### Small-to-Big Retrieval

流程:

```text
Query
↓
Child retrieval
↓
RRF / rerank
↓
命中 Child C53
↓
根据 parentID / neighbor relation
扩展为更完整 Context
↓
最终 Book Evidence
```

注意:

**Small-to-Big 不是再次使用命中 Child 做向量搜索。**

第二步是确定性的结构扩展:

- parent lookup
- sibling window
- neighboring children
- token-budget bounded expansion

#### Expansion Policy

建立明确的 `ContextExpansionPolicy` 或等价抽象。

至少支持一种可靠策略:

```text
命中 Child
↓
以 Child 为中心
↓
向左右 sibling 扩展
↓
最多达到 maxTokens
↓
不能越出 Parent / Section
```

如果 Parent 本身足够小,也允许直接取 Parent。

---

## 四、防剧透必须贯穿 Small-to-Big

这是本次改造的**硬约束**。

当前 ReadingBoundary 逻辑必须保留,而且 Expansion 后需要新增一次防剧透校验。

因为:

```text
Child.end <= readingPosition
```

不意味着:

```text
Parent.end <= readingPosition
```

例如:

```text
Child:
36.5% → 36.9%

Parent:
35% → 39%

User:
37.2%
```

Child 合法,但整个 Parent 不合法。

因此必须:

```text
Child Retrieval
↓
ReadingBoundary Filter
↓
Expansion
↓
ReadingBoundary Re-validation
↓
必要时裁剪未来部分
```

最终给 ReaderAgent 的任何书籍证据:

```text
evidence.end <= currentReadingBoundary
```

必须由**确定性代码**保证。

不要依赖 Prompt 中的"不要剧透"。

当前这些机制必须保留:

- lexical SQL boundary predicate
- semantic candidate filtering
- final boundary verification
- no boundary → no book evidence

---

## 五、P4:升级 Reflection / Memory Retrieval

当前 Past Reflection / Memory 主要依靠 lexical matching。

请将它们演进为:

```text
lexical
+
semantic
```

但不要把所有 Source 直接扔进一个统一 Vector DB 混搜。

#### 推荐抽象

建立公共协议/模型,例如:

```swift
RetrievableItem
ContextSourceRetriever
RetrievalCandidate
```

不同 source 可以共享:

- text
- id
- sourceType
- metadata
- embedding
- lexical score
- semantic score
- timestamps

但分别保留:

```text
BookRetriever
ReflectionRetriever
MemoryRetriever
```

由 Context Planner 决定调用哪些 Retriever。

#### Reflection Retrieval

支持:

```text
lexical recall
+
semantic recall
+
fusion
```

并保留目前这些行为(除非源码证明需要调整):

- same-book 优先
- cross-book 更谨慎
- strongest connection
- connection persistence

#### Memory Retrieval

同样支持 semantic matching,但需要保持 Memory 和 Reflection 的语义边界:

- Reflection:用户在某次阅读中的具体思考
- Memory:更稳定、长期、抽象的用户信息/观点

不要因为实现统一 Retriever 抹平这两个 source。

---

## 六、P5:增加 ContextCandidate Ranking / Budgeting 层

当前多个 evidence source 最终会进入 ReaderAgent:

```text
nearby passage
book evidence
past reflection
memory
conversation
```

请不要继续让它们只是"每种各拿几个然后拼起来"。

建立统一:

```swift
ContextCandidate
```

推荐至少包含:

```swift
id
source
content
relevance
confidence
tokenCost
importance
recency?
metadata
```

注意:这些 score 不要求一开始全部复杂建模。第一版可以使用简单、可解释、确定性的策略。

---

## 七、增加 Context Assembly 层

建立明确:

```text
Context Sources
↓
Context Candidates
↓
Deduplicate
↓
Prioritize
↓
Token Budget Packing
↓
Context Expansion
↓
Boundary Validation
↓
Context Bundle
↓
ReaderAgent
```

ReaderAgent 不应自己越来越多地承担:

- Retrieval policy
- Source competition
- Token budgeting
- Expansion

这些应逐步移到 Context Engineering 层。

#### Token Budget

不要使用简单:

```text
搜到多少塞多少
```

而应该按照 ContextPlan 分配预算。

例如:

```text
conversation
nearby passage
book evidence
reflection
memory
```

各有预算。

如果超预算,优先使用:

1. relevance
2. source priority
3. confidence
4. token cost

做确定性裁剪。

**不要为了压缩 Context 新增一个额外 LLM summarizer**,除非当前代码已经存在这类能力。

---

## 八、Context Candidate 去重

必须考虑多个 retrieval channel 命中相同或高度重叠内容:

```text
BM25 → Child 17
Dense → Child 17

Dense → Child 18
Child17 / Child18 属于同一 Parent
```

不能最终重复塞入大量相同 Context。

至少实现:

- same ID dedup
- sibling / overlapping range merge
- same Parent 的合并策略

如果多个 Child 属于同一 Parent,应优先形成一个连续、结构完整的 Context Window,而不是重复输出多个 fragment。

---

## 九、Retrieval 链路目标形态

Book Retrieval 最终目标:

```text
ContextPlan.bookRetrieval
        ↓
Metadata / ReadingBoundary
        ↓
┌─────────────────────────┐
│                         │
Dense Query          Lexical Query
│                         │
Child Embedding       FTS5 / BM25
│                         │
TopK                      TopK
└──────────┬──────────────┘
           ↓
         RRF
           ↓
      Candidate TopK
           ↓
       Cross Encoder
           ↓
      Retrieval Children
           ↓
   Context Expansion Policy
           ↓
   Spoiler Boundary Re-check
           ↓
   Merge / Deduplicate
           ↓
     Book ContextCandidate
```

然后:

```text
Book Candidates
Reflection Candidates
Memory Candidates
Nearby Passage
Conversation
        ↓
Context Rank / Budget
        ↓
Context Bundle
        ↓
ReaderAgent
```

---

## 十、本次明确不要做的内容

### 不做 P3:Router Fast Path

不要:

- 绕过 LLM Router
- 建新的 heuristic pre-router
- 改变 Router 每次执行的行为模型

保留当前:

```text
LLM Router
↓
fallback Deterministic Router
```

架构。本次只增强 Context Plan 的表达能力。

### 不做 P6:ANN / HNSW / SQLite Vector 扩展

当前 semantic retrieval:

```text
load candidate vectors
↓
VectorMath.cosine
↓
TopN
```

继续保留。

不要:

- 引入 HNSW
- 引入 sqlite-vec
- 引入 Qdrant / Milvus
- 重写 Vector Storage
- 增加 ANN dependency

当前规模下 brute-force cosine 是可接受的。

但请确保新 Child Retrieval 不把向量加载、过滤逻辑写死到未来无法替换的程度。设计接口时允许未来替换 ANN backend,但本次不实现。

---

## 十一、保持现有可靠性能力

以下能力**不可回退**:

### Agent Runtime

保留:

- ExecutionBudget
- maxModelCalls
- maxWallTime
- maxOutputTokens
- `.truncated`
- `.cancelled`
- error normalization

### Routing

保留:

- structured output
- JSON fence stripping
- deterministic fallback
- ContextPlanValidator
- fallback reason tracing

### Retrieval

保留完整退化链:

```text
无 embedding
→ lexical only

rerank unavailable / failed
→ fused result

index unavailable
→ graceful fallback

ReadingBoundary unavailable
→ no book evidence
```

### Citation

保留:

- evidence ID validation
- book index validation
- ReadingBoundary validation
- persisted response evidence

---

## 十二、Persistence / Migration 要求

请先审视当前:

```text
bookChunks
bookChunksFTS
bookChunkEmbeddings
bookIndexJobs
```

再设计最小迁移。

优先考虑:

```text
Parent Chunk
+
Retrieval Child
```

而不是破坏现有表的语义。

可以新增类似:

```text
bookRetrievalChunks
bookRetrievalChunksFTS
bookRetrievalChunkEmbeddings
```

也可以根据当前 repository 抽象选择更干净的 schema。

必须满足:

1. migration 可测试
2. old index 可识别
3. `indexVersion` 正确升级
4. 不产生旧 embedding 与新 Child embedding 错配
5. model/version/dimension 继续可追踪
6. 删除/重建一本书索引时 Child/Parent/FTS/Embedding 不产生孤儿数据

---

## 十三、Observability 必须同步升级

当前已有 `routingTraces`。

请补充能够观察新的 Context Pipeline。至少应能知道:

```text
Router intent
selected sources

dense query
lexical terms
retrieval mode

lexical candidate count
semantic candidate count
RRF candidate count
rerank candidate count

retrieved child count
expanded context count

reflection candidate count
memory candidate count

context token budget
actual context tokens

deduplicated count

spoiler-filtered count

fallback reason

routing duration
retrieval duration
expansion duration
context assembly duration
reply duration
```

不要求把所有 Query 内容永久记录,如果存在隐私风险,可记录摘要、hash 或 debug-only 字段。

---

## 十四、Evaluation / Tests

这次不能只做到"能运行"。需要建立足够的 retrieval / context pipeline 测试。

至少覆盖:

### Context Planner

- structured output decode
- invalid output fallback
- denseQuery / lexicalTerms validation
- source scope clamp
- budget clamp

### Chunking

- Parent/Child 正确关联
- Child 不跨越错误结构边界
- indexVersion migration
- overlap / locator 正确

### Retrieval

- lexical child retrieval
- semantic child retrieval
- RRF fusion
- rerank
- rerank failure fallback

### Small-to-Big

- child → parent
- child → sibling window
- token budget
- duplicate parent merge

### Spoiler Safety

重点测试:

```text
合法 Child
+
Parent 跨 ReadingBoundary
```

最终 Context 必须被裁剪。

还要覆盖:

- lexical 不召回未来内容
- semantic 不召回未来内容
- expansion 不引入未来内容
- final evidence validator 继续兜底

### Reflection / Memory

- lexical + semantic fusion
- same-book preference
- cross-book retrieval
- unrelated memory 不进入结果

### Context Assembly

- source competition
- token budget
- deterministic priority
- overlapping evidence dedup
- Context Bundle 输出稳定

---

## 十五、实现方式要求

不要一次性重写全部模块。先建立清晰的迁移计划,再分阶段实现。

建议顺序:

```text
Phase 1
ContextPlan 模型升级
+
Validator
+
Router Prompt

Phase 2
ContextCandidate / ContextBundle 抽象

Phase 3
Parent / Child Index Schema
+
Index migration
+
Child indexing

Phase 4
Book Child Retrieval
+
Small-to-Big Expansion
+
Spoiler Re-check

Phase 5
Reflection / Memory semantic retrieval

Phase 6
Context Ranking / Dedup / Budgeting

Phase 7
ReaderAgent 接入新的 ContextBundle

Phase 8
Observability + Evaluation + Cleanup
```

每个 Phase 必须保持:

```text
buildable
testable
reversible enough to debug
```

不要在一个 commit-sized change 中同时重写 Router、Retriever、Persistence 和 ReaderAgent。

---

## 十六、设计原则

整个实现始终遵循:

### 1. LLM 做语义判断,代码做硬约束

LLM:

```text
intent
query rewrite
source selection
retrieval strategy
```

确定性代码:

```text
ReadingBoundary
budget
limits
schema
citations
fallback
validation
```

### 2. Source-specific retrieval

不要做:

```text
所有 Context
→ 一个大 Vector DB
→ TopK
```

而做:

```text
Planner
├── BookRetriever
├── ReflectionRetriever
└── MemoryRetriever
```

### 3. Small-to-Big

```text
小粒度负责找到
大粒度负责理解
```

### 4. Context 是有限资源

最终优化目标不是:

```text
retrieve more
```

而是:

```text
在有限 token budget 下,
最大化 Context 的相关性、完整性和可信度。
```

### 5. 防剧透属于 Data Access Policy

不是 Prompt 风格要求。

---

## 十七、开始工作前与完成后的要求

### 开始工作前(先完成这些,不要立即修改代码)

1. 阅读当前 Agent / Retrieval / Persistence / ContextRouting 实现。
2. 对照当前架构图确认哪些描述仍然与源码一致。
3. 找出这次演进会影响的 package / module / table / protocol。
4. 输出一份简洁实施计划。
5. 明确哪些现有 invariants 必须保持。
6. 明确 database migration strategy。
7. 明确 index version strategy。
8. 明确测试矩阵。

然后开始按 Phase 实施。

如果源码与本文描述冲突:**以源码和现有架构 invariant 为准,不要为了迎合本文强行修改正确设计。**

### 实现完成后

- 运行相关 unit tests
- integration tests
- build
- lint/typecheck(如果项目存在)
- database migration tests
- retrieval tests

并最终**更新架构文档**,使其准确反映新的:

```text
Context Planner → Retrieval → Context Candidate → Expansion → Context Bundle → ReaderAgent
```

完整链路。

### 完成后输出清单

最后输出:

1. 实际修改的架构
2. 新增的核心 abstractions
3. 数据库/index migration
4. Retrieval 行为变化
5. 防剧透如何保证
6. Context budgeting / dedup 机制
7. 新增测试
8. observability changes
9. 未完成项
10. 后续可以考虑、但本次明确未实现的 P3 Router Fast Path 与 P6 ANN/HNSW

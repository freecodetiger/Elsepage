# Phase 12: Brain Domain + Persistence - Context

**Gathered:** 2026-08-29
**Status:** Ready for planning
**Source:** PRD Express Path(docs/brain.md)

<domain>
## Phase Boundary

按 `docs/brain.md` §1-6、§19-20 Phase 1 落地 Brain Domain 与持久化:Thought/Question/Memory 三类一级对象的强类型域模型、`brainItems` 表、`BrainRepository` 仓储、既有 `memories` 的一次性幂等回填。交付后能力:三类对象可可靠存储,kind → 强类型域对象映射,旧数据无缝进入 Brain。

本 phase **不含**:Evidence/Relation 表(Phase 14)、Embeddings/BrainRetriever(Phase 15)、Agent 接入(Phase 16)、LLM 投影(Phase 17)、Revisions(Phase 18)、UI(Phase 13)。
</domain>

<decisions>
## Implementation Decisions

### 领域模型(brain.md §3,锁定)
- `BrainItem` 为 tagged union:`case thought(Thought) / question(Question) / memory(BrainMemory)` — 禁止 `type: String + 全可选字段` 的弱模型;非法状态不可表示。
- `ThoughtStage`: emerging / evolving / stable / reconsidering / archived(禁用 `isStable: Bool`)。
- `QuestionState`: open / exploring / partiallyResolved / resolved / dormant(解决不删除,转变由关系表达,Phase 14 落地)。
- `MemoryOrigin`: userExplicit / agentInferred / derivedFromThought;`MemoryState`: active / needsReview / superseded / forgotten;`MemoryConfidence`: high / medium / low(闭集,不用裸 Double)。
- Question→Thought 的 `addresses`、Thought→Memory 的 `derivedMemory` 是**关系**而非自动数据转换(brain.md §18)。

### 模块边界(brain.md §19,锁定)
- 新建 **BrainCore** Swift module(零包内依赖);**不得 import ReaderAgent**。未来由 BrainContextProvider(integration layer)把 Brain 转成 ContextCandidate。
- 持久化(GRDB)在 Persistence 模块实现 `BrainRepository` 协议(协议定义在 BrainCore),数据库表示不得污染领域模型。

### 持久化(brain.md §6,锁定 + 有据偏差)
- Phase 1 只建 `brainItems` 单表(brainItemEvidence/Relations/Embeddings/Revisions 分属 Phase 14/15/18,不提前建)。
- brainItems 列:id, kind('thought'|'question'|'memory'), title(可空), content(非空,trim 后长度>0), state, origin(仅 memory), confidence(仅 memory), contentHash(可空,Phase 15 使用), schemaVersion, createdAt, updatedAt;per-kind state CHECK 约束。
- **有据偏差 1**:brainItems 增加可空 `sourceReflectionID`(references reflections, onDelete: cascade)——仅为 memory 回填镜像现有 `memories.sourceReflectionID` 的级联语义;Thought/Question 的来源在 Phase 14 走 evidence 表,不用此列。
- **有据偏差 2**:memory 域结构体命名 `BrainMemory`(brain.md 文中为 `Memory`),避免与既有 `ReaderMemory` 及平台语义混淆;语义不变。

### 回填(锁定)
- v17 迁移内 `INSERT OR IGNORE ... SELECT` 一次性回填:claim→content;status 映射 provisional→needsReview / active→active / superseded→superseded;origin 一律 agentInferred(现有记忆全部来自 Journal Agent 提案管线,`MemoryApplicationService` 是唯一写入者);confidence 数值映射 ≥0.8→high / ≥0.5→medium / 其余→low;id 沿用记忆 id(保证据回链能力);createdAt/updatedAt 原样。
- 回填必须幂等(重复迁移不产生重复行);旧 `memories` 表、`GRDBMemoryRepository`、MyMind UI 行为**完全不变**(UI 切换属 Phase 13)。
- `wipeAllUserData` 需覆盖 brainItems(数据主权不变量 TRUST-01)。

### the agent's Discretion
- BrainEvidenceSource 在 Phase 1 以 `case reflection(String)` 等字符串载荷定义(避免 BrainCore 依赖 ReflectionCore/RetrievalCore);集成层的强类型 ID 适配留给 Phase 14/16。
- BrainProvenance 最小形态(originEvidence 可空);完整 provenance 随 Phase 14 evidence 表展开。
- 文件组织、测试命名遵循仓库既有模式(Testing 框架,ReadLoopCoreTests)。

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 规范
- `docs/brain.md` — Brain Domain 全规范(本 phase 依据 §1-6,§19-20)
- `ARCHITECTURE.md` — 现有 Agent/Context Engineering 链路(Phase 16 接入点的背景)

### 代码模式锚点
- `Sources/Persistence/AppDatabase.swift` — GRDB 迁移模式(v12_memory 为表结构样例;v17 新增 brainItems + 回填)
- `Sources/Persistence/MemoryRepositories.swift` — 仓储 + Record 映射模式(GRDBBrainRepository 照此模式)
- `Sources/ReflectionCore/Memory.swift` — ReaderMemory/MemoryRepository 现状(回填数据源,不得改动其行为)
- `Sources/Persistence/Repositories.swift` / `LocalDataWipeTests.swift` — wipeAllUserData 数据主权覆盖面

</canonical_refs>

<specifics>
## Specific Ideas

- brain.md §9 的质量规则(attach > update > create)是 Phase 17 的约束,Phase 1 不实现但域模型须能承载(state 枚举即为此设计)。
- brain.md §10 BrainItemRevision 是 Phase 18 的表;Phase 1 的 contentHash 列为其与 Phase 15 embedding 复用预留。
- 「我的大脑」首页形态(§14)与详情页(§15-17)是 Phase 13 的 UI 契约来源。

</specifics>

<deferred>
## Deferred Ideas

- brainItemEvidence / brainItemRelations → Phase 14
- brainItemEmbeddings + BrainRetriever + QueryTime embedding → Phase 15
- ContextRequest.brain 变体与 Pinned Context → Phase 16
- BrainMutationProposal / BrainProjectionService / 碎片化阈值 → Phase 17
- brainItemRevisions + 演化时间线 UI → Phase 18
- Brain 质量评估与观测 → Phase 19

</deferred>

---

*Phase: 12-brain-domain*
*Context gathered: 2026-08-29 via PRD Express Path (docs/brain.md)*

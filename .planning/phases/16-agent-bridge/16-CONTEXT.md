# Phase 16: Agent Bridge - Context

**Gathered:** 2026-08-29
**Status:** Ready for planning
**Source:** PRD Express Path(docs/brain.md §11-13,§20 Phase 5)

<domain>
## Phase Boundary

Brain 作为**新的 Context Source** 接入现有管线:BrainContextProvider 适配、Planner 请求面(brainRetrieval)、Pinned Context 数据通路、ContextAssembler 打包、ReaderAgent 接线。Brain 是新来源,不是新主 Agent。

本 phase **不含**:继续想想 的 UI 入口(涉及"Brain 页讨论以什么形态存在"的产品决策——新建 Reflection?挂在哪本书?需要用户拍板,见 Deferred);brainItemEmbeddings 的 App 装配已在 ReaderAgent init 参数位暴露,默认 nil(无配置即纯关闭)。
</domain>

<decisions>
## Implementation Decisions

### 关键架构决策:Brain 不进 [E] 引用体系(锁定,有据)
`agentResponseEvidence` 的 CHECK(`kind IN (3 值)`)与 `bookID NOT NULL` 意味着加 `.brain` 需要在事务内重建带子表 FK 的表(SQLite 不可 ALTER CHECK,事务内 PRAGMA foreign_keys 无效)——风险与收益不成比例。且语义上 **brain 条目是用户自己的想法,不是需要引用校验的外部证据**。落地:
- Brain 条目进 **prompt 专属区块**("你自己的想法档案",明确"无需引用标记"),不进 `agentResponseEvidence`,不改 `AgentEvidenceKind`,**无表迁移**。
- Memory→pastReflection 的既有映射不动(历史选择,Phase 17 复评)。

### 统一下游(brain.md §12,锁定)
- `ContextSource += .brain`(priority 3,与 pastReflection 同档——都是"用户自己的思考")与 `.pinnedBrain`(priority 6,高于 nearby——Pinned Context 必须确定性进入 bundle);Ranker defaultPriority 同步。
- `BrainContextProvider`(ContextEngineering):包装 BrainRetriever;`candidate(from: BrainCandidate) -> ContextCandidate`(metadata 携带 kind/title);`pinnedCandidate(for: BrainItem)`。
- ContextAssembler:`assemble(... brainCandidates: [ContextCandidate])`;打包后按 source 拆分——brain/pinnedBrain 进 `EvidenceAssemblyResult.brainCandidates`(不做 AssembledEvidence 映射),其余照旧走 provenance → evidence。per-source 预算:.brain 由编译期常量(brainCharacters 1200);.pinnedBrain 不限(总预算内必进)。

### Planner 请求面(锁定)
- wire schema v2.1:`brainRetrieval: null | {query}`——LLM 只决定"是否需要检索用户的想法/问题 + 查询改写",kinds 与 limit 是编译期策略。
- `ContextRequest += case brain(BrainContextRequest { query })`;normalizer/validator/compiler 全链路;validator 按 `availableSources.hasBrainItems`(AvailableContextSources 新可选字段,decode-safe)门控;空 query 丢弃。
- prompt:reader-context-router-v2 增补一行字段与语义说明(用户明确提及过去的想法/问题/之前想过什么时才请求;默认少取原则不变)。

### Pinned Context(brain.md §11A,锁定)
- `ContextRoutingInput += activeBrainContext: ActiveBrainContext?`({id,kind,title,content},decode-safe 可选);**非 LLM 决策**:ReaderAgent 参数直通 compiler → pinned 候选(与 planner 输出无关,LLM 无法删除用户显式置顶的上下文)。
- `ReaderAgent.respond/continueDiscussion` 增加可选 `activeBrain: BrainItem?` 参数(默认 nil,API 向后兼容);App 装配 Phase 17/18 随 UI 入口接。

### ReaderAgent 接线(锁定)
- init += `brainRetriever: BrainRetriever? = nil`;`availableSources.hasBrainItems = brainRetriever != nil`;plan 请求 brain 且 retriever 就绪 → 检索 → provider 映射 → assembler;pipelineMetrics += brainCandidateCount(可选字段,decode-safe)。

### the agent's Discretion
- ActiveBrainContext 的字段命名;brain 区块文案;测试用假 client 的断言方式(prompt 内容断言走 ReaderAgentPolicy.input 的消息拼接)。

</decisions>

<canonical_refs>
## Canonical References

- `docs/brain.md` §11-13 — 两种接入方式、BrainRetriever→ContextAssembler 适配、Brain 是新 Source
- `Sources/ContextRouting/`(v2 链路)— wire/normalizer/validator/compiler
- `Sources/ContextEngineering/ContextAssembler.swift` / `ContextCandidateRanker.swift` / `ContextSource.swift`
- `Sources/ContextEngineering/BrainRetriever.swift`(Phase 15)
- `Sources/ReaderAgent/ReaderAgent.swift` / `ReaderAgentPolicy.swift`(prompt 区块)
- `Sources/Persistence/AppDatabase.swift:251` — agentResponseEvidence CHECK(不重建的依据)

</canonical_refs>

<deferred>
## Deferred Ideas

- 「继续想想」UI 入口:需用户拍板讨论形态(新建 Reflection 挂哪本书 vs 独立对话)——pinned 通路已就绪,接一个按钮即可
- Memory→pastReflection 映射是否迁为 .brain 证据 → Phase 17
- query 向量 SemanticVectorCache 接入 → Phase 19
- brainRetrieval 的 kinds 细分(relatedThoughts/openQuestions)→ 出现真实需求时

</deferred>

---

*Phase: 16-agent-bridge*
*Context gathered: 2026-08-29 via PRD Express Path*

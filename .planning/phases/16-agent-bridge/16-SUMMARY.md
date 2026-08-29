# Phase 16: Agent Bridge — Summary

**Date:** 2026-08-29
**Status:** Complete — `swift test` 347/347 全绿(新增 4 个桥接测试);纯包层改动,无迁移、无 App 改动
**Spec:** `docs/brain.md` §11-13,§20 Phase 5 · Plan: `16-01-PLAN.md`

## What shipped

1. **ContextSource 扩展**:`.brain`(priority 3,与 pastReflection 同档)与 `.pinnedBrain`(priority 6,高于 nearby——置顶必进 bundle);Ranker defaultPriority 同步。
2. **`BrainContextProvider`**(ContextEngineering,integration layer):BrainCandidate → ContextCandidate 适配(metadata 携带 brainItemID/brainKind/brainTitle);`pinnedCandidate(for:)` 提供用户显式置顶。**BrainCore 零改动**。
3. **ContextAssembler**:新增 `brainCandidates` 参数;打包后按 source 拆分——brain/pinnedBrain 进 `EvidenceAssemblyResult.brainCandidates`,**不生成 AssembledEvidence**;预算策略常量:检索 brain 1200 字符、置顶在总预算内不限。
4. **Planner 请求面(wire v2.1)**:`brainRetrieval: null | {query}` 全链路——decode → normalize(.brain 请求)→ validate(`hasBrainItems` 门控,新可选字段 decode-safe)→ compile(`BrainRetrievalPolicy{query, limit=3}`);prompt 增补(仅当用户明确提及过去的想法/问题时请求)。
5. **Pinned Context 通路(brain.md §11A)**:`ReaderAgent.respond/continueDiscussion` 新增 `activeBrain: BrainItem?` 参数——**输入驱动,绕过 plan,LLM 无法否决**;直通 assembler 置顶候选。
6. **ReaderAgent 接线**:init += `brainRetriever: BrainRetriever?`(nil 即关闭,validator 自动丢弃 brain 请求);`pipelineMetrics.brainCandidateCount`(可选,decode-safe)。
7. **Policy**:brain 区块("这些是你自己的已成形想法与问题……不需要添加引用标记")在证据块之前渲染。

## Key decision(重申)

**Brain 条目不进 [E] 引用体系**:agentResponseEvidence 的 CHECK + bookID NOT NULL 需要事务内重建带子表 FK 的表(高风险),且语义上自己的想法不是可校验的外部证据。brain 内容走专属 prompt 区块,零迁移。

## Tests(4 个)

Provider 映射与置顶;assembler 置顶优先于 nearby 且 brain 与证据分离;validator 门控 + compiler 策略发射;**ReaderAgent 端到端**(scripted client:plan 请求 brain → 条目内容进 prompt;plan 不请求 + activeBrain → 置顶内容仍进 prompt——LLM 不可否决)。e2e 第二场景需用新 Reflection(同反思回复命中幂等重试路径,这是设计)。

## Deferred(需用户拍板)

「继续想想」UI 入口:Brain 页讨论以什么形态存在——新建 Reflection(挂哪本书)vs 独立对话?pinned 通路已就绪,定形态后接一个按钮即可。

## Next

Phase 17 BrainProjectionService(Observation → 候选检索 → LLM MutationProposal → Validator → 事务执行;attach > update > create)——大脑开始自动更新。

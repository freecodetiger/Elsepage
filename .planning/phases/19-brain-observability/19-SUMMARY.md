# Phase 19: Evaluation / Observability — Summary

**Date:** 2026-08-29
**Status:** Complete — `swift test` 356/356 全绿;ARCHITECTURE.md 已更新;App 层待用户最终 xcodebuild 验证
**Spec:** `docs/brain.md` §20 Phase 8 · Plan: `19-01-PLAN.md`

## What shipped

1. **`brainProjectionTraces`(v25)+ `BrainProjectionTrace`**:每次投影的 action/applied/corrections/candidateCount/decodeFailed/duration;**绝不含观察文本与反思正文**(ADR 0001,测试钉死);复用 routingTraces 单 JSON 列模式;擦除覆盖。
2. **`BrainProjectionDiagnostics`**:totalRuns / appliedCount / acceptanceRate / fragmentationRejections / actionDistribution——Brain 质量的确定性观测面;Service 接线(默认关闭,零测试影响)。
3. **继续想想按钮(形态 C)**:Thought/Question 详情页「继续想想」→ 输入 sheet → 用户文字存为新 Reflection(挂书规则:最近反思证据的书 → 最近打开的书;F9 满足)→ `readerAgent.respond(activeBrain:)` 流式回复显示在同一 sheet → 投影服务自动观察该新反思,Brain 自然吸收。对话历史沉淀在想法档案。
4. **ARCHITECTURE.md**:新增「子图 D:Personal Brain 维护路径」(fire-and-forget 全链路图 + 关键决策)与 brain* 六表清单。

## v1.1 Personal Brain 里程碑收官状态

Phases 12-19 全部完成:Domain → UI → Evidence/Relation → Embedding/Retriever → Agent Bridge → Projection → Revisions → Observability。大脑具备:强类型三对象存储、来源与关系、语义检索、自动投影更新、演化追溯、继续想想入口、质量可观测。

## 追加(2026-08-29,手测前):Memory 区正式切换

应用户要求补上记忆显示缺口:MyMind 记忆区**全量切到 brain store**(kind=.memory 条目)——投影形成的记忆即刻可见;旧 `memories` 表自本改动起退出该 UI(v21 回填已覆盖历史数据,表保留只读)。UI 同步调整:原「AI 眼中的我」(kind 分组)与「记忆」合并为 brain.md §14 形态的单一「Memories · ElsePage 记住的我」分区;行徽标改为来源性质(用户明确表达/AI 推断),新增「待确认」状态提示;置信度显示 高/中/低;用户编辑使 origin 转 userExplicit 并记录修订。
**遗留**:PersonalDataExporter 仍读旧 MemoryRepository——新记忆暂不入导出包,随旧链路清理一起切换(已记录)。

## Deferred(记录在案)

- LLM-judge 式 Brain 质量评估(需真实 Key 与样本积累;当前以验收率/碎片化率 + 手测清单替代)
- 诊断的 Settings UI;旧 Journal memory_proposals 死代码清理(投影路径 UAT 后)
- 修订 diff 视图;Question/Memory 修订

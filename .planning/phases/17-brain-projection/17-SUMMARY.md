# Phase 17: BrainProjectionService — Summary

**Date:** 2026-08-29
**Status:** Complete — `swift test` 352/352 全绿(5 个新投影测试);App 装配完成
**Spec:** `docs/brain.md` §7-9,§20 Phase 6 · Plan: `17-01-PLAN.md`

## What shipped

1. **`BrainMutationProposal`**(BrainCore,7 值 tagged union:attachEvidence/createThought/updateThought/createQuestion/updateQuestion/proposeMemory/noChange)+ `BrainMutationOutcome`。
2. **`BrainMutationValidator`**(ReaderAgent 模块):确定性门控——target 必须在候选中;内容 trim 非空且 ≤200 字(超过拒绝并要求"distill instead of appending");**create 仅当候选为空**(碎片化护栏);单提案结构性保证。
3. **`BrainProjectionService`**:观察 → BrainRetriever 候选(≤4)→ LLM(brain-projection-v1,1 call/20s/600tok,temperature 0,无修复重试——维护路径,解码失败 = noChange)→ 验证 → 执行。执行附证据:createThought .origin / updateThought .revises / createQuestion .raises / proposeMemory .origin。
4. **记忆形成复活**:proposeMemory 创建 `BrainMemory(needsReview, agentInferred, medium)`——"我的大脑"的记忆终于有了活水;用户在 MyMind 确认后转 active。
5. **ReaderAgent 触发**:回复持久化完成后 fire-and-forget `Task`,失败绝不阻塞回复;`projection: BrainProjectionService? = nil` 默认关闭(既有测试/Bench 零影响)。
6. **App 装配**:AppModel 构造 BrainRetriever(store + RAG embedding factory)+ BrainProjectionService 注入 ReaderAgent。

## 设计修正(实施中发现)

新条目不再把 provenance 写入 `sourceReflectionID` 列(硬 FK + 级联)——该列保留为 v21 回填快照专用;新条目的溯源走证据表(软悬挂,删除反思不会蒸发已形成的记忆)。测试先暴露了 FK 冲突,修正后 `backfilledMemoryKeepsSourceReflectionProvenanceAndCascades`(回填路径)依然绿。

## Tests(5)

create+origin 证据;update+revises(观察措辞必须与当前陈述共鸣才能被检索关联——护栏按设计工作);幽灵目标拒绝;proposeMemory 生命周期;noChange/垃圾 JSON 零写入。

---

# Phase 18: Revision / Evolution — Summary

**Date:** 2026-08-29
**Status:** Complete — `swift test` 354/354 全绿(2 个新修订测试);Thought 时间线 UI 完成
**Spec:** `docs/brain.md` §10,§20 Phase 7 · Plan: `18-CONTEXT.md`

## What shipped

1. **`brainItemRevisions`(v24)**:PK(item, revision,revision 由仓储按 count+1 分配);content = 被替换**前**的陈述;triggerEvidenceID = 触发反思(用户编辑为 NULL);FK CASCADE;擦除覆盖。
2. **`BrainItemRevision` + 协议 API**(`revisions(for:)` / `recordRevision`)。
3. **两个写入方**:投影 updateThought 保存前记录旧陈述(trigger=反思);MyMind 用户编辑同样记录(trigger=nil)——**用户自己的修改也可追溯**。
4. **Thought 详情「我的变化」**:时间线倒序("yyyy.MM · 旧陈述"),空态提示;当前陈述永远在上方,体量恒定。

## Tests(2)

投影 update 记录被替换陈述 + 连续两次改写编号递增([2,1] 倒序);修订往返/随条目级联/擦除覆盖。测试顺带验证了系统的自洽性:第二次改写的观察措辞必须与**新**陈述共鸣才能关联(检索护栏按设计拒绝)。

## Next

Phase 19(Evaluation / Observability):brainProjectionTraces 持久化、验收率/碎片化率、query 向量缓存评估;「继续想想」按钮(形态 C 已定,待 App 任务)。

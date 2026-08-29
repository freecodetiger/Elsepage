# Phase 18: Revision / Evolution - Context

**Gathered:** 2026-08-29
**Status:** Ready for planning
**Source:** PRD Express Path(docs/brain.md §10,§20 Phase 7)

<domain>
## Phase Boundary

Thought 的变化可追溯:`brainItemRevisions` 表 + 仓储 API + 两个写入方(投影 updateThought、用户编辑)+ Thought 详情页「我的变化」时间线。**update 永不覆盖旧总结**——旧陈述降级为修订记录。

本 phase **不含**:Question/Memory 的修订(用户编辑 Memory 已有 userEdited 标记;需求出现时扩展)、修订的 Agent 呈现(Phase 16 的 pinned 上下文只带当前陈述,保持最小)。
</domain>

<decisions>
## Implementation Decisions

### 数据模型(brain.md §10,锁定)
- `brainItemRevisions`:PK(itemID, revision);revision 从 1 递增(该条目第 N 次被改写);content = 改写**前**的陈述;triggerEvidenceID = 触发改写的反思 ID 字符串(用户编辑为 NULL);FK CASCADE 到 brainItems。
- `BrainItemRevision` 值类型与 `revisions(for:)` / `recordRevision(itemID:content:triggerEvidenceID:)` 进 BrainCore 协议(GRDB 实现);revision 号由仓储计算(count+1),调用方不传。
- 写入方:① BrainProjectionService.updateThought 保存前记录旧陈述(trigger = 反思 ID);② MyMindModel.editThought 同样记录(trigger = NULL)——**用户编辑同样可追溯**。

### UI(锁定)
- Thought 详情页新增「我的变化」:按时间倒序,每行"yyyy.MM · 旧陈述";空态提示「陈述会随讨论不断重写,旧版本留在这里。」;区块与证据区同为紧凑卡片,保持首屏不冗长。

### the agent's Discretion
- 时间线行样式细节;revision 号展示方式(隐式,仅排序)。

</decisions>

<canonical_refs>
## Canonical References

- `docs/brain.md` §10,§20 Phase 7
- `Sources/ReaderAgent/BrainProjectionService.swift`(updateThought 写入方)
- `App/MyMind/MyMindModel.swift`(editThought 写入方)
- `Sources/Persistence/AppDatabase.swift`(v22/v23 迁移与 wipe 模式)

</canonical_refs>

<deferred>
## Deferred Ideas

- 修订的 diff 视图、按月聚合流动画 → 需求出现时
- Question/Memory 修订 → 需求出现时

</deferred>

---

*Phase: 18-brain-revisions*
*Context gathered: 2026-08-29 via PRD Express Path*

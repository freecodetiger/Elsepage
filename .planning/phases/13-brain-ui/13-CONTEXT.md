# Phase 13: Brain UI — Context

**Gathered:** 2026-08-29
**Status:** Ready for planning
**Source:** PRD Express Path(docs/brain.md §14-17,§20 Phase 2)

<domain>
## Phase Boundary

「我的大脑」界面升级为 brain.md §14 的三分区结构:Thoughts(正在形成)/ Questions(还没想明白)/ Memories(ElsePage 记住的我),Thought/Question 详情页可编辑/删除,Memory 详情补 origin/confidence 展示。纯 App 层(SwiftUI),复用 Phase 12 的 `GRDBBrainRepository`。

本 phase **不含**:Evidence/来源区块与 [继续想想](Phase 14/16)、演化时间线(Phase 18)、Thought/Question 的自动形成(Phase 17)、`[继续想想]` Agent 入口(Phase 16)。
</domain>

<decisions>
## Implementation Decisions

### 数据读取策略(锁定,防止界面说谎)
- **Thoughts/Questions 读 `BrainRepository`(brainItems);Memories 继续读旧 `MemoryRepository`。** 原因:记忆的写入方仍是 Journal 管线(`MemoryApplicationService` → memories 表),BrainProjectionService(Phase 17)接管前,brainItems 里的 memory 回填是**一次性快照**——若 Memory 区改读 brainItems,迁移后新建的记忆将不可见。三分区混读保证界面永远反映真实数据源;Phase 17 统一写入后再切。
- 由此:Thoughts/Questions 对既有用户为空(此前无创建路径),空态文案明确引导("随阅读与讨论逐渐成形"),Phase 17 落地后自然填充。

### 交互(锁定)
- 首页三分区顺序:Thoughts → Questions → Memories;保留成就区与设置/清除入口。
- Thought/Question 详情:NavigationStack push;可编辑文本与阶段/状态、可删除。**不提供手动新建**(形成机制是 Phase 17 的投影;首页不是数据库管理器)。
- Memory 行为完全不变(准确/不准确/修改/忘记/查看依据);在元数据行增加来源性质展示:`userEdited → 用户明确表达`,否则 `AI 推断`;置信度按 ≥0.8 high / ≥0.5 medium / 其余 low 的同一映射显示为 高/中/低。

### 工程约定(锁定)
- App target 通过 project.yml 增加 BrainCore 依赖;`xcodegen generate` 由 Agent 执行(pbixproj 提交入库),`xcodebuild` 编译验证由用户完成(WORKTREES.md 约束:Agent 只做 swift test)。
- App 层不可被 swift test 覆盖——UI 代码贴现有模式(MemoryRow/alert/编辑弹窗),保持克制,不做新动画/新组件。

### the agent's Discretion
- 详情页布局遵循 brain.md §15/§16 的可用子集(当前的我/问题 + 状态),省略"我的变化/来自我的阅读/相关问题"区块(Phase 14/18)。
- 删除确认沿用 confirmationDialog 模式。

</decisions>

<canonical_refs>
## Canonical References

- `docs/brain.md` §14-17 — UI 形态契约(首页/三类详情)
- `App/MyMind/MyMindView.swift` / `MyMindModel.swift` — 现有记忆界面(改造基座)
- `App/AppModel.swift` — 装配点(myMind 构造)
- `project.yml` — App target 依赖声明(xcodegen)
- `.planning/phases/12-brain-domain/12-SUMMARY.md` — BrainCore/BrainRepository 现状

</canonical_refs>

<deferred>
## Deferred Ideas

- [继续想想] 与 Pinned Context → Phase 16
- Evidence/来源/相关区块 → Phase 14
- 演化时间线 → Phase 18
- Memory 区切读 brainItems → Phase 17(写入源统一后)

</deferred>

---

*Phase: 13-brain-ui*
*Context gathered: 2026-08-29 via PRD Express Path*

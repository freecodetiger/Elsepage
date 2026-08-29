# Phase 14: Evidence / Relation - Context

**Gathered:** 2026-08-29
**Status:** Ready for planning
**Source:** PRD Express Path(docs/brain.md §4-5,§20 Phase 3)

<domain>
## Phase Boundary

Brain Item 获得来源与关系:brainItemEvidence(item ↔ 外部证据)、brainItemRelations(item ↔ item)两张表 + 仓储 API + 详情页来源区块。Evidence 是事实,Brain Item 是解释(brain.md 核心原则);Evidence 给 Item 带来可解释性、时间线与后续 Agent Context 的引用能力。

本 phase **不含**:谁来写 evidence(Phase 17 的 MutationProposal.attachEvidence 是唯一生产写入方;本 phase 只交付存储 + API + UI 展示)、embedding(brainItemEmbeddings 属 Phase 15)、Relations 的 UI 区块(无生产写入方,只交付读 API)、修订历史(Phase 18)。
</domain>

<decisions>
## Implementation Decisions

### 领域模型(brain.md §4-5,锁定)
- `EvidenceRelation`(item ↔ 证据):origin / supports / contradicts / revises / raises / answers —— 六值封闭枚举。
- `BrainRelationType`(item ↔ item):related / supports / contradicts / evolvesFrom / raises / addresses / derivedMemory —— 七值克制集;**不做**万能 Knowledge Graph。
- `BrainEvidence { itemID, source: BrainEvidenceSource, relation: EvidenceRelation, weight, createdAt }`;`BrainRelation { sourceItemID, targetItemID, relation: BrainRelationType, weight, createdAt }`。
- **不设代理主键**:evidence 身份 = (item, source, relation),关系身份 = (source, target, relation) —— attach 天然幂等,重复关联不产生重复行。

### 仓储(锁定)
- 扩展 `BrainRepository`(唯一实现方是 GRDBBrainRepository,无兼容负担):`evidence(for:)` / `attachEvidence(itemID:source:relation:weight:)` / `relate(source:target:relation:weight:)` / `relations(of:)`(返回存储的规范方向——relate 写入谁 addresses 谁就是谁,查询另一端不翻转,保语义)。

### 持久化(锁定 + 有据决策)
- v22 迁移建 `brainItemEvidence`(brainItemID FK→brainItems ON DELETE CASCADE;UNIQUE(brainItemID, sourceType, sourceID, relation);CHECK relation/sourceType 枚举)与 `brainItemRelations`(双 FK CASCADE;PK=(source,target,relation);CHECK source≠target;双向索引)。
- **证据表不设 reflection 外键**:sourceType/sourceID 是泛型字符串(可指向 reflection/bookChunk/message);删除 Reflection 的级联清理在 `GRDBReflectionRepository.delete(id:)` 同事务内执行(`DELETE FROM brainItemEvidence WHERE sourceType='reflection' AND sourceID=?`),不依赖 SQLite 条件外键。brainItem 本体被删时其证据由 FK CASCADE 保障。
- **v22 不回填历史证据**:v21 回填的 memory 行继续用 sourceReflectionID 列承载 provenance(Phase 17 写入统一时迁为 evidence 行);双轨不在此 phase 合并。
- `wipeAllUserData` 表清单增加 brainItemEvidence / brainItemRelations(置于 brainItems 之前,child-before-parent)。

### UI(锁定)
- Thought 详情页新增「来自我的阅读」、Question 详情页新增「它从哪里来」:列出 evidence,reflection 来源解析为书名 + 反思原文 + (有 locator 时)「回到《书名》」跳转;bookChunk/message 来源显示类型 + 引用标识。区块为空时降级提示(「来源会随讨论逐渐积累」),对应成功标准"无 Evidence 的 Item 可信度展示降级"。
- Memory 详情不动(已有独立的"查看依据"流程,Phase 17 统一)。

### the agent's Discretion
- relations(of:) 的方向归一实现与排序;weight 语义(0...1,默认 1.0);App 层解析辅助的文件组织。

</decisions>

<canonical_refs>
## Canonical References

- `docs/brain.md` §4-5 — 证据与关系模型、克制原则
- `Sources/BrainCore/BrainItem.swift` / `BrainRepository.swift` — 既有域模型与协议(BrainEvidenceSource 已存在,字符串载荷)
- `Sources/Persistence/BrainRepositories.swift` / `AppDatabase.swift`(v21)— 仓储与迁移模式
- `Sources/Persistence/ReflectionRepositories.swift:283` — GRDBReflectionRepository.delete(级联清理挂钩点)
- `App/MyMind/MyMindView.swift` — 详情页现状(BrainThoughtDetailView / BrainQuestionDetailView)
- `Sources/Persistence/AppDatabase.swift` userDataTableOrder — 擦除清单

</canonical_refs>

<deferred>
## Deferred Ideas

- attachEvidence 的生产写入方(BrainMutationProposal)→ Phase 17
- relations UI(相关问题/相关思想)→ Phase 17 产生关系后
- brainItemEmbeddings + BrainRetriever → Phase 15
- 记忆 provenance 从 sourceReflectionID 列迁 evidence 行 → Phase 17

</deferred>

---

*Phase: 14-brain-evidence*
*Context gathered: 2026-08-29 via PRD Express Path*

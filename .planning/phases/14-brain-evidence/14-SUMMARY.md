# Phase 14: Evidence / Relation — Summary

**Date:** 2026-08-29
**Status:** Complete — `swift test` 338/338 全绿(新增 5 个行为级测试);App 文件 swiftc -parse 通过;**App 层 xcodebuild 编译验证待用户**(随 Phase 13 一起)
**Spec:** `docs/brain.md` §4-5,§20 Phase 3 · Plan: `14-01-PLAN.md`

## What shipped

1. **BrainCore 域模型**:`EvidenceRelation`(origin/supports/contradicts/revises/raises/answers,item↔证据)与 `BrainRelationType`(related/supports/contradicts/evolvesFrom/raises/addresses/derivedMemory,item↔item,克制集)两个封闭枚举;`BrainEvidence` / `BrainRelation` 值类型——**身份即 (item, source, relation) / (source, target, relation)**,attach 天然幂等,无代理主键。
2. **BrainRepository 扩展**:`evidence(for:)` / `attachEvidence`(INSERT OR IGNORE)/ `relate`(拒绝 selfRelation)/ `relations(of:)`。实现中发现并修正一处设计错误:关系**按存储的规范方向返回**(relate 写入谁 addresses 谁就是谁),不做查询端翻转——翻转会篡改语义("问题回应了想法"不能变成反向),CONTEXT 已同步修正。
3. **v22 迁移**:`brainItemEvidence`(FK CASCADE→brainItems,UNIQUE 幂等,CHECK 枚举)与 `brainItemRelations`(复合主键,双 FK CASCADE,CHECK source≠target);`wipeAllUserData` 覆盖两新表。
4. **Reflection 删除级联清理**:`GRDBReflectionRepository.delete(id:)` 在同事务内删除 sourceType='reflection' 的证据行(泛型字符串源无法用 SQLite 条件外键,清理挂在删除方);被引用的 Brain Item 本体存活,证据行随来源消失(软悬挂在读取端解析为空,与既有 evidenceContext 容错模式一致)。
5. **详情页来源区块**:Thought 详情「来自我的阅读」/ Question 详情「它从哪里来」——reflection 来源解析为反思原文 + 书名 + 「回到《书名》」跳转;bookChunk/message 来源显示类型徽标 + 关系标签;空态降级提示「来源会随讨论逐渐积累」。Memory 详情不动(Phase 17 统一)。

## Deviations from plan (recorded)

- relations(of:) 的"双向归一"表述在实现中被证伪:规范方向在写入时已定,读取端翻转会破坏 addresses/derivedMemory 的语义方向。测试钉住正确行为,CONTEXT/PLAN 表述已更正。
- 测试对 evidence 排序的断言从"位置序"降为"内容 + 确定性契约"(同毫秒 attach 在 (createdAt, sourceType, sourceID) 排序键下并列)。

## Verification

- `swift build` 干净;`swift test` 338/338(既有 333 + 新 5:evidence 幂等与确定性、关系双向与自反拒绝、Item 删除双向级联、Reflection 删除清理、wipe 覆盖)。
- PersistenceHardeningTests 迁移清单已含 `v22_brain_evidence_relations`。
- ⚠ 用户侧:App 层 xcodebuild 编译验证(Phase 13+14 累计)。

## Next

Phase 15:Persistent Embedding + BrainRetriever(lexic + embedding + RRF,kinds 过滤)→ Phase 16 Agent Bridge → Phase 17 BrainProjectionService(attachEvidence/建关系的唯一生产写入方)。

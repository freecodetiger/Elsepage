# Phase 12: Brain Domain + Persistence — Summary

**Date:** 2026-08-29
**Status:** Complete — `swift test` 全绿(333 tests / 15 suites,含 6 个新增 Brain 测试)
**Spec:** `docs/brain.md` §1-6, §19-20 Phase 1 · Plan: `12-01-PLAN.md`

## What shipped

1. **新模块 `BrainCore`**(零包内依赖,`import Foundation` only——模块边界不变量已验证,不 import ReaderAgent):
   - `BrainItem` tagged union:`thought(Thought) / question(Question) / memory(BrainMemory)`。
   - 封闭枚举:`ThoughtStage`(5 值)、`QuestionState`(5 值)、`MemoryState`(4 值)、`MemoryOrigin`(3 值)、`MemoryConfidence`(3 值)——非法状态不可表示。
   - `BrainEvidenceSource`(字符串载荷,CONTEXT 记录的 discretion)、`BrainProvenance`、`BrainItemID`。
   - `BrainRepository` 协议 + `BrainItemValidationError` 定义在 BrainCore,GRDB 实现在 Persistence——数据库不污染领域模型。
2. **持久化(GRDB `v21_brain` 迁移)**:
   - `brainItems` 单表:per-kind state/origin/confidence/title CHECK 约束(storage 层同样拒绝非法状态)。
   - `BrainItemRecord` 强类型映射(kind → 三种域对象;未知 kind/state → `stateMismatch`),`GRDBBrainRepository` 完整 CRUD,ordering (createdAt, id)。
   - `wipeAllUserData` 覆盖 `brainItems`(TRUST-01 数据主权不变量)。
3. **memories 一次性幂等回填**:`INSERT OR IGNORE ... SELECT` 确定性映射(provisional→needsReview / active→active / superseded→superseded;≥0.8→high / ≥0.5→medium / 其余→low;origin=agentInferred;id 沿用)。旧 `memories` 表、`GRDBMemoryRepository`、MyMind UI 零改动。
4. **测试(6 个新用例)**:三 kind 往返、per-kind CHECK 拒绝非法行、回填确定性 + 幂等 + 旧表不受影响、sourceReflectionID 级联与 provenance 重建、擦除联动、空内容拒绝。

## Deviations from plan (recorded)

- 迁移号:v21(计划文本误写 v17;实际迁移序列已至 v20,以源码现状为准)。
- brain.md 的 Question 只有单字段——表中 title 对 question 保持 NULL(计划中的 CHECK 已按此放宽;thought 仍要求 title NOT NULL)。
- memory 的 provenance 从回填的 `sourceReflectionID` 重建(`.reflection(...)`);thought/question 的 originEvidence 暂不持久化,evidence 表落地于 Phase 14。

## Verification

- `swift build` 干净;`swift test` 333/333 全绿。
- 既有 327 个测试无行为变化(PersistenceHardeningTests 迁移清单断言已按 v21 更新)。

## Next

Phase 13(Brain UI)→ 14(Evidence/Relation)‖ 15(Embedding + BrainRetriever)→ 16(Agent Bridge)→ 17(BrainProjectionService)→ 18(Revisions)→ 19(Eval)。

# Phase 13: Brain UI — Summary

**Date:** 2026-08-29
**Status:** Complete(App 层)— 包层 `swift test` 333/333 全绿;`xcodegen generate` 通过;App 文件 swiftc -parse 语法检查通过;**`xcodebuild` 编译验证待用户执行**(WORKTREES.md 约束)
**Spec:** `docs/brain.md` §14-17,§20 Phase 2 · Plan: `13-01-PLAN.md`

## What shipped

1. **首页三分区(brain.md §14)**:「我的大脑」现有记忆界面之上新增 Thoughts · 正在形成 与 Questions · 还没想明白 两个分区;两者读 `BrainRepository`(brainItems),按更新时间倒序;空态文案明确"随阅读与讨论逐渐成形"(无手动新建入口——形成机制是 Phase 17)。
2. **详情页**:Thought 详情(当前的我/阶段/更新时间)与 Question 详情(问题/状态),支持编辑与删除(确认对话框);编辑用轻量 Form sheet(文本 + 阶段/状态 Picker),复用既有 Haptics/主题/A11Y combine 模式。brain.md §15/§16 的"我的变化/来自我的阅读/相关问题"区块按计划留给 Phase 14/18。
3. **Memory 信任展示(brain.md §17 子集)**:元数据行新增来源性质(userEdited → 用户明确表达,否则 AI 推断)与 高/中/低 置信度(沿用回填同款映射 ≥0.8/≥0.5);准确/不准确/修改/忘记/查看依据 行为完全不变。
4. **装配**:AppModel 构造 `GRDBBrainRepository` 注入 MyMindModel;project.yml App target 与 ReadLoopCoreTests target 增加 BrainCore 依赖,pbxproj 已由 xcodegen 重新生成。

## Key decision(记录在 CONTEXT)

**记忆区继续读旧 `memories` 表**:写入方仍是 Journal 管线,BrainProjectionService(Phase 17)接管前 brainItems 的 memory 是一次性回填快照——混读保证界面永远反映真实数据源;Phase 17 统一写入后切。

## Verification

- `xcodegen generate` 成功,BrainCore 已进入 App 与测试 target(10 处引用)。
- `swift test` 333/333 全绿(包层零行为变化)。
- App/MyMind/*.swift + AppModel.swift `swiftc -parse` 无语法错误。
- ⚠ 用户侧待办:unsigned `xcodebuild` 编译验证(swift test 不编译 App target)。

## Next

Phase 14(Evidence/Relation)‖ Phase 15(Persistent Embedding + BrainRetriever)可并行;Phase 16 Agent Bridge → Phase 17 BrainProjectionService(记忆与 Thought/Question 的自动形成,届时统一写入源)。

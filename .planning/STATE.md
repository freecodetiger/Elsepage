# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-29)

**Core value:** 用户在读完书后愿意持续输出高质量 Reflection,并随时间累积成可回溯的个人思想档案
**Current focus:** v0.5 TestFlight 就绪 — Phase 1 信任基线

## Current Position

Phase: 6 of 11 (习惯打磨与偏差批量修)
Plan: Phase 6 执行中 (v0.5 最后一个 phase)
Status: In progress
Last activity: 2026-08-29 — Phase 5 (Bench) 合并; 全量基线 10/10 跑通 (docs/bench/runs/2026-08-29-baseline); main 264 tests 全绿

Progress: [█████░░░░░] 50% (10/22 plans)

Milestone: v0.5 TestFlight 就绪 (Phases 1-6)
Next milestone: v1.0 App Store 首发 (Phases 7-11)

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: -
- Total execution time: -

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Init]: 首发两阶段 v0.5 → v1.0;软缺口纳入 Library/Today、Journal 用户编辑、小偏差批量修
- [Init]: 不做真流式,移除假开关;PRD 偏差写回 v0.3
- [Init]: Agent 只做开发+swift test;构建/真机/上架由用户手动;Bench 含 LLM 评审
- [Init]: 并发模型=每 phase 一个 worktree(gsd/phase-{N}-{slug}),main 为唯一集成区

### Pending Todos

None yet.

### Blockers/Concerns

None yet.

Phase: 11 of 11 (首发验收) — 代码侧完成
Plan: UAT 清单已交付 (docs/release/UAT-CHECKLIST.md); 剩余全部为用户真机验收项
Status: Awaiting user acceptance
Last activity: 2026-08-29 — Phase 9/10/11 代码侧完成; 评审基线 20.10/22; 317 ST + 26 XCT 全绿; 修复 Haptics.swift 工程遗漏并加防回归测试

Progress: [█████████▓] 95% (21/22 plans)

v0.5 用户待办 (真机): xcodebuild 构建并上 TestFlight → 验收清单见 .planning/UAT-v0.5.md (待补)

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Feature | 真流式输出(SSE) | Out of Scope(首发) | Init |
| Feature | 模型列表拉取 | Out of Scope | Init |
| Feature | Today 历史回顾一句(P1) | v2 | Init |

## Session Continuity

Last session: 2026-08-29
Stopped at: v1.1 Personal Brain — Phase 12-19 全部完成,v1.1 代码收官(356 tests 全绿);待用户 xcodebuild + 真机验收(投影自动更新/继续想想/MyMind);v1.0 Phase 11 同样待用户验收
Resume file: .planning/phases/19-brain-observability/19-SUMMARY.md

### v1.1 Brain 里程碑进度

- [x] Phase 12: Brain Domain + Persistence(BrainCore 模块 / brainItems v21 迁移 / memories 回填 / 6 测试)
- [x] Phase 13: Brain UI(三分区 + 详情/编辑 + Memory 来源性质;App xcodebuild 编译验证待用户)
- [x] Phase 14: Evidence / Relation(brainItemEvidence/Relations + Reflection 删除清理 + 详情页来源区块)
- [ ] Phase 15: Persistent Embedding + BrainRetriever(下一步)
- [ ] Phase 16: Agent Bridge(BrainContextProvider → ContextCandidate → ContextAssembler)
- [ ] Phase 17: BrainProjectionService(LLM 提议,代码执行;attach > update > create)
- [ ] Phase 18: Revision / Evolution(brainItemRevisions 演化时间线)
- [ ] Phase 19: Evaluation / Observability

## Quick Tasks Completed

- 2026-09-12：DEBUG 测试闭环 v1（.planning/quick/debug-loop/SUMMARY.md），包测试与执行器测试通过；App/USB 真机验收待用户，见 docs/DEBUG-LOOP.md。
- 2026-09-12：Phase 1 A 文本测量/富文本缓存代码落地（.planning/quick/phase1-text-cache/SUMMARY.md）；包测试通过，App target 与真机命中率对照待验收。
- 2026-09-12：Phase 2 B 流式输出去抖合并代码落地（.planning/quick/260912-gut-b-reflectionconversationmodel-textdelta-/SUMMARY.md）；包测试通过，App target 与真机刷新次数/视觉等价待用户安装验收。
- 2026-09-12：Phase 3 C 阅读器打开管线代码落地并完成真机性能采样（.planning/quick/260912-i4j-c-reader-resume-position-preferences-pub/SUMMARY.md）；复开缓存命中，性能证据见 docs/testing/interaction-perf/2026-09-12-reader-reopen.json，视觉语义待确认。
- 2026-09-12：Phase 5 E-P2 冷启动数据库迁移移出主 actor（.planning/quick/260912-je1-e-p2-appdatabase-appmodel-start-local-fi/SUMMARY.md）；AppDatabase.openOffMain 与 AppModel 启动接缝已落地，353 个包测试全绿，真机启动体感待验收。
- 2026-09-13：客户端交互性能闭环真机验收通过（`.planning/quick/260913-interaction-perf-acceptance/SUMMARY.md`）；A/C/D/E-P2 通过，B 因当前 Provider 非流式延至 v2 SSE；证据见 `docs/testing/interaction-perf/2026-09-13-interaction-acceptance.json`。
- 2026-09-13：Voice Reflection 交付水准代码完成（`.planning/quick/260913-voice-delivery/SUMMARY.md`）；365 tests 全绿，真机权限/录音/播放/删除/强杀验收待用户，清单见 `docs/testing/voice/2026-09-13-delivery-checklist.md`。
- 2026-09-13：Anti-Spoiler CARC 实现完成（`.planning/quick/260913-anti-spoiler-carc/SUMMARY.md`）；373 tests 全绿，Spec 见 `docs/ANTI_SPOILER_SPEC.md`。
- 2026-09-13：Reader Help 临时选句答疑 Spec 完成（`.planning/quick/260913-reader-help-spec/SUMMARY.md`）；文档见 `docs/READER_HELP_SPEC.md`。
- 2026-09-13：Reader Help 临时选句答疑代码完成（`.planning/quick/260913-reader-help-delivery/SUMMARY.md`）；382 tests 全绿，真机验收见 `docs/testing/reader-help/2026-09-13-delivery-checklist.md`。
- 2026-09-13：Reader Help 关闭语义与回答边界修正完成（`.planning/quick/260913-reader-help-dismissal-and-grounding/SUMMARY.md`）；下滑不丢失、X 完全丢弃、Prompt v2 允许现实背景回答，未引入 WebSearch。
- 2026-09-13：Reader Help Citation 返回体验修复完成（`.planning/quick/260913-reader-help-citation-return/SUMMARY.md`）；原文来源标签替代 E1，跳转时保留回答与 thread。
- 2026-09-13：Agent Markdown v3 渲染完成（`.planning/quick/260913-agent-markdown-v3/SUMMARY.md`）；标题/列表/引用/代码块可渲染，Reader Help Prompt v3 支持更长结构化回答。
- 2026-09-13：选区工具栏“聊聊”删除完成（`.planning/quick/260913-remove-reader-reflect-action/SUMMARY.md`）；保留笔记、问和复制入口。
- 2026-09-13：Reader Help 保存笔记反馈完成（`.planning/quick/260913-reader-help-note-feedback/SUMMARY.md`、`.planning/quick/260913-reader-help-note-decoration/SUMMARY.md`）；保存后正文显示 note underline，并可点击打开。

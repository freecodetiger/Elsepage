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
- 2026-09-13：Note 重叠命中与预览/编辑双态完成（`.planning/quick/260913-note-overlap-and-preview/SUMMARY.md`）；重叠时提供“笔记 / 高亮”选择器，Note editor 默认 Markdown 预览。
- 2026-09-13：Note / Highlight 冲突选择器完成（`.planning/quick/260913-annotation-conflict-picker/SUMMARY.md`）；仅真实重叠时二次选择笔记或高亮。
- 2026-09-13：Annotation Model Refactor Spec 完成（`.planning/quick/260913-annotation-model-spec/SUMMARY.md`）；Range 成为唯一身份，Highlight/Note 完全解耦，Note 允许交叉并追加数组，旧交叉高亮保留较新者。
- 2026-09-13：Annotation Model Refactor 落地完成（`.planning/quick/260913-annotation-model-refactor/SUMMARY.md`）；v28 迁移、TextAnnotation 聚合、NoteEntry 数组和冲突 selector 已实现，387 tests 全绿。
- 2026-09-13：Readium Selection Range Bridge 完成（`.planning/quick/260913-readium-range-bridge/SUMMARY.md`）；通过 evaluateJavaScript 获取真实 start/end，388 tests 全绿。
- 2026-09-13：Annotation 点击坐标冲突消歧完成（`.planning/quick/260913-annotation-overlap-hit-fix/SUMMARY.md`）；按 decoration clickableElements 的 hit rect 判定，且菜单锚定实际点击点，只有点击点同时命中 Note 和 Highlight 才显示选择器。
- 2026-09-13：UI 语言与信息架构重构完成（`.planning/quick/260913-ui-language-and-ia/SUMMARY.md`）；锁定“页外 / 今天 / 书架 / 想法 / 我的”和阅读记录/看法/问题/记忆语义，应用壳层改为中性黑白 token，拆分交互色与状态色，重构想法/我的页层级；Spec 见 `docs/UI_LANGUAGE_AND_IA_SPEC.md`，swift test 全绿（388 Swift Testing + XCTest 0 failures），Xcode/真机视觉验收待用户。
- 2026-09-14：想法页减法 HTML 原型完成（`.planning/quick/260914-thoughts-html-prototype/SUMMARY.md`）；交付 `docs/prototypes/thoughts-redesign.html`，删除档案入口，覆盖固定概要、扫读/展开、明暗预览与中文日期；已完成 Chrome 实渲染，待用户审阅视觉方向。
- 2026-09-14：想法页 UI 重构 Spec 完成（`.planning/quick/260914-thoughts-ui-redesign-spec/SUMMARY.md`）；新增 `docs/THOUGHTS_UI_REDESIGN_SPEC.md`，锁定删除档案入口/状态/筛选、自动 AI 回应、首次两输入生成不可变概要、玻璃仅用于导航浮层、卡片只留书名中文日期与概要；旧 UI 规范已同步指向新 spec。
- 2026-09-14：想法页 UI 重构代码落地（`.planning/quick/260914-thoughts-ui-implementation/SUMMARY.md`）；新增 v29 不可变概要、自动首次回应与后台补齐，删除档案入口/筛选/状态/手动回应，卡片收敛为书名+中文日期+概要，点击进入独立记录世界，详情隐藏系统标题栏并保留左上角玻璃悬浮返回，含概要、用户/AI inline 头像署名正文、每条回应的轻量依据脚注、这次留下和对话输入；391 包测试全绿，Xcode 真机验收待用户。
- 2026-09-14：对话身份设置完成（`.planning/quick/260914-conversation-identity-settings/SUMMARY.md`）；设置新增用户名/AI名称、头像符号选择、实时预览和恢复默认，偏好通过 AppStorage 即时作用于对话消息；391 包测试全绿。
- 2026-09-14：删除 Today 独立 Tab（`.planning/quick/260914-remove-today-tab/SUMMARY.md`）；主导航改为书架/想法/我的，默认进入书架；补写 Reflection 降为书架顶部 Next Action，连续阅读/连续思考迁入我的；391 包测试全绿。
- 2026-09-14：书架第一轮重构落地（`.planning/quick/260914-bookshelf-first-pass/SUMMARY.md`）；当前阅读桌面、彩色书脊书架、书脊/封面切换、按压缩放与抽出动画已实现；Today 已从主导航移除，补写动作附着当前书，Streak 迁入我的；391 包测试全绿。
- 2026-09-14：书架桌面视觉与比例修正完成（`.planning/quick/260914-wgk-bookshelf-desk-polish/SUMMARY.md`）；当前书不再在桌面和书架重复出现，封面与书脊统一为同一对象高度，圆角卡片改为浅桌面承托，补写入口收成封面便签；391 包测试全绿，Xcode 真机视觉验收待用户。
- 2026-09-14：书架桌面动作层级修正完成（`.planning/quick/260914-wjk-bookshelf-action-parity/SUMMARY.md`）；移除封面补写便签，将“补写想法”与“继续阅读”改为同级同样式操作，并在窄宽度下自动纵向排列；391 包测试全绿，Xcode 真机视觉验收待用户。
- 2026-09-14：书架打开阅读器连续过渡完成（`.planning/quick/260914-wlx-zoom-transition/SUMMARY.md`）；当前封面/书脊/封面模式接入 iOS 18 原生 zoom transition，移除书脊 140ms 固定等待，Reader 准备态改为封面占位并交叉淡入正文，Reduce Motion 回退保留；391 包测试全绿，Xcode 真机转场验收待用户。
- 2026-09-14：书架阅读桌面固定排布完成（`.planning/quick/260914-wpb-fixed-reading-desk/SUMMARY.md`）；书籍舞台、标题/作者/进度槽位和动作位置不再随书名长度变化，普通字号动作等宽，设备宽度与 Accessibility 字号才触发确定性回退；391 包测试全绿，Xcode 真机视觉验收待用户。
- 2026-09-14：书架封面抽象书签删除完成（`.planning/quick/260914-wqp-remove-cover-bookmark/SUMMARY.md`）；移除封面右侧仅露出一点的进度 Capsule，进度只保留信息区进度条与百分比，并清理 Spec 中旧便签/书签语义；391 包测试全绿，Xcode 真机视觉验收待用户。
- 2026-09-14：书架现代拟物重构完成（`.planning/quick/260914-wt4-prd-spec/SUMMARY.md`）；PRD/Spec 改为允许低对比现代家具感材质，阅读区使用铺满宽度的程序化胡桃木桌面，书封增加页芯与接触阴影，书脊模式改为每排共享木质承托板并支持 6–1 列宽度回退；391 包测试全绿，Xcode 真机材质与对比度验收待用户。
- 2026-09-14：书架木质拟物撤回完成（`.planning/quick/260914-wxe-revert-wood/SUMMARY.md`）；恢复低噪中性书架，删除木质桌面/承托板和书本页芯、底板与额外投影，桌面书本外框与封面统一为 100×150pt，保留固定几何、同级操作与 zoom transition；391 包测试全绿，Xcode 真机视觉验收待用户。
- 2026-09-14：Reader 返回书架封面闪烁修复完成（`.planning/quick/260914-x0a-reader/SUMMARY.md`）；根因是封面外部阴影不属于 matched transition source frame，源视图与 Reader 占位改为共享 100×150pt 无阴影几何并显式裁切 zoom snapshot；391 包测试全绿，Xcode 真机返回动画验收待用户。
- 2026-09-14：书架 zoom transition 阴影一致性修复完成（`.planning/quick/260914-x2m-zoom-transition/SUMMARY.md`）；恢复封面层次，将封面尺寸、圆角与阴影参数集中管理，并同步写入当前封面/书脊/封面模式的 matched transition configuration；391 包测试全绿，Xcode 真机开合动画验收待用户。
- 2026-09-14：想法页编辑式 HTML 原型完成（`.planning/quick/260914-x71-html/SUMMARY.md`）；新增 `docs/prototypes/thoughts-editorial.html`，去掉重复卡片/数量/箭头，改为月份分组与细分隔线的编辑式记录流，搜索默认收起，支持时间/书籍分组和明暗预览；HTML/JS 静态检查通过，最终视觉审阅待用户。
- 2026-09-14：想法页搜索入口调整完成（`.planning/quick/260914-xa0-ui/SUMMARY.md`）；移除标题下方常驻搜索框，改用右上角系统工具栏搜索按钮，点击后展开，其他卡片/分组/详情保持不变；391 包测试全绿，Xcode 真机位置验收待用户。
- 2026-09-14：想法页显式搜索按钮完成（`.planning/quick/260914-xbg-thoughts-search-button/SUMMARY.md`）；右上角固定加入 magnifyingglass 按钮，与更多菜单并列，点击后展开 searchable 抽屉，卡片/分组/详情不变；391 包测试全绿，Xcode 真机按钮位置验收待用户。

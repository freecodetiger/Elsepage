# Elsepage Client Interaction Performance — Active Execution Plan

Status: **active**（阶段 0 未开工；阶段 1–5 pending）
Source of truth: `docs/INTERACTION_PERFORMANCE_SPEC.md`（规格与验收）、`docs/adr/0002-client-interaction-performance.md`（定案）
定案（2026-09-05）：A=最小面（会话+档案正文）；B=去抖合并（纯增量二期）；基线=真机可采。

## 阶段跟踪

| # | 工作包 | 内容 | 状态 | 验收出口（详见 spec 对应节） |
|---|--------|------|------|-------------------------------|
| 0 | F 起点 | `PerfSignposts` + Diagnostics 打点；采三卡点 + 流式基线 | **未开工（下一个）** | spec §8.1 指标表 + §8.3 |
| 1 | A | TextMeasureCache + RichTextBuilder；替换会话/档案正文为 `MessageText` | pending | §3.6 |
| 2 | B | 流式去抖合并（保 withoutCitationBlock / 完成切换 / 滚动锚点） | pending | §4.3 |
| 3 | C | 阅读器管线重排 + Publication 缓存/预取（离主实验门控 R1） | pending | §5.5 |
| 4 | D | 键盘 frame 驱动滚动、去整树动画；两处 autofocus sheet 节奏 | pending | §6.3 |
| 5 | E-P2 | 冷启动 DB 迁移离主（以阶段 0 基线决定是否本轮做） | pending | §7.4 |
| 二期 | C-离主 / B-增量流 | 门控于 R1 与基线；默认不做 | — | spec §5.4 / §4.2 |

## Phase 0（下一个要开工的阶段）

目标：先有"能复现卡顿"的曲线，再谈优化；回滚=移除打点（不改变行为，建议永久保留）。

改动面（预估，均在 App 层，无 UI target 依赖）：
- 新增 `App/Performance/PerfSignposts.swift`：`OSSignposter` 门面（subsystem `com.readloop.app` / category `perf`），为 readerOpen、keyboardAppear、streamDelta、textMeasure、aliveTextView 提供 begin/end 打点与"缓存缺失才计"的 textMeasure 守卫。
- `DiagnosticsModel`（`App/Settings/DiagnosticsModel.swift`）之上新增近期 signpost 摘要聚合（次数/均值/p95/最大主线程连续阻塞），接到 `SettingsView` Diagnostics 区（`App/Settings/SettingsView.swift:281` 现有展示位）。
- 在当前代码里插好**未改行为**的埋点（reader 打开两端、两处 autofocus、流式 consume 入口、FitTextView 测量点）——不进入 A–D 的任何行为改动。

验收（阶段 0 出口，供阶段 1 作为对照）：
- 真机（见定案）上，三卡点 + 流式各有一条可复现的 signpost 曲线。
- Diagnostics 屏能显示近期打点摘要。
- 确定 R3（主执行器 CPU 量级）与 R4（系统键盘冷启动份额）的量级，回填 spec §10 与 §5.1 的 ⚠️ 项，据此校订 A–D 的预算分配。

风险/回滚：仅新增打点，无行为变更，低风险；回滚 = 移除新文件与 Diagnostics 扩展。

## 备注
- 交互/标注 UI 语义受 `docs/READER_EXPERIENCE_OPTIMIZATION_PLAN.md` 约束，阶段 1–4 不得改动其规格。
- 死路径 `BrainDiscussionSheet`（`App/MyMind/MyMindView.swift:1069`）勿迁移勿重复投入。

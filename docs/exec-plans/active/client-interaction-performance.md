# Elsepage Client Interaction Performance — Active Execution Plan

Status: **active**（阶段 0 采样完成；A/C/D/E-P2 真机通过；B 在非流式 Provider 下无可见收益；仅 R3 定量 CPU 归因仍为残余项）
Source of truth: `docs/INTERACTION_PERFORMANCE_SPEC.md`（规格与验收）、`docs/adr/0002-client-interaction-performance.md`（定案）
定案（2026-09-05）：A=最小面（会话+档案正文）；B=去抖合并（纯增量二期）；基线=真机可采。

## 阶段跟踪

| # | 工作包 | 内容 | 状态 | 验收出口（详见 spec 对应节） |
|---|--------|------|------|-------------------------------|
| 0 | F 起点 | `PerfSignposts` + Diagnostics 打点；采三卡点 + 流式基线 | 部分完成：真机与 USB 采样已通；R3 定量 CPU 归因未闭合，不再阻塞本轮验收 | spec §8.1 指标表 + §8.3 |
| 1 | A | TextMeasureCache + RichTextBuilder；替换会话/档案正文为 `MessageText` | 真机通过：缓存命中、键盘/选区不重测、视觉与选区正常 | §3.6 |
| 2 | B | 流式去抖合并（保 withoutCitationBlock / 完成切换 / 滚动锚点） | 代码已落地；当前 Provider 非流式，无可见收益，真实验收延至 v2 SSE | §4.3 |
| 3 | C | 阅读器管线重排 + Publication 缓存/预取（离主实验门控 R1） | 真机通过：复开缓存命中且性能改善；恢复位置/偏好/标注正常 | §5.5 |
| 4 | D | 键盘 frame 驱动滚动、去整树动画；两处 autofocus sheet 节奏 | 真机通过：回落回归已修复；composer 与两处自动聚焦 sheet 无异常 | §6.3 |
| 5 | E-P2 | 冷启动 DB 迁移离主（以阶段 0 基线决定是否本轮做） | 真机通过：普通冷启动无白屏/冻结，进入主界面可交互 | §7.4 |
| 二期 | C-离主 / B-增量流 | 门控于 R1 与基线；默认不做 | — | spec §5.4 / §4.2 |

## Phase 0（已完成采样，部分证据待闭合）

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

## Phase 5 E-P2（验证）

`AppDatabase.openOffMain(path:)` 在 detached executor 中执行同步 GRDB migrator；`AppModel.start()` 只在后台数据库准备完成后回主 actor 组装对象图，原有 `startupError` 错误出口和 local-first 顺序保持不变。`ReaderFoundationTests.backgroundOpenMigratesFileBackedDatabase` 验证 file-backed 数据库已迁移到 v26 且可读写。

包级验证已完成：`swift test` 353 tests 全绿，`git diff --check` 通过。2026-09-13 真机普通冷启动（非重装）无白屏或长时间冻结，进入主界面可交互；本轮未新增 `launchInteractive` 数值指标。

## Phase 1 A（验证）

代码已落地在 `App/DesignSystem/SelectableText.swift` 与 `AgentMarkdownText.swift`：`MessageText` 统一会话/档案正文门面；`RichTextBuilder` 分离并缓存 Markdown 结构解析与样式落字；`TextMeasureCache` 按富文本指纹和 8pt 宽度桶做主 actor LRU（200 项），`FitTextView` 保留选区实现并只在缓存缺失时执行 `boundingRect`。旧包装保留为薄壳以降低迁移风险。

2026-09-13 真机验收通过：键盘 safe-area 与长按选区过程中 `textMeasure.cache.miss` 保持 22 不变，没有发生整串重测；Agent 完整消息出现时记录 `hits=2`，确认缓存命中路径可执行。文本高度、正文视觉、跨行选区与手柄拖动均无回归。缓存指纹开销未成为热点，本阶段不再扩大范围。

## Phase 2 B（验证）

代码已落地在 `Sources/ReflectionCore/StreamingResponseBuffer.swift` 与 `App/Reflection/SessionReflectionSheet.swift`：模型 delta 先追加到全文缓冲，约 50ms 合并一次可见刷新；`withoutCitationBlock` 仅在刷新时对累计全文执行。收到 `.completed` 时先冲刷再清空，取消/失败/流意外结束时冲刷挂起内容并保留已有局部回应。`streamDelta` 诊断项现在代表一次可见批次刷新，便于比较去抖前后的刷新次数。

本阶段尚未宣称真机收益：包级 `StreamingResponseBuffer` 回归测试已覆盖合并、citation 过滤和完成清理。2026-09-13 真机实测确认当前 Provider 按 PRD §21.3 固定非流式，只产生一个完整 `.textDelta`，因此 `streamDelta n=1` 且界面一次性出现全文；这是当前产品架构的预期行为，不是去抖回归。该包保留为 v2 SSE 路径的未来防线，真实收益验收随真流式一起延期。

## Phase 4 D（验证）

2026-09-13 真机验收发现键盘升起后会话会“回落一下”。事件序列稳定为 `keyboardWillShow` → 约 400ms → `keyboardDidShow` → 约 1ms → 自定义 `scrollToBottom`；移除晚于系统动画结束的强制滚动后，复测四次未再出现回落，composer 始终保持可见。

普通冷启动首次键盘：触摸→编辑 130.6ms、`becomeFirstResponder` 49.9ms、主队列最大 28.4ms；重复键盘约 93.8–102.9ms / 26.5–27.9ms。约 0.5s 的总观感主要由系统声明的 383.3ms 键盘动画构成，App 侧无 ≥50ms 连续阻塞。两处自动聚焦 sheet 经用户手测无异常，Phase D 本轮验收完成。

## Phase 3 C（验证）

代码已落地在 `App/Reader/ReaderModel.swift`、`App/Reader/ReadiumServices.swift` 与 `App/Library/LibraryModel.swift`：Reader 首帧门闩只等待 position/preferences；highlights、notes 和 `markOpened` 移出首帧门闩，在首帧准备后异步处理。ReadiumServices 增加按本地文件路径、大小、修改时间和交互权限区分的 4 项 LRU Publication 缓存与可合并预热任务，删除书籍时主动失效；缓存命中/写入/预热进入诊断事件时间线。

本阶段性能与视觉验收已通过：2026-09-13 真机冷开 `readerOpen=766.4ms`，同进程复开 `470.4ms` 且出现 `reader.publicationCache.hit`；`readerParse` 7.15ms→1.12ms，`readerToFirstPage` 693.3ms→422.9ms。用户确认恢复位置、字号/主题、高亮和笔记均正常。较早的同场景证据见 `docs/testing/interaction-perf/2026-09-12-reader-reopen.json`，本轮汇总见 `docs/testing/interaction-perf/2026-09-13-interaction-acceptance.json`。Publication 缓存复用的集成回归用例已加入 `ReadiumPublicationIntegrationTests`。

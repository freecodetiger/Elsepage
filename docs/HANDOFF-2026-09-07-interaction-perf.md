# 交接文档：客户端交互性能（文本可选特性 + Phase-0 埋点）

> 交接日：2026-09-07 · 交接人：freecodetiger（Claude Code 会话）
> 状态：本会话工作已提交；**Phase-0 真机基线尚未采集**（下一步）。

## 1. 一句话交代

工作树里此前有一份**半成品的"文本可选择"特性**（让会话/档案/日志/MyMind 正文用原生 UITextView 做跨行选区），本会话在其之上完成了**Phase-0 交互性能埋点**，并产出了**六工作包 spec + ADR + 执行计划**。两者在同一份代码里交织提交，尚未拆历史。

## 2. 提交记录（main，两笔）

| Hash | 消息 | 内容 |
|---|---|---|
| `1ede809` | feat(text): selectable message/entry text + Phase-0 interaction perf instrumentation | 14 文件 +560/−23：SelectableText 组件、Thoughts/Journal/MyMind 接线、Perf 埋点、Reader 计时、Diagnostics 扩展、pbxproj |
| `e7fb5dc` | docs: 客户端交互性能与渲染架构 spec + ADR-0002 + active 执行计划 | spec(约 350 行) + ADR-0002 + exec-plan |

提交后 `git status` 仅剩两个**有意未入库**目录：`research/`（实验草稿）、`ReadLoop.xcodeproj/project.xcworkspace/xcshareddata/`（xcodegen 生成物）。是否需要入库由你决定。

## 3. 关键产物（新开发阶段从这读起）

- `docs/INTERACTION_PERFORMANCE_SPEC.md` — **主 spec**：三卡点根因、目标/非目标/原则、工作包 A–F 每节现状→规格→迁移清单→验收、落地顺序、风险 R1–R6、证据索引。
- `docs/adr/0002-client-interaction-performance.md` — 定案（A 最小面 / B 去抖 / 真机采基线 / 非目标）。
- `docs/exec-plans/active/client-interaction-performance.md` — 阶段 0–5 状态表；**Phase 0 定义即下一步**。

## 4. 本会话完成的代码改动（Phase 0 埋点，行为不变）

新增：
- `App/Performance/Perf.swift` — @MainActor 单例：os_signpost（`com.readloop.app` / `perf`）+ 采样桶 + `timed/begin/end/abort`。disabled（非 DEBUG / 未 enable）时单分支 no-op。
- `App/Performance/PerfDiagnosticsView.swift` — 采样摘要节。

埋点位置（都只计时、不改行为）：
- `App/Reader/ReadiumReaderView.swift` — `readerParse` / `readerToFirstPage` / 首个 `locationDidChange` 记 `readerOpen`（锚点在 `ReaderModel.perfOpenBeganAt`，由 `ReaderScreen.task` 写入）。
- `App/Reflection/SessionReflectionSheet.swift` — 流式 `.textDelta` 模型侧合并计时（`streamDelta`）。
- `App/DesignSystem/AgentMarkdownText.swift` — 单次 body 渲染计时（`markdownRender`）。
- `App/DesignSystem/SelectableText.swift` — `FitTextView` 单次全量测量计时（`textMeasure`）+ make/dismantle 存活计数（`alive`）。
- 键盘：全局通知 `textDidBeginEditing` → `keyboardDidShow` 计时（`keyboardAppear`）。

启用/入口：
- `App/AppModel.swift` `start()` 顶部 `#if DEBUG Perf.shared.enable()`。
- 展示：真机 DEBUG → **设置 → 路由诊断** 顶部「交互性能（本次运行）」。

## 5. 下一步（Phase 0 收尾，须真机）

1. DEBUG 装真机，做三件事各一次：开一本大书、在会话唤起输入法、会话里长按拖选区 + 看完一条流式 Agent 回复。
2. 读诊断屏数字；或用 `log stream --predicate 'subsystem == "com.readloop.app"'` 复看同一批 os_signpost。
3. 用结果闭合 spec §10 的 **R3**（`readium.open` 主执行器 CPU 量级，源码推断待实测）与 **R4**（键盘系统冷启动份额）。
4. 据实校订 A–D 的预算分配，再进 **Phase 1 = 工作包 A（TextMeasureCache）**。

## 6. 交接给后续会话时的注意

- **提交身份**：一切提交署名 `freecodetiger`；**不要**在提交信息加 `Co-Authored-By: Claude` 等尾注。Conventional Commits 前缀。推送走本地代理（`git config http.proxy http://127.0.0.1:7890`）——本会话未推送。
- **构建**：新增/删除 App 文件后先 `xcodegen generate` 再编译；unsigned 模拟器门禁：
  `xcodebuild -project ReadLoop.xcodeproj -scheme ReadLoop -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
- `swift test` 会改写 `Package.resolved`（丢 Readium pins），跑完 `git checkout -- Package.resolved`。本会话未跑 swift test（只动了 App 层）。
- `xcodegen generate` 会重写 `ReadLoop.xcodeproj`（pbxproj/scheme 是派生物，以 `project.yml` 为准）。
- 隐藏约定：`docs/ARCHITECTURE.md` 是漂移快照、非权威；交互/标注 UI 语义受 `docs/READER_EXPERIENCE_OPTIMIZATION_PLAN.md` 约束，工作包 1–4 不得改其规格。
- 死路径别误伤：`BrainDiscussionSheet`（`App/MyMind/MyMindView.swift:1069`）当前无展示点，勿迁移勿重复投入。

## 7. 证据锚点速查

- GRDB 已离主：`Sources/Persistence/*` 全部 `await db.writer.read/write`；例外=冷启动迁移同步（`AppDatabase.init`）。
- Agent 流式产出端在后台：`Sources/ReaderAgent/ReaderAgent.swift` / `AgentExecutor.swift`；消费端主 actor 每 delta 整串重解析 = O(n²) 病根之一。
- Readium 无公开"首帧就绪"回调；最可靠信号 = 首次 `locationDidChange`。
- `Publication` 零缓存（`App/Reader/ReadiumServices.swift`）：每次 open 重解析；httpServer 常驻。

# Elsepage P0 并发执行方案 — 5 worktree + 并发 subagent

> 基线：2026-08-25。目标：把 PRD 审计中的 **P0 全量 5 项** 拆进 5 颗 worktree，
> 每颗一个并发 subagent 独立实现，完成后按依赖拓扑顺序合回 `main`。

## 0. 基线现状

- `main` = `00f8dee`（feat(agent): add LLM context routing）
- `origin/main` = `97e7d47`，**落后本地 main 2 个提交**（41fa5b6 EPUB pipeline、00f8dee LLM routing）。
  ⚠️ 本轮 worktree **以本地 `main` (00f8dee) 为 base** 而非 origin/main —— 否则 subagent 会缺 LLM 路由这一关键代码。
  如后续要对外推送，先 push main 再重建即可。
- `swift test` 基线：**83 个测试全部通过**。
- 遗留 worktree 处置（2026-08-25）：
  - **在途 WIP 归档**：citations WIP 提交为 `dde0bbf`（Citation 收口起点）；providers WIP 提交为 `bcc7eee`（P1 下一轮，parked）。
  - **清理**：删除空分支 worktree `journal`、`reflection-domain`、`reader-experience`、`ui-foundation` 与无 worktree 分支 `codex/agent-runtime-refactor`。
  - **保留搁置**：`overnight-agent/reader/reflection/thoughts`（前一晚批次的陈旧分支，主要是文档删除，待人工确认后归档）。

## 1. 范围：P0 全量 5 项

| # | 任务 | worktree | 分支 | base / 起点 |
|---|------|----------|------|-------------|
| P0-1 | Agent Citation 收口 | `citations`（复用） | `codex/vnext-citations` | main + WIP `dde0bbf` |
| P0-2 | Agent Session Context 完整性 | `session-context`（新建） | `codex/vnext-session-context` | main `00f8dee` |
| P0-3 | LLM Router 产品级可观测性 | `router-observability`（新建） | `codex/vnext-router-observability` | main `00f8dee` |
| P0-4 | Voice Reflection | `voice`（复用+rebase） | `codex/vnext-voice-reflection` | main + voice `eef82c6`（rebase 到 main） |
| P0-5 | Journal 结构化 | `journal`（重建） | `codex/vnext-journal` | main `00f8dee` |

明确不进入本轮：P1（Provider 工程、Bench、导入、Library、隐私）、P2（Memory、Habit）。

## 2. 目标

每个 P0 缺口收敛到「可合回 main」的增量，满足对应 PRD 验收：
- **Citation**：关键引用可点击回到证据源；citation 与 message 持久化；Evidence ID 本地验证；UI 展示本次使用的阅读数据。
- **Session Context**：F7 五项全进 Agent context（阅读区间 / Session Highlight / Session Note / 书内检索 / 本书 Reflection）。
- **Router 可观测性**：routing trace 落库、proposed/validated 区分、fallback 原因统计、选中 Evidence ID 透出、分段耗时、用户可见 Context Disclosure。
- **Voice**：录音 / 准实时转录 / 转录编辑 / 文字输入闭环；补长按、可选音频、失败恢复；修复 inputKind 回退 bug。
- **Journal**：从 Reflection Archive 升级为结构化 Journal（时长/章节/Highlight/What I think/Question/Citation/Memory 变化/source navigation）。

## 3. 架构不变量（沿袭 overnight-mvp，追加本轮专属）

1. 原始 Reflection 永不覆盖；派生内容（Journal、citation、trace）单独表/单独字段。
2. `AgentExecutor` / `ModelResponse` / `ModelContracts` 形状**本轮不改**；结构化解析一律在调用方（ReaderAgent 层）完成，避免 Provider 层三任务打架。
3. Provider 保持 `ModelClient` 契约；ASR 转录默认走系统 `Speech`，不引入云 STT。
4. migration 只增不改；**v8+ 编号由 coordinator 在合并时统一重排**。
5. `project.yml` / `Package.swift` 最终接线、`AppModel` 依赖注入、`SessionReflectionModel.submit()` 签名扩展由 **coordinator 拥有**；各任务只做 additive 变更并提交清晰的 diff。
6. trace 不持久化原始用户文本（ADR 0001）：只存 plan/统计/时长/Evidence ID/摘要。
7. 隐私：API Key 不进库、不进 trace。

## 4. 共享热点与解耦契约（深读结论）

五个任务在 4 个文件上有真实重叠，合并前必须对齐：

| 热点文件 | 涉及任务 | 解耦契约 |
|----------|---------|---------|
| `App/Reflection/SessionReflectionSheet.swift` | **全部 5 个** | editor 区（Voice）与 conversation/model 区（Citation/Journal/Disclosure）改动基本正交；`SessionReflectionModel.submit()` 签名扩展（`linkedHighlightIDs`、结构化输出回调）是唯一强耦合点，coordinator 定义契约 |
| `Sources/ReaderAgent/ReaderAgent.swift`（`run()` 事件流） | C / S / R | **一次**把 `ReaderAgentEvent` 扩展为可携带富载荷（`contextDisclosure`/`traceID`），而不是三任务各改一遍枚举；C 的 citation 解析、R 的计时+save trace、S 的 context 收集各自落独立函数 |
| `Sources/ReaderAgent/ReaderAgentPolicy.swift` | C / S / R | C 改 `[E(i+1)]` → `[E(i+1)][<chunkID>]` 绑定；S 加 Session/Highlight/Note/本书 Reflection 槽位；R 不动 prompt |
| `Sources/Persistence/AppDatabase.swift`（migration v8+） | C / R / J | coordinator 按合并顺序重排 v8/v9/v10；各任务先以 `v8_pending_*` 命名，合并时重排 |
| `Sources/ContextRouting/ContextRoutingModels.swift` | S / R | S 给 `ContextRoutingInput`/`AvailableContextSources` 加可用性字段；R 加 `ContextPlanTrace`（Codable），给 `ValidatedContextPlan` 补 Codable |
| `App/Thoughts/ThoughtsView.swift` + `ThoughtsModel.swift` | C / R / J | C 复用 `openSource(Book, BookLocator)` 渲染引用；R 加 disclosure 块；J 从 `ReflectionArchiveEntry` 投影切到 `JournalEntry` |

**接口预对齐**：
- `ReflectionEvidence` 作为 Citation 的超集：Journal 复用其 locator 列布局，Citation 收口只加 `title/excerpt/messageID`，不新起平行表。
- `TextReflectionSubmissionService` / `VoiceReflectionSubmissionService` 都要开始传 `linkedHighlightIDs`（当前恒 `[]`），信号来自 `ReaderModel.endReadingSession()` 算出的 session 内 highlights。
- 结构化输出：沿用 `LLMReaderContextRouter` 的 `JSONDecoder().decode` 范式，`ModelResponse.content` 保持纯文本，decode 在 ReaderAgent/Journal 层做。

## 5. 合并顺序（依赖拓扑）

```
Voice → Citation → Session Context → Router 可观测性 → Journal
```

理由：
1. **Voice** 最隔离（新模块 SpeechCore + Package/project.yml 增量），先合建立构建基座。
2. **Citation** 先合：`[E1]→chunkID` 绑定是 Router 观测 C4 与 Journal C7 的前置；其 message 持久化是 Journal 引用的基础。
3. **Session Context** 独立特征，rebase 到已含 Citation 的 main。
4. **Router 可观测性** 依赖扩展后的 `ReaderAgentEvent` 与证据绑定。
5. **Journal** 依赖 Citation 结构 + Session 数据，最后合。

每步：`git rebase main` → 解决冲突（coordinator 文件优先）→ 全量 `swift test` → merge。合并期间若前后分支有 build 冲突（如 SpeechCore target），coordinator 修复。

## 6. 各任务落地清单

> 每个任务开工前 subagent 须先 `git status` 确认在正确 worktree，结束前在**自己的工作区**跑 `swift test` 并记录命令/结果。禁止 push、禁止动 main、禁止跨 worktree checkout。

### P0-1 Citation 收口 — `citations` / `codex/vnext-citations`（起点 `dde0bbf`，已含部分 WIP）

**深读结论**：WIP 已含 `AgentCitationValidator`、Reflection citation 字段、`AgentCitationValidatorTests`、`AgentCitationPersistenceTests`。断点：模型输出无结构约束、`reflectionMessages` 无 citation 列、`[E1]` 不渲染不跳转、无"本次用了哪些数据"展示。

**改动文件**：`Sources/ReaderAgent/ReaderAgent.swift`（解析/持久化 + `ReaderAgentEvent` 富载荷）、`ReaderAgentPolicy.swift`（prompt 产出结构化 citation + `[E1][chunkID]` 绑定）、`AgentRuntime/ModelContracts.swift`（`ModelRequest.response_format` 可空扩展）、`Sources/ReflectionCore/Reflection.swift`（`ReflectionMessage` 加 citation 可选字段）、`Sources/Persistence/AppDatabase.swift`（migration v8：`messageCitations` 或 `reflectionMessages.citationsJSON`）、`ReflectionRepositories.swift`、`RetrievalCore/BookIndexRepository.swift`（`chunk(id:bookID:)` 供本地验证）、`AgentCitationValidator.swift`（补：chunk 属于该书 + 已读边界）、`App/DesignSystem/AgentMarkdownText.swift`（E1 tokenizer/可点击）、`App/Reflection/SessionReflectionSheet.swift`（conversation 区 provenance + DisclosureGroup）、`App/Thoughts/ThoughtsView.swift`（复用 openSource 渲染引用）。

**验收**：关键引用可点击跳回原文（PRD L1473/L783）；citation 随 message 持久化；Evidence ID 本地校验（chunk 存在、属该书、在已读边界内）；conversation 展示"本次使用了 N 处书内内容/过去的你"。测试全绿 + 新增 citation 渲染/验证/持久化测试。

### P0-2 Session Context 完整性 — `session-context` / `codex/vnext-session-context`（base `00f8dee`）

**深读结论**：当前 prompt 只有 5 类输入（系统提示、附近原文、书内检索、至多 1 条词法命中的过去想法、对话历史）。F7 五项中 Book 检索已接入；阅读区间/Highlight/Note/本书 Reflection 未进。

**改动文件**：`Sources/ReadingSessionCore/`（复用，只读）、`Sources/RetrievalCore/RetrievalModels.swift`（`ReaderAgentContextBuilder` 扩展或新建 `SessionContextBuilder`）、`Sources/ReaderAgent/ReaderAgent.swift`（注入 `ReadingSessionRepository` + `ReadingRepository`；收集 session 区间/highlight/note/`reflections(for bookID:)`）、`ReaderAgentPolicy.swift`（新增 context 槽位）、`Sources/ContextRouting/ContextRoutingModels.swift`（`AvailableContextSources` 加 `hasSessionHighlight/hasSessionNote/hasBookReflections`）、`App/AppModel.swift`（注入，coordinator 契约）。

**验收**：F7 五项全进 context；Session 阅读区间用 `startLocator→endLocator`（非仅"当前 locator 之前"）；本书 Reflection 走 `reflections(for bookID:)` 而非全局 50 条；highlight/note 按 `createdAt` 窗口 + `bookID` 归属（本轮不加 `sessionID` FK，除非经 coordinator 同意加 migration）。新增 context 组装测试。

### P0-3 Router 可观测性 — `router-observability` / `codex/vnext-router-observability`（base `00f8dee`）

**深读结论**：`route`(L143)/`build`(L153)/`reply`(L164) 是三条天然耗时边界；proposed/validated 现都在 `ReaderAgent.run` 作用域但被丢弃；`RoutingFallbackReason` 只两值，`.failed` 的 `AgentFailure` 粒度丢失；证据只有 `[E1]` 索引无真实 ID 透出；`ReaderAgentEvent` 只带 `ReflectionConnection?`。

**改动文件**：`Sources/ContextRouting/ContextRoutingModels.swift`（`ContextPlanTrace` Codable：proposed/validated/usedFallback/fallbackReason/三段 Duration/`selectedBookEvidenceIDs`/`connectedReflectionID`/双 tokenUsage；`ValidatedContextPlan`/`ContextBudget` 补 Codable）、`ContextRouting/LLMReaderContextRouter.swift`（fallback 透传 `AgentFailure` 粒度）、`Sources/Persistence/`（`RoutingTraceRepository` 协议 + `GRDBRoutingTraceRepository` + `routingTraces` 表 migration v8）、`AppDatabase.swift`（v8，不存原始文本）、`ReaderAgent.swift`（`ContinuousClock` 三段计时 + save trace + `ReaderAgentEvent` 富载荷 + `ContextDisclosure`）、`App/Reflection/SessionReflectionSheet.swift`（回应下方小型披露块）、`App/Thoughts/ThoughtsView.swift`（归档场景 disclosure）、`App/Settings/ProviderSettingsView.swift`（诊断入口：fallback counts + 分段耗时均值）。

**验收**：每次 Agent 回复产生一条 routing trace（含 proposed/validated/fallback 原因/Evidence ID/三段耗时）；fallback 统计可按原因聚合；conversation 显示正向披露文案（"参考了已读部分 N 处内容"）；设置页可见诊断。新增 trace 持久化/统计测试。

### P0-4 Voice Reflection — `voice` / `codex/vnext-voice-reflection`（rebase 到 main + `eef82c6`）

**深读结论**：已有实现约 70%（状态机/系统转录 provider/提交服务/UI + 5 测试，无需 DB migration，v3 已有 `inputKind`/`audioFileName` 列）。缺口：**长按录音**（PRD F5 明确）、可选音频保存、关联 Highlight、`markVoiceTranscript` 不回退 `.text` 的 bug、语言选择可选。

**改动文件**：`App/Reflection/SessionReflectionSheet.swift`（长按手势 + haptics；`markVoiceTranscript` 回退逻辑；`linkedHighlightIDs` 传入——与 Journal 共享契约）、`App/Reflection/VoiceReflectionRecorder.swift`、`Sources/SpeechCore/VoiceReflectionState.swift`（加 audio 保存选项状态）、`Sources/ReflectionCore/VoiceReflectionSubmissionService.swift`（audioFileName 可选 + linkedHighlightIDs）、`project.yml`（权限文案已有，补音频权限文案若需）、`Tests/ReadLoopCoreTests/VoiceReflectionTests.swift`（补长按/音频用例）。

**验收**：长按录音 + 准实时转录 + 编辑 + 纯文字全链路；转录失败/权限拒绝可恢复且不丢已说内容；提交幂等；音频默认不保存、可选保存；"先语音后删光改纯文字"保存为 `.text`。测试全绿。

### P0-5 Journal 结构化 — `journal` / `codex/vnext-journal`（base `00f8dee`）

**深读结论**："思想"页现为 `ReflectionArchiveService.recentEntries()` + `ThoughtsArchiveProjection`，只读 `books/reflections/reflectionMessages/reflectionEvidence/reflectionConnections` 五表。缺：session 时长/章节、Highlight 关联、What I think、独立 Agent Question、Citation、Memory 变化。

**改动文件**：`Sources/ReflectionCore/ReflectionArchive.swift`（`ReflectionArchiveEntry` 增 `session`/`chapters`/`linkedHighlights`；或引入 `JournalEntry` 派生模型）、`Sources/ReflectionCore/`（新增 `AgentQuestion` 模型 + `JournalEntry` 组装服务）、`Sources/Persistence/AppDatabase.swift`（migration：`agentQuestions`、`journalThoughts`、`journalMemoryChanges`、citation 表与 P0-1 共用）、`ReflectionRepositories.swift`（对应 repository 方法）、`Sources/Persistence/BookIndexRepository.swift`（`chapters(for:bookID:locator:)` 查询，复用 `bookChapters`/`bookChunks`）、`App/Thoughts/ThoughtsView.swift` + `ThoughtsModel.swift`（从 archive 投影切到 JournalEntry；时长/章节/Highlight/Question/Citation/Memory 变化展示；source navigation 复用 `openSource`）、`App/Reader/ReaderModel.swift` + `ReaderScreen.swift`（session 高亮 ID 捕获）、`App/AppModel.swift`（注入 `ReadingSessionRepository`，coordinator 契约）。

**验收**：每次 Reflection 后自动生成结构化 Journal；展示 session 时长/章节、关联 Highlight、What I think（1–3 条忠于用户）、Agent Question 与 open 追踪、Citation（点击跳原文）、Memory 变化快照、source navigation 直达原文。新增 Journal 组装/投影测试。

## 7. 编排机制（并发 subagent 生命周期）

1. **Phase 0 前置**（本轮已完成）：深读建图、WIP 归档、清理过期 worktree、基线测试（83 pass）。
2. **Phase 1 建 worktree**：按 §1 注册表创建/规范化 5 颗 worktree（base = main）。
3. **Phase 2 并发执行**：coordinator 同时派 5 个 subagent，每个：
   - 工作目录 = 对应 worktree 绝对路径；任务说明指向本 MD 的对应小节。
   - 只在自己的分支提交；不 push；不动 main；不跨 worktree。
   - 中途 checkpoint 用 `SendMessage` 汇报进度；卡住/越权改动立即上报。
   - 结束前跑 `swift test`，记录命令/结果；产出「改动清单 + 未决项」报告。
4. **Phase 3 顺序合回**：按 §5 顺序逐个 rebase + 全量测试 + merge；冲突以 coordinator 契约为准；每合一个记录进 §10。
5. **Phase 4 验收**：全量 `swift test`、`xcodegen generate`、unsigned iOS build；真机项（长按录音、语音权限、EPUB 跳转）标注为 manual Xcode gate。

**并发注意**：SwiftPM 依赖解析共享缓存有锁竞争（同 overnight-mvp 遇到的坑）。策略：5 颗 worktree 各自的 `.build` 独立；若解析锁卡住，subagent 等待并在报告注明，coordinator 事后串行补测。

## 8. Verification gates

- 每个 worktree 内：`swift test`（targeted）→ 记录精确命令/结果。
- 每次合回后：全量 `swift test`（基线 83 → 只增不减）、`xcodegen generate`、unsigned iOS `xcodebuild`。
- 磁盘空间前后检查；只允许清理可复现缓存。
- Voice 的录音/权限为设备级行为，走 `docs/READER_FOUNDATION_XCODE_GATE.md` 手工 gate，不在 CLI 声称 device-verified。

## 9. Known risks / 未决决策

- **origin/main 落后 main 2 提交**：本轮以 main 为 base；若需对外，先 push main。
- **`SessionReflectionSheet.swift` 五任务同文件**：editor/conversation/model 三区已按功能隔离，但仍需三方合并；`submit()` 签名扩展是唯一强耦合，coordination 必做。
- **migration v8 编号**：C/R/J 各占一版，coordinator 按合并顺序重排；各任务先 `v8_pending_*`。
- **JSON mode 依赖**：Citation 要模型输出结构化 citation，需要 `ModelRequest.response_format`（可空扩展）；若某 Provider 不支持 JSON mode，fallback 到"文本内解析 `[E1]` 块"。
- **ADR 0001 与 trace 持久化**：产品级 trace 须脱离"ephemeral"决策面，存摘要而非原始文本；若涉用户文本，做哈希/截断。
- **Voice 音频文件存储**：默认不保存符合 PRD"可选"，但"选择保存"需要文件存储路径与清理策略，本轮按最小实现（存 Documents/Reflections，进 `audioFileName`）。
- **Journal 与 Memory 边界**：`journalMemoryChanges` 只做派生快照，不接 Memory 域（P2 任务，避免塞进 ReflectionRepository）。

## 10. Handoff checklist / Integration record

- 记录每颗 worktree 分支/commit、合并顺序、migration 编号、测试/构建结果、未决集成问题、手工设备项。
- 若实现实质改变 README/gate 文档，同步更新。

## 11. 执行记录（Phase 2 + Phase 3，2026-08-25）

### Phase 2 — 5 个并发 subagent 交付

| 任务 | 分支 | 提交数 | worktree 测试 |
|---|---|---|---|
| P0-1 Citation | `codex/vnext-citations` | 6 | 93/93 |
| P0-2 Session Context | `codex/vnext-session-context` | 4 | 87/87 |
| P0-3 Router 可观测性 | `codex/vnext-router-observability` | 5 | 91/91 |
| P0-4 Voice | `codex/vnext-voice-reflection` | 4 | 91/91 |
| P0-5 Journal | `codex/vnext-journal` | 4 | 89/89 |

### Phase 3 — 顺序合回 main

合并顺序 V→C→S→R→J，每次合并后全量 `swift test`：

| 顺序 | 合并提交 | 合入后测试 |
|---|---|---|
| 1 Voice | `48b352e` | 91/91 |
| 2 Citation | `3f002f9` | 101/101 |
| 3 Session Context | `8a3c996` | 105/105 |
| 4 Router | `5471bbc`（6 文件冲突已解） | 113/113 |
| 5 Journal | `9ddd9cf`（6 文件冲突已解） | 119/119 |

合并中修复（coordinator）：
- `SessionContextBuilderTests.readerAgentConnectsOnlySameBookPastReflections`：`.completed` 后新增 `.contextDisclosed` 事件，改为 `last(where:)` 定位最后的 `.completed`。
- `RoutingTracePersistenceTests.routingTraceSavesRoundTripsAndLatestTraceWins`：两个 trace 的 `createdAt` 落在 GRDB julian-day Double 同一精度格点 → flaky；改为显式不同 createdAt。
- AppDatabase 双右花括号残留（Journal 合并时 conflict 区尾部）已修。

### Migration 重排（coordinator）

`v8_pending_citations` → `v8_agent_citations`；`v8_pending_router_trace` → `v9_routing_trace`；`v8_pending_journal` → `v10_journal`。提交 `bd41c49`。

### 合并后的已知债务 / 未决项

- **citation 双表重叠**：P0-1 建 `agentResponseEvidence`+`agentCitations`（live provenance，按 messageID）；P0-5 建 `reflectionCitations`（journal 快照，按 reflectionID）。功能不冲突但数据冗余，后续应让 Journal 读取 agentCitations 并废弃 reflectionCitations。
- **`contextRecipeVersion`** 仍为 `reflection-book-hybrid-read-so-far-v1`（Session Context 已实质改配方），语义上升 v2 需同步改 AgentProviderTests 断言，未做。
- **Voice 长按/录音/权限** 为设备级行为，需真机 Xcode gate。
- **linkedHighlightIDs** 在 SessionReflectionSheet 提交处已由 coordinator 统一接上（voice/text 两分支都传）；capture 端（ReaderModel.endReadingSession）已由 Journal 任务打通。
- **App 层编译**：swift test 不编译 App target，由 Phase 4 xcodegen + xcodebuild gate 验证。

### Phase 4 门禁（构建中）

- `xcodegen generate` ✅（ReadLoop.xcodeproj 已更新，含 SpeechCore/ContextRouting 新 product）。
- unsigned iOS Simulator `xcodebuild` 后台构建中。

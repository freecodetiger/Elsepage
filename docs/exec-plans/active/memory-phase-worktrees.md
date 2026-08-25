# Elsepage 0.3 Memory 阶段并发执行方案 — 5 worktree / 2 波次

> 基线：2026-08-25（main = `c663a31`，与 origin/main 同步，工作区干净）。
> 目标：PRD 审计收敛出的 **0.3 Memory（核心）+ 0.5 最小一档（Thinking Streak + 数据控制）**，
> 拆进 5 颗 worktree，分 2 波并发 subagent 实现，按依赖拓扑合回 `main`。
> 完成度提升点：`0.2 闭环收尾 → 0.3 Memory 落地`（补齐 F10/F11/P7 不变量），并顺手打通 1.0 硬性的数据控制。

## 0. 基线现状

- `main` = `c663a31`（chore(app): rename home-screen display name to 页外），`origin/main` 同步，工作区干净。
- `swift test` 基线：**123 个测试全部通过**（跑完已 `git checkout -- Package.resolved`）。
- 上一轮（P0 五任务）已交付：Citation / Session Context / Router 可观测 / Voice / Journal，migration 至 **v11_polished_text**。
- 遗留 worktree（`../elsepage-worktrees/` 下 citations/journal/voice/router-observability/session-context/providers/overnight-*）均为已合入 main 的陈旧分支，**本轮不复用**；Phase 0 由 coordinator 标记停用，避免 subagent 误入。
- 本轮关键事实：`journalMemoryChanges` 表**已经存在**，`JournalStructuredParser` 已把 Agent 的 memory 提案解析并落库——但**没有任何人把它消费成长期记忆**。这半截管线正是本轮要闭合的。

## 1. 范围：5 WS / 2 波次

| # | 任务 | worktree | 分支 | base | 波次 |
|---|------|----------|------|------|------|
| WS1 | Memory 落库（Core：v12 迁移 + MemoryRepository + 应用管线） | `memory-core`（新建） | `codex/vnext-memory-core` | main `c663a31` | **波 1**（主干） |
| WS4 | Reading / Thinking Streak（Core 派生 + Today UI） | `streak`（新建） | `codex/vnext-streak` | main `c663a31` | **波 1**（独立） |
| WS5 | 数据控制：Export My Data + Delete Book & Index（Settings） | `data-control`（新建） | `codex/vnext-data-control` | main `c663a31` | **波 1**（独立） |
| WS2 | My Mind / "AI 眼中的我"（Memory 可见可改 UI） | `my-mind`（新建） | `codex/vnext-my-mind` | 含 WS1 的 main | **波 2**（依赖 WS1） |
| WS3 | 跨书 Personal Retrieval + 记忆检索（ReaderAgent） | `crossbook-retrieval`（新建） | `codex/vnext-crossbook-retrieval` | 含 WS1 的 main | **波 2**（依赖 WS1） |

明确不进本轮（记录为 known debt，避免膨胀）：citation 双表冗余（reflectionCitations vs agentCitations）、ReaderAgentBench harness、Achievement 体系、Provider native API（Anthropic Messages）、语义 embedding 落地。

## 2. 目标（每 WS 对应 PRD 验收）

- **WS1 Memory 落库**（F10 / PRD §19 Memory）：
  - `memories` 表含 `kind / claim / confidence / status / userEdited / evidenceIDs / createdAt / updatedAt`；
  - 新 Memory 必须带 evidence（指向源 reflection + message）；
  - **删除原 Reflection 后其派生 Memory 级联删除**（PRD §19「应重新标记或删除」取删除）；
  - 消费 `journalMemoryChanges` 的 store/reinforce/revise 三态应用；**userEdited 的记忆永不被自动覆盖**（P2 精神延伸）。
- **WS4 Streak**（F12）：Reading Streak + Thinking Streak 两个派生指标，Today 首页展示；Thinking Streak 存在感不弱于 Reading Streak（PRD §18.1）。无新表。
- **WS5 数据控制**（§13.3）：Export My Data（Codable JSON 打包全量个人数据 + Share Sheet）、Delete Book & Index（含索引文件，复用已有 cascade）；不碰 provider 配置与记忆域。
- **WS2 My Mind**（F11 / P7 不变量）："AI 眼中的我"区块，每条支持 准确 / 不准确 / 修改 / 忘记 / 查看依据（点击回原 Reflection）；一键清除 Agent Memory。语气定位"这是我目前从阅读与讨论中形成的理解"，避免心理诊断感。
- **WS3 跨书检索**（F8 / PRD §18.1）：Agent 的 past-thought 检索从**同书**扩为**跨书 + 记忆**，命中进 context 并标 `pastReflection` 证据；保守阈值不变，宁缺毋滥（PRD P4）。

## 3. 架构不变量（沿袭 P0 轮，追加本轮专属）

1. 原始 Reflection 永不覆盖；Memory 是派生数据，`userEdited` 后 AI 自动应用不得覆盖（**本轮新增不变量**）。
2. migration 只增不改：本轮**仅 WS1 加 v12_memory**，编号 coordinator 拥有；其他 WS 一律不允许加迁移。
3. `AgentExecutor` / `ModelContracts` 形状本轮不改；memory 提案的解析继续走 `JournalStructuredParser`（已有），WS1 只消费结果不重复解析。
4. 证据 kind 复用：**不新增** `agentResponseEvidence.kind` 枚举值（避免改 CHECK 约束），记忆类证据复用 `pastReflection`，靠 `title` 区分。
5. `project.yml` / `Package.swift` 最终接线、`AppModel`/`LibraryModel` 依赖注入、AppShell Tab 增改由 **coordinator 拥有**；各 WS 只做 additive 变更并提交清晰 diff。
6. 隐私：Export 产物是用户自己的数据；API Key 不进导出、不进 memory claim 之外任何落库。

## 4. 共享热点与解耦契约（深读结论）

| 热点文件 | 涉及 WS | 解耦契约 |
|----------|---------|---------|
| `Sources/Persistence/AppDatabase.swift` | **仅 WS1** | v12 迁移归 WS1 独占；其余 WS 不得加迁移。`ifNotExists: true` 保旧库兼容 |
| `Sources/ReflectionCore/JournalEntryService.swift` + `Journal.swift` | WS1（应用管线） / WS2（只读） | `MemoryApplicationService` 由 WS1 新增，消费 `journalMemoryChanges`；WS2 只经 `MemoryRepository` 读，不碰该文件 |
| `Sources/ReaderAgent/ReaderAgent.swift` + `ReaderAgentPolicy.swift` + `SessionContextBuilder.swift` | **仅 WS3** | WS3 独占；WS1/WS2/WS4/WS5 一律不 touch（ReaderAgent 是上轮 6 冲突的热点，本轮隔离） |
| `Sources/ReflectionCore/TodayProductState.swift` + `App/Today/TodayView.swift` | **仅 WS4** | WS4 独占 Today 域 |
| `App/Settings/ProviderSettingsView.swift` | **仅 WS5** | WS5 在 Settings 加"数据"Section；WS2 的 My Mind 不走 Settings，避免冲突 |
| `App/AppShell.swift` | WS2 / coordinator | WS2 提出 Tab 增改方案（第 4 Tab "我的头脑" 或并入"思想"），**由 coordinator 落**，WS2 只交方案与视图组件 |
| `Sources/ReflectionCore/Reflection.swift`（ReflectionID） | WS1 / WS3 | 只读复用，不改 |
| `Sources/Persistence/Repositories.swift` / `ReflectionRepositories.swift` | WS1 | WS1 在此加 `GRDBMemoryRepository`（或新文件 `MemoryRepositories.swift`）；WS3 的检索只经 Repository 协议读 |

**接口预对齐（coordinator 裁定，subagent 不得改签名）：**

- **Memory 模型**（WS1 产出，WS2/WS3 依赖）：
  ```swift
  public enum MemoryKind: String, Codable, Sendable, CaseIterable {
      case episodic, semantic, preference, openQuestion, profileTrait
  }
  public enum MemoryStatus: String, Codable, Sendable, CaseIterable {
      case provisional, active, superseded
  }
  public struct ReaderMemory: Hashable, Codable, Sendable, Identifiable {
      public let id: UUID
      public let sourceReflectionID: ReflectionID?   // FK cascade，删除 reflection 即删派生 memory
      public let kind: MemoryKind
      public let claim: String
      public var confidence: Double                  // 0...1
      public var status: MemoryStatus
      public var userEdited: Bool
      public let evidenceIDs: [String]               // "refl:<uuid>" / "msg:<uuid>"
      public let createdAt: Date
      public var updatedAt: Date
  }
  public protocol MemoryRepository: Sendable {
      func memories() async throws -> [ReaderMemory]
      func memories(kind: MemoryKind) async throws -> [ReaderMemory]
      func save(_ memory: ReaderMemory) async throws
      func delete(id: UUID) async throws
      func deleteAll() async throws
      func markInaccurate(id: UUID) async throws      // → status .superseded（保留可审计）
  }
  ```
- **Memory 应用语义**（WS1 的 `MemoryApplicationService.apply(journalChange:evidence:)`）：
  - `store` → 新建（status .provisional，confidence 0.6，evidence 指向源 message）；
  - `reinforce` → confidence +0.15（封顶 0.95），更新 updatedAt；
  - `revise` → 仅当目标 `!userEdited` 才覆盖；`userEdited` 则保留用户版并跳过（可留 debug 日志）；
  - 重复消息幂等：同 message 不重复应用（复用 `journal.hasStructuredData` 或给 memory 记 messageID）。
- **跨书检索**（WS3）：
  - 候选池从 `reflections(for: bookID)` 扩为**全部 reflection**（排除当前）+ 词法命中的 memories（top N）；
  - 证据统一复用 `.pastReflection`，`title` 用"过去的想法" / "长期记忆"区分；连接仍 `saveConnection(sourceReflectionID)`；
  - `ReflectionLexicalMatcher` 阈值（≥2 shared tokens、40% overlap）**不变**，保守优先（P4）。
- **Streak**（WS4）：
  - 纯派生、无新表：Reading 从 `readingSessions.startedAt`，Thinking 从 `reflections.createdAt`；
  - 本地 `Calendar`，当天多次算 1 天，昨天截止不断（今日为 0 时 streak 仍连续）；新增 `Sources/ReflectionCore/Streak.swift`（calculator + 两个值对象）。
- **Export**（WS5）：新增 `PersonalDataExporter`（Persistence 或 ReflectionCore），Codable 编码 reflections/messages/evidence/connections/sessions/journal(thoughts/questions/citations/memoryChanges)/books → 单个 JSON 文件 → `ShareLink`。**不导出** provider 配置与 Keychain。
- **Delete Book & Index**（WS5）：复用 `GRDBBookRepository.delete`（cascade 已有测试 `bookDeletionCascadesPositionHighlightsNotesAndPreferences`）；补齐 `BookFileStore` 的索引文件删除。

## 5. 依赖拓扑与合并顺序

```
波 1（并发、互不依赖）:  WS1 Memory ── WS4 Streak ── WS5 Data
                              │
波 2（依赖 WS1 合入后）:      ├── WS2 My Mind
                              └── WS3 Cross-book Retrieval
```

合并顺序：
1. **WS1 Memory**（主干，先合，波 2 依赖）→ 全量测试
2. **WS4 Streak**（独立，可与 WS1 乱序）→ 全量测试
3. **WS5 Data**（独立）→ 全量测试
4. **WS2 My Mind**（rebase 到含 WS1 的 main）→ 全量测试
5. **WS3 Cross-book**（rebase 到含 WS1 的 main）→ 全量测试

每步：`git rebase main` → 解冲突（coordinator 契约优先）→ 全量 `swift test` → merge。WS1 合入后立即把新 main 广播给波 2 的 worktree（`git fetch` + rebase），使 WS2/WS3 尽早基于新基座。

## 6. 各任务落地清单

> 开工前 subagent 先 `git status` 确认在正确 worktree；结束前在**自己工作区**跑 `swift test` 并记录命令/结果。禁止 push、禁止动 main、禁止跨 worktree checkout。

### WS1 Memory 落库 — `memory-core` / `codex/vnext-memory-core`（base `c663a31`）

**深读结论**：`journalMemoryChanges`（store/reinforce/revise + summary + memoryID）已存在、`JournalStructuredParser` 已解析；`JournalEntryService.materializeStructuredOutput` 已把它们写进 journal 表。断点：无 `memories` 表、无仓库、无人消费提案。

**改动文件**：`Sources/Persistence/AppDatabase.swift`（**唯一**加 migration v12：`memories` 表，`sourceReflectionID` FK → reflections ON DELETE CASCADE，`ifNotExists: true`）、`Sources/ReflectionCore/`（新增 `Memory.swift`：`ReaderMemory`/`MemoryKind`/`MemoryStatus`/`MemoryRepository` 协议 + `MemoryApplicationService`）、`Sources/Persistence/`（新增 `MemoryRepositories.swift`：`GRDBMemoryRepository` 实现）、`Sources/ReflectionCore/JournalEntryService.swift`（在 materialize 后调用 `MemoryApplicationService.apply`，保持幂等；或独立 `MemoryPipeline` 由 coordinator 接线——见 §7）。

**验收**：`memories` 表存在且升级旧库（v1–v11 含 v11）不删库；store→新建 / reinforce→置信提升 / revise→覆盖且 **userEdited 不被覆盖** 三态语义测试；删除 reflection 级联删派生 memory（PRD §19）；新 memory 均带 evidenceIDs；全量测试只增不减。**注意 `Package.swift` 若新增产品 target 需 coordinator 确认**（可并入 ReflectionCore，避免动 project.yml）。

### WS4 Streak — `streak` / `codex/vnext-streak`（base `c663a31`）

**深读结论**：`TodayProductState` 只做"是否该反思/已完成"判定；无任何连续天逻辑。Today 是 Next Action 页（PRD §6.1）。

**改动文件**：`Sources/ReflectionCore/`（新增 `Streak.swift`：`StreakCalculator` + `ReadingStreak`/`ThinkingStreak`）、`Sources/ReflectionCore/TodayProductState.swift`（可选：把 streak 作为派生投影的一部分，或由 TodayModel 计算）、`App/Today/TodayView.swift` + `App/Today/TodayModel.swift`（今日卡片展示两条 streak：`连续阅读 N 天` / `连续思考 N 天`，Thinking 视觉不弱于 Reading；streak 延续时一次 haptic——复用 §10.4）、`Tests/ReadLoopCoreTests/`（`StreakCalculatorTests`：当天多次算 1、昨天断、连续 N 天、跨月）。

**验收**：两条 streak 从真实 sessions/reflections 派生、无新表、无迁移；Today 首页可见；测试覆盖边界（当天多次、断档、空历史）。

### WS5 数据控制 — `data-control` / `codex/vnext-data-control`（base `c663a31`）

**深读结论**：Settings 现有 Provider + 路由诊断 Section；GRDB cascade 能力已有但无 UI；`BookFileStore` 存在。

**改动文件**：`Sources/ReflectionCore/` 或 `Sources/Persistence/`（新增 `PersonalDataExporter.swift`：把 §4 列出的个人数据编码为 JSON）、`Sources/Persistence/BookFileStore.swift` + `Sources/AppInfrastructure/BookImporter.swift`（`deleteBookAndIndex(bookID:)`，删 DB 行 + 沙盒文件）、`App/Settings/ProviderSettingsView.swift`（新增"数据"Section：`导出我的数据` / `删除书籍与索引`(destructive，逐本或当前全部)）、`Tests/ReadLoopCoreTests/`（`PersonalDataExporterTests`：导出→重导入往返一致、不含 provider 密钥字段；`deleteBookAndIndex` 连文件带 DB 一并清）。

**验收**：一键导出全量个人数据为可读 JSON 并通过 Share Sheet 分享；删除书籍级联清 DB 与沙盒索引文件；provider 配置与 Keychain 不受影响；**不 touch memories 表**（归 WS2）。

### WS2 My Mind / "AI 眼中的我" — `my-mind` / `codex/vnext-my-mind`（base = 含 WS1 的 main）

**深读结论**：无任何 memory UI；"思想"Tab 现为 ThoughtsView（archive/journal 双投影）；无第 4 Tab。

**改动文件**：`App/`（新增 `MyMind/MyMindView.swift` + `MyMindModel.swift`：分 `记忆` 与 `AI 眼中的我` 两块；每条 memory 显示 kind 徽标 + claim + confidence + 证据数，点证据跳回原 Reflection（复用 `openSource`）；操作：准确 / 不准确 / 修改 / 忘记 / 一键清除）、`App/AppShell.swift`（**提交 Tab 方案**，由 coordinator 决定第 4 Tab 或并入思想 Tab）、`Sources/ReflectionCore/`（若需 `ReaderProfileProjection`：从 memories 聚合出 profile 摘要，evidence-based、可编辑）、`Tests/ReadLoopCoreTests/`（projection 聚合 + 编辑后不被 AI 覆盖的测试）。

**验收**（P7 不变量）：记忆全部可见、可溯源到原 Reflection、可改/删/标记不准确/一键清除；`markInaccurate` 后新自动应用不复活旧 claim；删除 reflection 后其派生记忆从 UI 消失（级联由 WS1 保证，WS2 验证）。

### WS3 跨书 Personal Retrieval + 记忆检索 — `crossbook-retrieval` / `codex/vnext-crossbook-retrieval`（base = 含 WS1 的 main）

**深读结论**：`ReaderAgent.run` 的候选池被硬编码为 `reflections(for: reflection.bookID)`（同书）；`ReflectionLexicalMatcher` 只收 `[Reflection]`；`responseEvidence` 的 `pastReflection` 槽位已存在。

**改动文件**：`Sources/ReaderAgent/ReaderAgent.swift`（候选池改为全库 reflection 排除当前 + `MemoryRepository.memories()` 词法命中 top N；跨书连接仍 `saveConnection`）、`Sources/ReaderAgent/ReaderAgentPolicy.swift`（`previousReflection` 槽位语义扩为"过去的想法（可能跨书）+ 长期记忆"，title 区分）、`Sources/ReaderAgent/SessionContextBuilder.swift`（若需把记忆带进 context）、`Tests/ReadLoopCoreTests/`（跨书命中：同主题两本书能连；无关书不连；记忆命中标 `pastReflection`；阈值保守回归）。

**验收**：Agent 能引用**其他书**的旧想法并让用户点击跳回；能引用长期记忆（title 显示"长期记忆"）；同书优先、跨书次之（排序：同书 > 跨书 > 记忆）；全量测试只增不减。**不新增 evidence kind、不加迁移。**

## 7. 编排机制（并发 subagent 生命周期）

1. **Phase 0 前置**：停用/标记陈旧 worktree；基线测试（123 pass）复核；写本 MD。
2. **Phase 1 建 worktree**：按 §1 注册表创建 5 颗 worktree（波 1 三颗 base = main；波 2 两颗先建在 main 上，待 WS1 合入后 rebase）。
3. **Phase 2 波 1 并发**：同时派 WS1 / WS4 / WS5 三个 subagent。每个：
   - 工作目录 = 对应 worktree 绝对路径；任务说明指向本 MD 对应小节；
   - 只在自己分支提交；不 push；不动 main；不跨 worktree；
   - 中途 checkpoint 用 `SendMessage` 汇报；卡住/越权改动立即上报；
   - 结束前在自己 worktree 跑 `swift test` 记录命令/结果；产出「改动清单 + 需要 coordinator 接线的点 + 未决项」报告。
4. **Phase 3 WS1 合回 + 波 2 启动**：WS1 rebase + 全量测试 + merge → 把新 main fetch 到波 2 两颗 worktree 并 rebase → 派 WS2 / WS3。
5. **Phase 4 顺序合回波 2 + 全量验收**：按 §5 顺序合 WS2/WS3；每次全量 `swift test` + `xcodegen generate` + unsigned xcodebuild；记录进 §10/§11。

**并发注意**：SwiftPM 依赖解析共享缓存有锁竞争（上轮同坑）。策略：5 颗 worktree 各自 `.build` 独立；解析锁卡住就等待并在报告注明，coordinator 事后串行补测。另：WS2/WS3 的 base 是"含 WS1 的 main"，创建/切分支时务必先 `git fetch` 主仓库再 rebase，防止基于过期 main 空跑。

## 8. Verification gates

- 每个 worktree 内：`swift test`（targeted）→ 记录精确命令/结果。
- 每次合回后：全量 `swift test`（基线 123 → 只增不减）、`xcodegen generate`、unsigned iOS `xcodebuild`（App 层 gate）。
- **v12 向后兼容**：`preRenumberedDevDatabaseUpgradesWithoutDeletion` 同类回归——从 v1 逐级升到 v12 且旧数据（books/reflections/journalMemoryChanges）原样保留。
- Memory 应用幂等：同一 message 重复跑 materialize 不重复建 memory。
- My Mind 的证据跳转、跨书记忆提示为 App 层行为，走 `docs/READER_FOUNDATION_XCODE_GATE.md` 手工/模拟器 gate，不在 CLI 声称 device-verified。

## 9. Known risks / 未决决策

- **ReaderAgent 独占**：WS3 是唯一 touch ReaderAgent 的 WS，但波 1 的 WS1 若动了 `ReflectionID`/证据相关文件需避免与 WS3 语义冲突——已用契约隔离（WS1 不碰 ReaderAgent，WS3 只读 MemoryRepository）。
- **Memory 应用管线的接线点**：放 `JournalEntryService.materializeStructuredOutput` 之后（复用其幂等 `hasStructuredData`），由 coordinator 决定是内联扩展还是独立 `MemoryPipeline` 任务；两者 API 均不得再变。
- **跨书检索的排序口径**：同书 > 跨书 > 记忆是初版口径；若未来语义 embedding 落地，排名可换 HybridRanker——本轮不改排序器。
- **`markInaccurate` 的复活防护**：superseded 的 claim 若被后续 `reinforce` 命中，按 `userEdited || status == .superseded` 一律跳过（写进 MemoryApplicationService 的不变量测试）。
- **Export 含哪些字段**：以"用户自己的原始数据"为准（reflections 原文、messages、sessions、highlights、notes、connections、journal 派生、books），**不含** routingTrace 原始 JSON（trace 是诊断数据）——如需纳入由 coordinator 再裁。
- **citation 双表 / contextRecipeVersion v2 / embedding dormant**：均记录为 known debt，本轮不做，避免范围膨胀重蹈上轮 6 文件冲突。

## 10. Handoff checklist / Integration record

- 记录每颗 worktree 分支/commit、合并顺序、migration 编号（本轮仅 v12）、测试/构建结果、未决集成问题、手工设备项。
- 若实现实质改变 README/gate 文档，同步更新（README 的 Status 表 0.3 一栏可在 WS1 合入后由 coordinator 更新）。

## 11. 执行记录（2026-08-25）

### Phase 2 — 波 1 三个并发 subagent 交付

| WS | 分支 | 提交数 | worktree 测试 |
|---|---|---|---|
| WS1 Memory 落库 | `codex/vnext-memory-core` | 3 | 131/131 |
| WS4 Streak | `codex/vnext-streak` | 3 | 132/132 |
| WS5 数据控制 | `codex/vnext-data-control` | 2 | 125/125 |

### Phase 3 — 波 1 顺序合回 main

| 顺序 | 合并 | 合入后测试 |
|---|---|---|
| WS4 | ff `a1ca7eb` | 132/132 |
| WS5 | merge `85b6ed9` | 134/134 |
| WS1 | ff `3695d33`（rebase 到含 WS4+WS5 的 main，无冲突；AppModel 两处接线自动合并） | 142/142 |

### Phase 2 — 波 2 两个并发 subagent 交付

| WS | 分支 | 提交数 | worktree 测试 |
|---|---|---|---|
| WS2 My Mind | `codex/vnext-my-mind` | 2 | 145/145 |
| WS3 跨书检索 | `codex/vnext-crossbook-retrieval` | 2 | 146/146 |

### Phase 3 — 波 2 顺序合回 + coordinator 接线

| 顺序 | 合并 | 合入后测试 |
|---|---|---|
| WS3 | ff `f1c2196`+`bf68fed` | 146/146 |
| WS2 | ff `311bea1` | 149/149 |
| coordinator 接线 | `be8b59c`：AppShell 第 4 Tab「我的头脑」+ AppModel `myMind` + ReadLoopApp guard + xcodegen 纳入 MyMind 文件 | 149/149 |

### Migration 确认

仅 **v12_memory**（WS1 独占）：`memories` 表 `ifNotExists: true`，`sourceReflectionID` FK → reflections ON DELETE CASCADE；旧库 v1–v11 升级不删库（回归测试 `v11DatabaseUpgradesToV12MemoryWithoutDeletion`）。

### 关键决策 / 偏差

- `ReaderMemory.claim` 为 `var`（非计划中的 `let`），支撑 `revise` 覆盖与 My Mind 编辑。
- 记忆类证据复用 `.pastReflection` kind（`title: "长期记忆"`），未新增 CHECK 枚举值；memory evidence 的 `bookID` 复用当前 reflection，UI 不为无 locator 的记忆提供"回到原文"。
- 记忆匹配阈值放宽（≥2 tokens / 30% overlap vs reflection 的 40%），reflection 阈值不变。
- 跨书记忆检索：连接（`saveConnection`）仅用于 reflection；memory 只作为证据出现，不产生 `ReflectionConnection`。
- `SessionContextBuilderTests` 的旧断言 `readerAgentConnectsOnlySameBookPastReflections` 重写为 `readerAgentPrefersSameBookOverCrossBookPastReflections`（同书优先 > 跨书）。

### 基础设施注意（后续 worktree 复用）

- 新 worktree 首次 `swift test` 需代理环境变量（`HTTPS_PROXY/HTTP_PROXY/ALL_PROXY=http://127.0.0.1:7890`），SwiftPM 的 GRDB 子模块 clone 不走 git `http.proxy`；WS1 已设 `git config --global http.proxy` 缓解。

### Phase 4 门禁 ✅

- 全量 `swift test`：**149/149**。
- `xcodegen generate` + unsigned iOS Simulator `xcodebuild`：**BUILD SUCCEEDED**。
- 手工设备项待真机 gate：My Mind 记忆证据跳回原文、第 4 Tab 手势、跨书记忆提示。

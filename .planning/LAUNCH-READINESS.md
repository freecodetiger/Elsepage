# App Store 首发就绪清单（Launch Readiness）

> 建立：2026-10-09　分支：`release/app-store-readiness`
> 来源：2026-10-09 对照 `ReadLoop_PRD.md`（v0.3）的完成度调研 —— 五维度代码审计 + `swift test` 实跑
> 口径：`P0` = 阻断提审；`P1` = 首轮真机构建前应修；`P2` = 可延后到首发后
> 分工：`[Agent]` 可在代码/文档侧完成；`[用户]` 必须真机/账号/决策侧完成（见 AGENTS.md 验证分工）

## 0. 调研基线（2026-10-09）

| 项 | 值 |
|---|---|
| 包测试 | `swift test` **391 用例 / 15 套件全绿**，exit 0（本次实跑） |
| 源码 / 测试 | 218 个 Swift 文件 31.5k 行 / 66 个测试文件 11.0k 行 |
| DB 迁移 | v1 → **v29**（v26 已 `drop(table: "memories")`） |
| 模块 | 18 个（LibraryCore … BrainCore） |
| Commits | 408（8月 234 / 9月 167 / 10月 7） |
| ROADMAP | Phase 1–10 ✅、11 `1/2`、12–19 ✅ |
| 真机/TestFlight 证据 | **零** —— 无 fastlane、无截图目录、UAT 清单 0 勾选、`.planning/UAT-v0.5.md` 被引用但不存在 |

**总体判断**：代码侧已超过 PRD §18 的 1.0 首发标准（并额外完成 PRD 划给 v2 的 v1.1 Personal Brain），代码 ~92%、发布工程 ~25%。瓶颈不在代码，在「真实构建 → 真机 → TestFlight → 提交」这条从未跑通的链路。

---

## P0 — 阻断提审

- [ ] **补 `PrivacyInfo.xcprivacy`** `[Agent]`
      全仓 `find -name "*.xcprivacy"` 零命中。用到 UserDefaults / 文件时间戳等 required-reason API，苹果自 2024-05 起强制要求。与 `Data Not Collected` 申报配套。
- [ ] **定案 App 名称** `[用户]`
      PRD 头部：正式名待定（余思 / 页外）。`APP-STORE-METADATA.md` 中 App Name 仍为占位。App Store 必须有确定名称。
- [ ] **隐私政策填生效日期 + 联系邮箱，并托管到公网 URL** `[用户]`
      `docs/release/PRIVACY-POLICY.zh-Hans.md` / `.en.md` 正文已完成（100/99 行），但 `:5-6` 仍是 `[生效日期]` / `[联系邮箱]` 占位；文件头自述「上架前须完成」托管。
- [ ] **第一轮真机构建 + UAT 七节走查** `[用户]`
      `docs/release/UAT-CHECKLIST.md` 全部 `[ ]` 未勾。含崩溃恢复 6 项、Provider 矩阵、无 AI 完整可用路径、AX5/VoiceOver 过检。
- [ ] **TestFlight 跑通一轮** `[用户]`
      这是唯一能真正量化「还剩多远」的动作。跑完后本清单中所有「代码在但没验证」项会分化成「真的好了」和「真有问题」。ROADMAP Phase 11-02 亦为此项。

## P1 — 首轮构建前应修

- [ ] **F9 `whatIThink` 生产端缺失** `[Agent]`
      `Sources/ReflectionCore/JournalStructuredParser.swift:35,46` 解析 `whatIThink`，但 `Sources/ReaderAgent/ReaderAgentSystemPrompt.swift:544-566` 的输出策略只示范 `comment/connection/question/memory_proposals` —— 全仓无任何生产者要求模型产出该键。生产环境「这次留下 → 看法」大概率长期为空，`ThoughtRecordExtras` 是死路径。
- [x] **v26 删除 F10 五类分类学：写回 PRD §21** `[Agent]` —— 2026-10-09 完成
      PRD 升至 v0.4，新增 §21.12（F10 分类学退役 + userEdited 替代 + 回填保真度损失 + P7 未覆盖项）与 §21.13（v1.1 Personal Brain 里程碑）。§21 节首注明 §21.12–21.13 为追溯补录，不构成 §0 顺序约定豁免先例。剩余 P2 项「F10 userEdited 字段缺失」经复核已由 `origin == .userExplicit` + `brainItemRevisions` 覆盖，见 §0 备注。
- [ ] **`elsepageBrand` 零引用 / brand 与 interactive 同值** `[Agent]`
      `App/DesignSystem/ElsepageTheme.swift:95` 定义后全仓无引用；`Sources/AppInfrastructure/AccessibilitySupport.swift:116-124` 中两者颜色完全相同，且 `Tests/ReadLoopCoreTests/AccessibilitySupportTests.swift:33-52` 强制单色。正是 PRD §21.9 声明要修的「单一颜色承担品牌/交互/状态」问题。
- [x] **离线补发文案与实现不一致** `[Agent]` —— 2026-10-09 完成
      改文案而非改机制：`App/Reflection/SessionReflectionSheet.swift:956-957` 的 `.providerNotConfigured` 分支原写「网络恢复后，页外会继续回应」，但该失败只在 `models.makeClient()` 抛错时发出（`Sources/ReaderAgent/ReaderAgent.swift:208-211`），即**没有可用 Provider 配置**，与网络无关 —— 而这正是新用户「还没配 AI 就写了想法」的常见路径，属于事实性误导。现改为「配置好 AI 服务后，回到想法页就会继续回应」，与 `App/Thoughts/ThoughtsModel.swift:173` 既有措辞「AI 服务」一致。
      机制侧确认无需改动：懒补发（`App/Thoughts/ThoughtsModel.swift:95-112`）符合 PRD §14「离线产生的数据待未来联网后再处理，但不能阻塞用户阅读」，文案已指明续接位置。
      **未采纳的完整解**：重开一条缺回应的 Reflection 会话页时没有手动「重试回应」按钮（网络类失败的文案「现在网络不可用，表达仍已保存在本机。」本身诚实，不误导）。留作 P2。
- [x] **`requiresOnDeviceRecognition` 决策** `[Agent]` —— 2026-10-09 完成
      实测（五段真人素材，`docs/testing/voice/2026-10-09-transcription-measurement.md`）：端上 vs 服务端均值 CER 为 0.249 / 0.244（无偏置）、0.149 / 0.149（带偏置）—— 代价在这批素材上测不出来，且 `contextualStrings` 的收益在端上完整保留。**判定默认改为端上**，识别全程不出设备。
      连带结清两笔：隐私政策不需要新增外发披露（反而改成了更强的「不上传」声明），§21.1 那句「系统转写本地优先」从与实现不符变为成立。记录见 PRD §21.14、§21.1 更正项；`PRIVACY-CLAIMS-EVIDENCE.md` §4 已补证据行。
      回退策略（用户定案 A）：模型缺失时**明确报错并给出可行动路径**，不退回服务端。已知未消除风险：端上模型按需下载、触发下载通常依赖服务端识别，硬失败可能死锁；zh-CN 实测已存在，处置预案记在 PRD §21.14。
      界面处置：模型不可用时**不渲染麦克风**，原位留一句说明与可行动路径，每次打开界面重查（不缓存），模型装上后自动恢复；**不做**静默隐藏。规则单点化在 `SpeechRecognitionAvailability`，UI 与 provider 共用；识别期 1101 兜底由 `SpeechProviderError.from` 映射。
      机型实测（iOS 27.0 / iPhone18,3）：zh-CN 与 en-US 有端上模型、ja-JP 与 zh-TW 没有 —— 模型缺失是真实可达状态。`evaluate` 的模型缺失分支已通过 `/transcribe` 在设备上验证。
      **待用户真机验收（本机测不到）**：本机 zh-CN 模型存在，所以「麦克风被替换为说明文案」这个界面状态在本机**无法复现**。要验需一台未启用中文听写的设备（或在系统设置里移除中文听写包）；验收点是：麦克风不出现、说明文案可读、装回模型后重开界面即恢复。
- [ ] **`Reset Reader Profile` 无独立入口** `[Agent]`
      PRD §13.3 要求；现只能靠「清除全部记忆」连带清除（`App/MyMind/MyMindModel.swift:156-161`）。
- [ ] **App Store 元数据收尾** `[用户]`（文案可 `[Agent]` 起草）
      `docs/release/APP-STORE-METADATA.md`：Support URL、营销 URL、版权行未填；**6.9" 截图未制作**；§8 补齐清单 7 项全未勾。
- [ ] **App Review Notes 填充** `[用户]` + `[Agent]`
      `docs/release/APP-REVIEW-NOTES.md` 正文双语完整，但 `[APP_NAME]`、`[REVIEWER_DEMO_KEY]` 为占位；§三检查清单 7 项全 `☐`；要求用真实构建自测 BYOK 路径。
- [ ] **Provider 验证矩阵填写** `[用户]`（需真实 Key）
      `docs/providers/VERIFICATION-MATRIX.md` 3 行全「☐ 待填」。代码侧 OpenAI / Anthropic / Gemini / DeepSeek 均已实现，缺的是真机联调记录。

## P2 — 首发后可延

- [x] **缺手动「重试回应」入口** `[Agent]` —— 2026-10-09 完成
      `ReflectionConversationView` 在「已保存但尚无 Agent 回应」时显示「让页外回应」按钮，调用既有的 `requestAgentReply()`。判据是持久化状态（`messages` 中无 `.agent` 作者）而非内存中的 `agentNotice`，因此重开缺回应的记录同样可用 —— 这才是原缺口的主要场景（自动补发只在想法页加载时触发）。
      顺序不变量：`consume()` 的 `defer { isResponding = false }` 在末尾 `reloadMessages()` **之后**执行，故刚收到回应不会闪出按钮；首次加载期间由 `hasLoadedMessages` 兜住。两处均已在代码注释中写明，供后续修改者保持。
      **未加测试**：判据是 App 层布尔表达式，而 `swift test` 不编译 `App/`；为此把它抽成包内函数会是「只有一个内部调用者的抽象」。验证依靠 `swiftc -parse`（已过）+ 用户真机。
      **待用户真机确认**：按钮出现时机、44pt 点击区、失败后与「重新发送」并存的视觉。同时复验上一条改动 —— 未配 Provider 时提交应显示新文案并出现此按钮。
- [x] **同一记录并发发起首次回应会产生重复 Agent 回应** `[Agent]` —— 2026-10-09 完成（上一条改动的连带发现）
      管线里唯一的重入保护是「库里已有 Agent 消息就短路」，**只在回应落库之后生效**；两个调用方只要在落库前重叠，就各跑一次模型、各写一条回应。原有窗口很窄（保存流程撞想法页补发），但重试按钮把「关窗后立刻重开并点击」变成常见路径。
      修法：`ReaderAgent` 新增 `InFlightReplyRegistry` 按 reflectionID 仲裁——`AsyncStream` 的 build 闭包同步执行，认领在 `run` 返回前完成，故两个调用方不可能同时赢；后来者等待，若先前尝试未落库（即失败）则接管，避免点击变成静默空操作。只仲裁首次回应：`continueDiscussion` 已由稳定 messageID 保证幂等。仅动 `Sources/`，App 层无需改动——等待期间 `isResponding` 为真，按钮自然变回「页外正在理解你的表达…」。
      测试：`Tests/ReadLoopCoreTests/InFlightReplyTests.swift`（3 例）。**已验证有效性**：临时禁用认领后并发用例失败（2 次模型调用 / 2 条回应 / id 不同），恢复后 394 全绿。
      已知残余：两个等待者同时被唤醒时，只有一个能接管，另一个空手返回（`continuation.finish()` 无事件）；UI 表现为重新出现按钮。可接受，未处理。
- [ ] **F8 旧 Reflection 引用无法跳回证据源** `[Agent]`
      组装时 `locator: nil`（`Sources/ContextEngineering/ContextAssembler.swift:103`），UI 仅在 `locator != nil` 时给按钮（`App/Reflection/SessionReflectionSheet.swift:1492-1497`）。反向（记忆 → 证据）可用。
- [x] ~~**F10 `userEdited` 字段缺失**~~ —— 2026-10-09 复核后**撤销**：语义已由替代设计覆盖，非缺口
      `App/MyMind/MyMindModel.swift:137-149`：编辑时先用 `recordRevision` 存入改写前陈述，再把 `origin` 置为 `.userExplicit`、`state` 置为 `.active`。即「用户改过」可由 origin 与修订历史共同判定，且比原布尔字段多保留改写前原文。已在 PRD §21.12 记录。Journal 侧仍保有独立 `userEdited`（`Sources/ReflectionCore/Journal.swift:23`），两者语义不冲突。
- [ ] **P7「禁止某些内容进入长期记忆」未实现** `[Agent]`
      全仓 grep `optOut/doNotRemember/blocklist` 无命中。缓解：memory 默认 `needsReview` 待确认。
- [ ] **F11 Reader Profile 聚合实体缺失** `[Agent]`
      F11 的「准确/不准确/修改/忘记/查看依据」操作已实现但作用于单条 memory，非画像聚合。
- [ ] **§6.1 书架顶部 Next Action 卡片** `[Agent]`
      现退化为当前书卡上的「补写想法」按钮（`App/Library/LibraryGridView.swift:103-104`），无顶部卡片，也无「刚才读的，还没有留下想法」文案。
- [ ] **F4 Session Ending 三分支入口** `[Agent]`
      `[按住说] / [写一点] / [今天先不了]` 合并进单一编辑器（`App/Reflection/SessionReflectionSheet.swift:1062-1077`）。功能等价，UI 结构不同。
- [ ] **§12 预设模式下 Base URL 只读** `[Agent]`
      仅 `.custom` 时可编辑（`App/Settings/SettingsView.swift:137-147`），代理地址需先切「自定义」。
- [ ] **§13.2 用户可见的「本次上下文」逐项视图** `[Agent]`
      trace 已落库（`ContextPlanTrace.selectedBookEvidenceIDs`），但诊断屏只显示计数/回退（`App/Settings/SettingsView.swift:309-368`）。
- [ ] **EPUB 正文不随系统 Dynamic Type 缩放** `[Agent]`
      `App/Reader/ReadiumReaderView.swift:421` 走自研 fontSize 滑块，需用户手动调。PRD 未豁免。
- [ ] **Settings 中英混排无一致 gloss** `[Agent]`
      `Provider` / `Reflection` / `Agent` / `Embedding` / `Reranker` 残留；同页既有「反思」(`:451`) 又有「Reflection」(`:464`)。§21.9 允许保留技术原文但要求就地中文解释。
- [ ] **§11 无独立「欢迎」屏；Onboarding 未编排首次 Agent 反馈** `[Agent]`
      三步流程本身完整（`Sources/AppInfrastructure/OnboardingFlow.swift:5-17`），但 PRD 建议流程的「欢迎」首项与「Agent 第一次反馈」段未在此链路内编排。

---

## 已确认无问题（供复审时免检）

- **无自有后端**：全仓 `URLSession` 只在 `Sources/ModelProviders/`；唯一其他网络是 `App/Performance/DebugHTTPServer.swift` 的 `#if DEBUG` + `127.0.0.1:18765` 回环。
- **API Key 安全**：Keychain `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`（`Sources/ModelProviders/SecretStore.swift:54`）；DB 只存 `secretReference` 文本列；`Sources/ModelProviders` + `AgentRuntime` + `BenchCore` 中 `print/os_log/Logger/NSLog` 零命中。
- **依赖面干净**：仅 GRDB 7.11.1 + Readium 3.11.0，无统计/遥测/崩溃 SDK。
- **数据控制**：Export / Delete Book & Index / Delete Memory / Delete All Local Data 均已实现且带级联（`App/Settings/DataSettingsModel.swift`、`Sources/Persistence/LocalDataWipeService.swift`）。
- **F1/F2/F3/F5/F6/F7/F12/F13**：实现完整，多处超 PRD 要求（4 阅读主题、5 色高亮、音频波形 seek、80–220 字长度硬约束、6 项成就全接线）。
- **无 `TODO`/`FIXME` 遗留标记**（`App/` + `Sources/`）。

## 备注

- 本清单为一次性调研产物，与 GSD 的 `.planning/ROADMAP.md` 相位体系并行；P1 项若要进入正式执行，建议按 `docs/exec-plans/active/` 的格式各起一份 exec plan。
- 若需隔离开发环境，可改用 worktree（约定见 `.planning/WORKTREES.md`）：`git worktree add ../elsepage-worktrees/release-readiness -b release/app-store-readiness main`。
- 本文件与 PRD v0.4 的 §21 补录随 `release/app-store-readiness` 分支提交；勾选进度就地更新。

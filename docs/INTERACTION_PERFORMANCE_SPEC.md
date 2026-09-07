# 客户端交互性能与渲染架构 Spec（供后续开发阶段参考）

> 状态：**方向已定案（2026-09-05）；尚未进入实现**
> 定案：执行定位 = 转 active 执行计划 + ADR 按阶段推进；工作包 A 迁移面 = **最小面（会话 + 档案正文）**；工作包 B = **去抖合并解析（纯增量留二期）**；基线来源 = **近期可提供真机配合采基线**（R3/R4 尽早闭合）。配套 `docs/adr/0002-client-interaction-performance.md` 与 `docs/exec-plans/active/client-interaction-performance.md`。
> 更新日期：2026-09-05
> 适用范围：iPhone/iPad 客户端；Reader 打开、会话与时间线的正文渲染、文本选区、键盘交互、Agent 流式输出
> 前置阅读：`ReadLoop_PRD.md`、`ReadLoop_Technical_Design.md`、`docs/READER_EXPERIENCE_OPTIMIZATION_PLAN.md`
> 证据基线：文中所有 `path:line` 均为调研时的源码位置；结论分「**已证**（据代码可直接判断）」「**待验证**（需 Instruments/真机确认，通常用 ⚠️ 标注）」。

---

## 0. 摘要（TL;DR）

用户报告的卡顿集中在三处：**首次打开阅读器**、**首次唤起输入法**、**会话里长按做跨行文本选区**。三处不是三个独立 bug，而是同一组结构性原因的三种表现：

1. **正文排版在主线程上"整串重算、且不缓存"** —— 每个 Agent 消息是一个自报高度的 UIKit `UITextView`，`intrinsicContentSize` 每次被查询都对**整段文本**做 `boundingRect` 量高；流式输出时每个 text delta 又对**整串**重跑 Markdown 解析 + 重建富文本 + 整串重测。单条长回复近似 O(n²)，全部发生在主 actor。
2. **首帧前串行执行了大量可后置的工作** —— 阅读器把 `open(EPUB)`、DB 四连查、highlights/notes 加载全部排在 `isPrepared` 一个门闩后，navigator 真正出第一页之前没有任何就绪信号或盖板。
3. **可观测性空白** —— 全仓无一处 `os_signpost`/MetricKit，也没有 UI 性能测试 target。于是"卡不卡"长期停留在感觉层面，无法回归。

本 spec 定义六个工作包：**A 文本/测量子系统**、**B 流式增量解析**、**C 阅读器打开管线**、**D 键盘/聚焦滚动策略**、**E 主 actor 并发接缝**、**F 性能回归护栏**。A、C 直接命中前两个卡点，B 命中流式 stutter（与选区共因），D 命中键盘与选区附近的整树重排，F 从第一天就埋点，E 是长期平滑度底座。

**执行顺序建议：先 F 埋点（基线）→ A → B → C → D，E 贯穿收敛。** 理由：F 不先做，A/B/C/D 的收益无法量化、也无法防退化。

---

## 1. 现状：架构定性

### 1.1 架构模式

SwiftUI + Observation（`@MainActor @Observable final class XxxModel`）+ 下层 protocol/service/repository 分层。`AppModel.start()`（`App/AppModel.swift:40`）做组合根，一次性注入 `LibraryModel`/`ThoughtsModel`/`MyMindModel`/`SettingsRootModel`；`AppShell`（`App/AppShell.swift:15`）持 TabView，Reader 以 `fullScreenCover` 呈现。

- 不是 MVC：无 Controller 层。
- 是 **MVVM 的 SwiftUI 变体**，且是"厚 VM"：Model 既当 ViewModel（`searchQuery`/`preferences` 等 UI 状态）又当功能协调者（`SessionReflectionModel` 内部是一台提交状态机 + 会话）。
- 判定：**模式本身不是瓶颈，不构成重构理由。** 真正的结构问题是"可观察对象全部钉主 actor + 排版/解析/首帧编排没有离主或缓存"，见下。

### 1.2 已经不在主线程上的（别动，也别误伤）

| 事项 | 证据 | 结论 |
|---|---|---|
| GRDB 读写 | 全仓仓库方法全部 `await db.writer.read/write`（异步重载，闭包跑在 GRDB 私有串行队列）；`AppDatabase` 持 `DatabaseQueue`（`Sources/Persistence/AppDatabase.swift:6-23`） | 主 actor 只做续体，**不阻塞** |
| Agent 流式产出端 | `ReaderAgent.respond` 返回 `AsyncStream<ReaderAgentEvent>`，内部 `Task` 建在非隔离 async 方法（`Sources/ReaderAgent/ReaderAgent.swift:128-148`），`AgentExecutor` 再开一层 `Task` + 流（`Sources/AgentRuntime/AgentExecutor.swift:13-67`） | 生成端在后台 executor，主 actor 只 `for await` 消费 |

**⚠️ 例外（主线程同步碰 DB）：冷启动迁移。** `AppDatabase.init` 内同步 `migrator.migrate(writer)`（`AppDatabase.swift:10`），在 `@MainActor AppModel.start`（`App/AppModel.swift:46`）触发 v1–v25 全量迁移。与三卡点无关，但归入工作包 E（低优先级）。

### 1.3 三个卡点与根因的对照

| 卡点 | 主因（已证） | 次要/共因 |
|---|---|---|
| 首次打开阅读器 | 首帧前串行做大量可后置工作 + Publication 每次重解析 + 无"真出页"就绪盖板 | WKWebView/WebKit、GCDWebServer（首次 serve）进程内冷启动 |
| 首次唤起输入法 | 系统键盘/IME 冷启动占大头（App 侧难消除） | 自动聚焦 sheet 打开即聚焦、聚焦事件对整树 `withAnimation` 滚动、non-lazy 容器随 safe-area 变化全体重新布局 |
| 会话长按跨行选区 | 每条消息 = 常驻 `FitTextView`，选区/手柄触发整树 re-layout 时逐个**整串 boundingRect 重测**；首次选区形成时 `becomeFirstResponder` 冷启动 UIKit 选中 UI | 与 B（流式）共用"整串重算"根因 |

三处背后同一句话：**排版与布局在主线程做，且不做缓存/增量；首帧与手势让位于可以提前完成或延后结算的工作。**

---

## 2. 目标 / 非目标 / 设计原则

### 2.1 目标（能验收的）

- T1 首次打开一本书：从点击到正文可交互（首个 `locationDidChange`），主线程无超过预算的连续阻塞段；第二本/再开同一本显著快于第一次（缓存命中）。
- T2 流式 Agent 回复期间：UI 不因 delta 出现掉帧；单条长回复总解析成本从近似 O(n²) 降到可控（见 B 验收）。
- T3 会话/时间线长按选区与拖动手柄：不因测量触发卡顿；同屏常驻文本测量实例收敛。
- T4 键盘首次唤起：App 侧在键盘弹窗期间不抢主线程（safe-area 变化不触发整树重测）。
- T5 以上全部可被 signpost/度量复现与回归（不是体感）。

### 2.2 非目标（即便"不计成本"也不做，见 0.1 判断）

- 不做 MVVM→其他模式的架构替换，不引入 TCA/Redux 类状态库。
- 不把 SwiftUI 正体重写为 UIKit。
- 不把所有"厚 Model"拆成瘦 VM + Coordinator ceremony（可读性投资，不是卡顿解药；仅当 F 基线证明某 model 是热路径才按需切）。
- 不把会话列表贸然改写成 `UICollectionView` 级复用（对话长度有限；先做 A 的测量缓存，若基线证明视图数才是瓶颈再谈复用）。
- 不为每层加协议抽象或拆包；198 文件的单体对单用户本地优先产品是合理复杂度。
- 不动 UI 语义与交互规格（选区工具条、高亮菜单等已由 `docs/READER_EXPERIENCE_OPTIMIZATION_PLAN.md` 锁定）。

### 2.3 设计原则

- **P1 先呈现、后落账**：首帧永远不等可提前做的工作；可延后的查询/解析/落库一律排在用户可见首帧之后，用盖板/占位承接。
- **P2 排版不进 UI 层**：正文一律走统一文本组件；测量与富文本构建做缓存，绝不"每次 layout 问一次就整串量一次"。
- **P3 主线程红线**：主 actor 只做"必须当场"的状态变更与 UIKit 交互；纯推导/解析/IO 在别处做或先缓存。可观察对象的最小失效面优先（别让一个 delta 触发整树 body）。
- **P4 无度量不优化**：任何性能改动先落 signpost/计数，改前改后都有一条能复现的曲线。
- **P5 手势与动画不和首帧抢道**：键盘弹窗、选区手柄、sheet 呈现期间，不触发整树 `withAnimation` 滚动或全体重测。

---

## 3. 工作包 A：文本/测量子系统（Text Measurement）

> 命中：卡点 3（选区）、流式 stutter、键盘 safe-area 整树重测；是所有正文面的公共底座。

### 3.1 现状与代价（已证）

- 只读可选中正文 = 一个自报高度的 `FitTextView`（`App/DesignSystem/SelectableText.swift:150-184`）：
  - `intrinsicContentSize` **每次被查询**都对 `attributedText` 做 `boundingRect(.usesLineFragmentOrigin, .usesFontLeading)`（`:159-168`）——O(文本长度)。
  - `layoutSubviews` 检测宽度变化后 `invalidateIntrinsicContentSize()`（`:170-177`）——宽度一变，重测。
  - `updateUIView` 里 `attributedText != attributedText` 做整串内容比较（`:32`）。
- 装配面（用户正文的全部调用点）：
  - `ReflectionConversationView`（会话正文）：`ScrollView { VStack }`，**非 Lazy**（`App/Reflection/SessionReflectionSheet.swift:1077-1079`）。Agent 消息 → `AgentMarkdownText`（`:1100`）、用户/跟进消息 → `SelectableTextBody`（`:1106,:1135`）、流式中 → `AgentMarkdownText(model.streamingResponse)`（`:1140`）。**N 条消息 ≈ N 个 FitTextView 常驻**，首帧与每次宽度变化逐个量高。
  - `ThoughtsView` 档案（`App/Thoughts/ThoughtsView.swift:120-121`）：外层 LazyVStack，但**懒粒度是"月/书 section"而非单卡**（`:187-274`），一个 section 内的卡 + 展开块同时 alive；展开块内含 Agent/用户消息正文（`:429/:436`、`:471`）。
  - Journal 卡在 LazyVStack（`ThoughtsView.swift:215-228`），收起/展开即建毁正文块。
  - MyMind/Today 的正文多为普通 `Text` + `.textSelection(.enabled)`（不走 FitTextView；选区只有系统菜单，无手柄），**本次不纳入 A 的迁移**，只保留对测量原则的遵守。
- 富文本构建：`AgentMarkdownText.attributedContent`（`App/DesignSystem/AgentMarkdownText.swift:48-58`）每次 body 求值都对整串 `AttributedString(markdown:.full)` 重解析，随即 `makeSelectableMarkdown`（`SelectableText.swift:89-113`）逐 run 重建 `NSAttributedString`。
- **死路径提醒**：`BrainDiscussionSheet`（`App/MyMind/MyMindView.swift:1069-1163`）当前无展示点（不可达），但它自己持 `@State reply` + `Text(reply).textSelection(.enabled)`，**不经过 A/B 的任何组件**——重构时不要把它误当迁移对象，也不要在它身上重复投入。

### 3.2 目标形态

收敛为 DesignSystem 的一个正式组件族，UI 层不再碰排版细节：

```
MessageText                       // SwiftUI 门面：宽度=提案，高度=查缓存
├── content: MessageTextContent   // .plain(String) | .markdown(String, citations:[URL 改写])
├── style: TextStyleKey            // 字体样式 + 明/次色 + 行距
├── selectable: Bool
└── 内部：
    ├── RichTextBuilder            // 结构解析（markdown→AttributedString）一次缓存
    └── TextMeasureCache           // 高度：key→测量值，永不在 intrinsic 里现算
```

- 替换面：`ThoughtsView` / `SessionReflectionSheet`（会话）里的 `AgentMarkdownText` 与 `SelectableTextBody` 全部改为 `MessageText`；`AgentMarkdownText`/`SelectableTextBody` 变为薄壳或删除。
- 只读 UIKit 桥（`FitTextView`）保留作"可选中 + 手柄"的唯一实现，但**测量改为查表**（A3）。

### 3.3 TextMeasureCache 规格

- **职责**：回答"给定富文本 + 可用宽度 → 高度"。只允许真正需要时测量一次。
- **键**：`(textKey, widthBucket, styleKey, contentSizeCategory)`。
  - `textKey` = 富文本内容摘要（AttributedString 的 stable hash，或原始串+样式令牌），用于内容不变时命中。
  - `widthBucket` = 宽度量化到 8pt 的桶（避免同一文本在不同提案宽度上反复量）。
  - `contentSizeCategory` = Dynamic Type 档位（字体缩放改变测量结果）。
- **存**：两层。① 组件级 memo（`@State`/Coordinator 持有 `last(textKey,widthBucket)→height`），覆盖生命周期内反复 layout；② 进程级 LRU（容量≈ 200 项，超过逐出）供会话/档案跨宽度复用。线程：只在主 actor 读写，非并发结构。
- **失效**：内容变、宽度越过桶界、Dynamic Type 变化才重测；safe-area/keyboard inset 变化**不**失效（宽度不变 → 命中缓存），这是 D 能成立的前提。
- **测量函数**：保持 `boundingRect` 语义（换行/字形占位与现有一致，避免文本视觉回归），但只对缓存缺失执行。后续若基线证明单条极长文本（>数 KB）单次量高仍是瓶颈，再评估用 `NSLayoutManager` 增量排版——**默认不做，YAGNI**。

### 3.4 RichTextBuilder 规格（富文本构建缓存）

- 把 markdown **结构解析**（`AttributedString(markdown:)`，含 citation 链接改写）与**样式落字**（`makeSelectableMarkdown` 逐 run 生成 font/color）拆开：
  - 结构解析结果（`AttributedString`）按 `(原文, 解析选项)` 缓存；Dynamic Type 变化时**不重解析**，只按当前 `preferredFont` 重跑样式落字（逐 run 应用 trait 很快）。
  - 样式令牌（textStyle + 明/次色）参与"是否需重建 NSAttributedString"的判断。
- 目的：把 A 从"每 layout 整串量一次 + 每 delta 整串解析一次"降到"结构与测量各做一次、之后全部命中缓存"。

### 3.5 迁移清单（A）

| 现状调用点 | 改为 |
|---|---|
| `AgentMarkdownText`（`AgentMarkdownText.swift:18`，被 `ThoughtsView.swift:429,471` 与 `SessionReflectionSheet.swift:1100,1141` 用） | `MessageText(.markdown)` |
| `SelectableTextBody`（`SelectableText.swift:64`，`ThoughtsView.swift:436`、`SessionReflectionSheet.swift:1106,1135,1236`） | `MessageText(.plain)` |
| 流式中 `AgentMarkdownText(model.streamingResponse)`（`SessionReflectionSheet.swift:1140`） | `MessageText(.markdown)` + B 的增量缓冲 |
| 编辑框 `ReflectionUIKitTextView` / `ReflectionUITextView`（`SessionReflectionSheet.swift:238/197`，composer `:1318` 与撰写框 `:956`） | **不并入 MessageText**（可编辑是另一职责）。但对其"高度延迟回写 + 二次量高"（`:376-396`）按 P1 微调：聚焦时跳过无谓重测（见 D） |

**不做**：把 `JournalEntryCard`/`ThoughtEntryCard` 里仅做系统菜单的普通 `Text.textSelection` 也迁进 MessageText（无手柄需求，保持普通 Text，省一层 UIKit 桥）。

### 3.6 验收（A）

- 同屏/同会话常驻 FitTextView 数量：非懒会话 N 条消息 = N（允许），但**任一实例的 intrinsic 查询零完整 `boundingRect` 重测**（除缓存缺失）。
- signpost：单次 textMeasure 事件耗时分布中位数与 p95 记录；同一消息在滚动/宽度变化后的重测次数 = 缓存设计上限。
- 视觉零回归：相同内容/样式/宽度下，新旧测量结果差 ≤ 1pt（用 Golden 或逐字符对比测，并入现有测试体系）。

---

## 4. 工作包 B：流式增量输出

> 命中：会话 Agent 回复期间的 stutter（与 A 共因）；A 解决"测量重算"，B 解决"每 delta 整串重解析 + 整串重建富文本"。

### 4.1 现状（已证）

- 链路：`ReaderAgent.respond` → `for await event`（消费端在 `@MainActor ReflectionConversationModel`，`SessionReflectionSheet.swift:628,776-820`）→ `.textDelta` 分支 `streamingResponse = Self.withoutCitationBlock(streamingResponse + text)`（`:797-798`）→ body 读 `model.streamingResponse`（`:1140`）→ `AgentMarkdownText` 整串重解析（`AgentMarkdownText.swift:48-58`）→ 整串重建 NSAttributedString（`SelectableText.swift:89-113`）→ `updateUIView` 换 `attributedText` + 失效 intrinsic → 整串重测。
- 每 delta 成本 = 整串 markdown 解析 + 整串富文本重建 + 整串重测 ≈ **O(n)**，累计到完成 ≈ **O(n²)**（n = 该条回复累计长度）。模型厂商通常按 token 分块 yield，频率≈每 token。
- 唯一例外：`TranscriptPolishService` **不流式**（收满一次性返回，`Sources/AgentRuntime/TranscriptPolishService.swift:14-32`），MyMind 讨论面也不经 A/B 组件——这两条路径本次不动。

### 4.2 目标：把"整串"改成"增量 + 去抖"

按 P1/P3，**首选去抖合并解析**（低风险、直达标），纯增量文本流作为二期（当基线证明长回复仍差一截时）：

- **去抖合并**：`ReflectionConversationModel.consume` 收到 textDelta 时不立即触发 body；累计进一个缓冲，用约 50ms 的 merge 窗口（或"收到 delta 后下一次 runloop + 追加阈值"）合并成"可见文本"。最终渲染对象是**去抖后的整串**（每 ~50ms 至多一次整串解析+重测）。把每 token 一次 O(n) 降到 ~20 次/秒的 O(n)——累计从 O(n²)/token 降到可接受。
- **不剥 citation 块则不进渲染**：继续用 `withoutCitationBlock`（`:797-798`）语义对**去抖后的串**执行一次（避免每 delta 剥一次）。
- **完成即切换**：`.completed` 清空 `streamingResponse` 换持久化消息的现有逻辑（`:803-816`）保留，保证清空与滚动锚点行为不变。
- **增量缓冲（二期，仅当基线要求）**：按块边界切"已稳定前缀"，只对新增量做 markdown 解析后拼接富文本段；注意 markdown 块可能跨 delta（一段加粗的开标签与闭标签在不同 chunk），因此"稳定前缀"判定必须在出现块结束边界/足够延迟后才推进，否则退化为全量。**复杂度高、默认不做**，A 的缓存已能吸收大部分收益。

### 4.3 验收（B）

- 流式期间主线程 signpost：单 delta 处理耗时（收到→视图提交）均值与 p95 有界，不随回复长度线性增长。
- UI 手感：流式整条长回复过程中无可见掉帧（配合 XCUITest/F 的采样）。
- 行为等价：去抖后最终呈现文本与现有逐 delta 呈现**字节一致**；`withoutCitationBlock` 语义、`.completed` 清空、自动滚动锚点（`SessionReflectionSheet.swift:1198-1200`）不受影响。

---

## 5. 工作包 C：阅读器打开管线

> 命中：卡点 1（首次打开阅读器）。这是三条卡点里唯一一个"纯编排可救"的——不改 UI 语义、不碰 Readium 渲染内核，只重排"谁先谁后、何时揭盖、如何缓存"。

### 5.1 现状（已证）

- 打开顺序：点击书 → `AppShell` 以 `fullScreenCover` 呈现 `ReaderScreen`（`App/AppShell.swift:42-48`，`ReaderScreen` 在 `App/Reader/ReaderScreen.swift`）→ body 以 `model.isPrepared` 门闩：false 显示 spinner（`:29-40`）→ `.task { await model.prepare() }`（`:54`）→ `prepare()` 串行 DB 四连查 + markOpened（`ReaderModel.swift:128-152`）→ `isPrepared=true` → 挂载 `ReadiumReaderView` → `Coordinator.open`（`ReadiumReaderView.swift:39-107`）在 @MainActor Task 内 `await readium.open` 再同步构造 `EPUBNavigatorViewController`。
- **首帧硬依赖 vs 可后置**（读 `ReadiumReaderView.swift:44-98` 与 Readium 源码）：

| 数据 | 何时需要 | 判定 |
|---|---|---|
| position（resume 位置） | `initialLocation`（`ReadiumReaderView.swift:52-58`） | **硬依赖**（决定开书落点） |
| preferences | navigator 初始 config 必填（字号/主题/scroll…） | **硬依赖** |
| highlights | `applyHighlights` 需 navigator 已挂载；Readium `apply(decorations:)` 晚到安全（spread 未加载会 guard 跳过并随后重放） | **可后置** |
| notes | 只进标注 sheet（`ReaderScreen.swift:349-367`） | **无关首帧** |
| markOpened | 只影响书架排序 | **无关首帧** |
| chapters（manifest） | `Self.chapters(from:)`（`ReadiumReaderView.swift:51`） | 不依赖 DB，随 open 即可 |

- **Publication 零缓存**：`ReadiumServices.open`（`App/Reader/ReadiumServices.swift:28-32`）每次 `retrieve + publicationOpener.open`；消费方除阅读器外还有元数据读取（`App/Library/ReadiumMetadataReader.swift:11,23`，同书导入时两次独立 open）与建索引（`App/Reader/ReadiumBookIndexer.swift:146`）。
- **无"首帧就绪"公开回调**（Readium 源码：`RT/Navigator/…`）：
  - `NavigatorDelegate` 仅 `locationDidChange`/`didJumpTo`/`presentError`/`didFailToLoadResourceAt`/…；`VisualNavigatorDelegate` 有 `presentationDidChange`；`EPUBNavigatorDelegate` 只加 `setupUserScripts`。**没有 didFinishLoading/isReady**。
  - 最可靠就绪信号 = **首次 `locationDidChange`**：它在"当前 spread 已加载、能算出位置"之后触发（`PaginationView.loadPages` → spread 就绪 → `updateCurrentLocation` → delegate）；App 在加 view 前已设 delegate（`ReadiumReaderView.swift:77-88`），不会漏首次。
  - 失败反向信号：`didFailToLoadResourceAt` / `presentError`（可作揭盖 + 报错出口）。
- **⚠️ 主执行器负担**：从 @MainActor Task 内 `await` 的非隔离 async（Readium streamer/shared 解析路径源码未见 `Task.detached`/全局队列跳转），其同步段跑在主执行器。EPUB 嗅探/解包/OPF+NCX 解析/positions 计算与首个 spread 的 WKWebView 创建都在主线程 CPU 段。**据源码判断，掉帧量级待 Instruments 证实。**
- **进程内冷启动**：GCDWebServer 惰性启动，首次 `serve` 在 `EPUBNavigatorViewController` 构造期（`RT/.../GCDHTTPServer.swift:189-201`）；WKWebView 不在 navigator init 同步创建，而在异步 initialize → pagination → 首个 spread 创建。webview/WebKit 进程冷启动叠加在首次打开。
- **销毁/复开**：`dismantle` → `cancelOpening`（`ReadiumReaderView.swift:23-26,109-113`）；navigator/Publication 随 fullScreenCover 关闭释放；httpServer 是 AppModel 级共享、**不随退出 stop**（只 remove 本 navigator 端点）。复开 = 新建 ReaderModel → 重跑 DB → 重解析 Publication → 新建 webview，全流程重来。

### 5.2 目标时序（C）

```
用户点书
  ├─ (立即) fullScreenCover 呈现 ReaderScreen，chrome 先出，内容区盖板「正在打开…」
  ├─ async let A = readium.open(fileURL)      // Publication（含 chapters/manifest）
  ├─ async let B = 只取 position + preferences // 移出 highlights/notes/markOpened
  ├─ 二者就绪 → 主 actor 构造 EPUBNavigatorViewController(initialLocation: A.positionLocator, config.preferences: B.preferences)
  ├─ 挂载 navigator、加 subview、apply(preferences)
  ├─ 盖板保持 → 直到 首次 locationDidChange 触发 → 揭盖（淡入）
  ├─ 揭盖后并行：applyHighlights(model.highlights)   // 延后、安全
  │              fetch notes；markOpened              // 异步落库，不阻塞
  └─ 失败分支：didFailToLoadResourceAt/presentError → 揭盖 + 报错 + 可重试
```

要点：

1. **门闩从 `isPrepared`（四连查全完）改成"open ∥ position+preferences 就绪"**：DB 里只有两项是硬依赖，highlights/notes/markOpened 全部移出首帧。
2. **就绪信号用首次 `locationDidChange`**（源码级最贴"真出页"且现有代码已依赖它）。摘盖后才有内容，盖板期间主线程即使有 CPU 段，用户看到的是"打开中"而非假死。
3. **开书请求可取消**：转屏/切后台/立刻返回时不把 `open` 或 navigator 初始化挂进僵尸 Task；沿用 `cancelOpening` 语义并覆盖新 async let。

### 5.3 Publication 缓存 + 后台预取（C）

- **键与失效**：`ReadiumServices` 增加 `cache: [BookID/文件URL : Publication]`（或按文件修改指纹），配 LRU（建议容量≈最近 N=3~5 本，含当前在读）。书籍被删除/替换（导入去重、`BookFileStore` 变更）时逐出。
- **预取时机**：① 一本书建索引完成时（`BookIndexCoordinator.enqueue` 后置成功，`ReadiumBookIndexer.swift` 侧）后台预热 open；② 从书架/会话回到 `Today`/`Library` 空闲时，预取最近打开的书；③ 阅读器内跳转/翻页无需预取（Publication 已在手）。
- **注意**：预取只做"解析成本"缓存；`EPUBNavigatorViewController`/WKWebView 每次打开仍需新建（不能跨打开复用，UIViewController 生命周期不允许）。缓存收益在：省掉每次重解析的 CPU + IO，使"第二本/复开"明显更快。
- **线程安全**：Publication 跨打开缓存意味着同一实例可能被并发持有。落地前先验证 `Publication`/`Asset` 的 `Sendable`/并发语义（见 §10 风险 R1）。若不满足，降级为"仅缓存解析产物/惰性条目"，预取排队在主 actor 侧串行执行。

### 5.4 可选实验：解析移出主执行器（C）

仅当 5.1 的 ⚠️ 基线证明主线程 CPU 段是首开主要成本且 5.3 缓存不足以覆盖"首次任意书"时执行：

- 把 `open()` 放到**非主 actor 的 Task**（如 `Task.detached` 或非隔离 async helper）里执行，解析完成后回到主 actor 构造 navigator。
- **前置条件**：验证解析产物跨线程迁移安全（R1）。Readium `Publication` 若不可 Sendable，则此路不通——宁可保持主执行器解析 + 盖板兜底，也不要在线程安全上赌。

### 5.5 验收（C）

- signpost：`readerOpen`（点书 → 首次 `locationDidChange`）中位数/p95；拆两段：`open(parse)`、`navigator→firstPage`，各自主线程连续 CPU 时长。
- 缓存命中：同进程内复开同一本，`open(parse)` 段不再出现（或显著下降）。
- 行为等价：resume 位置、首屏偏好、既有 highlights 呈现、标注 sheet 的 notes 完整，均与现状一致（对照现有测试 + 真机清单）。
- 无假死：盖板存在期间即使主线程有 CPU 段，不出现"白屏无反馈"。

---

## 6. 工作包 D：键盘 / 聚焦 / 滚动策略

> 命中：卡点 2（首次唤起输入法）的 App 侧可消部分，以及选区/输入附近的整树重排。

### 6.1 现状（已证）

- **自动聚焦只有两处**（都出现在 sheet 里，`onAppear` 即聚焦）：
  - `JournalThoughtEditor`（`App/Thoughts/JournalEntryCard.swift:289,311-312,319-322`）。
  - Reader `NoteEditor`（`App/Reader/AnnotationUI.swift:409,454,463-468`）。
- Reflection 撰写框与对话 composer **都是用户主动点击**才聚焦（`SessionReflectionSheet.swift:956/:1318`，无自动聚焦，`isComposerFocused` 初始 false `:1074`）。MyMind 各输入框也无自动聚焦。
- 对话 composer 聚焦时会触发：`becomeFirstResponder`（`SessionReflectionSheet.swift:294-295`）→ `.onChange(isComposerFocused)` 对**整棵 ScrollView** 做 `withAnimation(.snappy)` + `scrollTo bottom`（`:1181-1187`）→ safe-area 变化 → non-lazy `ScrollView{VStack}`（`:1077-1078`）内所有消息随布局整树重排。若 A 未落地，每条消息都会重测（共因已由 A 解决）；A 落地后剩下的主要是"整树动画滚动 + safe-area 重排"的系统开销。
- 键盘**首次**唤起中，系统键盘/IME 冷启动是主要成本（非 App 可控）。App 侧目标：在键盘弹窗期间不主动增加主线程负担。

### 6.2 目标

- **聚焦与滚动解耦**：滚动由**键盘 frame** 驱动（`UIResponder.keyboardWillShowNotification` 的 frame → 计算需要露出的是 composer/caret 区域，只滚动必要的量），而不是"聚焦事件对整树 withAnimation scrollTo"。
- 保留 `.scrollDismissesKeyboard(.interactively)`（`SessionReflectionSheet.swift:1178`）与 `defaultScrollAnchor(.bottom)`（`:1179`），行为不变。
- **自动聚焦 sheet 的节奏（P1）**：sheet 先完成呈现（呈现完成/下一个 runloop/短暂 sleep），再设置 `editorFocused = true`；避免"sheet 呈现动画 + 键盘冷启动 + 立即聚焦"三者同帧竞争。两处（`JournalThoughtEditor`、`NoteEditor`）统一此节奏；若用户体验证明 0 延迟更顺，保留 0 延迟但**不触发整树动画**。
- 键盘安全区变化与 A 协同：safe-area/keyboard inset 变化**不**使测量缓存失效（A3 已定义），这是"键盘弹出不重测"的结构保证。

### 6.3 验收（D）

- 键盘从按下输入框到 `keyboardDidShow`：App 侧无 ≥ 阈值的连续主线程阻塞（系统冷启动除外，用 signpost 分开计量）。
- 聚焦键盘时：无整树 `withAnimation` 滚动（改为 keyboard-frame 驱动的小范围滚动），无因 safe-area 变化触发的整串重测（A 缓存命中断言）。
- 两处自动聚焦 sheet：呈现与聚焦不再同帧抢占。

---

## 7. 工作包 E：主 actor 并发接缝（红线清单）

> 命中：长期平滑度；不是三卡点的直接解药，但 A/B/C 若无它约束会随时退化回去。

### 7.1 现状清单（已证 / ⚠️ 待验证）

| 事项 | 位置 | 主 actor 负担 | 处置 |
|---|---|---|---|
| GRDB 读写 | 全仓库 | 无（异步重载离主） | 保持 |
| Agent 产出端 | `ReaderAgent.swift`/`AgentExecutor.swift` | 无（后台） | 保持 |
| **流式消费端（去抖前）** | `SessionReflectionSheet.swift:797` + `AgentMarkdownText.swift:48` | 每 delta 整串解析/重建 | 归 B |
| **正文测量** | `SelectableText.swift:159` | 每 layout 整串量高 | 归 A |
| **Readium open/navigator 编排** | `ReadiumReaderView.swift:39-107` | ⚠️ 主执行器 CPU 段 | 归 C（缓存/盖板；离主见 R1） |
| **冷启动 DB 迁移** | `AppDatabase.swift:10` + `AppModel.swift:46` | 主线程同步迁移 | 本包处理（P2） |
| 视图层聚合流式（MyMind） | `MyMindView.swift:1144-1156` | `@State reply += delta` 每 delta 重渲 | 本次不动（死路径）；若启用再按 B 处理 |

### 7.2 红线规则（写进 PRD/工程约束，后续所有 Model/View 遵守）

1. `@MainActor @Observable` Model **不得**包含超过几 ms 的同步 CPU 段；纯推导/解析放后台或用缓存。
2. 可观察属性**最小失效面**：一个 `textDelta` 只允许使"读该字段的视图"失效，禁止连锁失效到整树（`@Observable` 逐属性追踪，代码上要避免在 body 顶层读宽泛状态）。
3. 首帧门闩只放**硬依赖**；可后置的查询一律揭盖后再做（P1）。
4. UIKit 桥（UIViewRepresentable）的测量/同步逻辑不得在 `updateUIView`/`intrinsicContentSize` 里做 O(n) 全量工作（P2）。
5. 任何新"整串 x 每事件 y"的循环模式出现即违反规则（评审拦）。

### 7.3 冷启动迁移离主（P2）

- `AppModel.start` 目前 `AppDatabase(path:)` 同步跑 v1–v25 迁移（`App/AppModel.swift:46`）。处置：迁移放到启动后台任务（`Task.detached` 或非 MainActor 上下文），UI 先出 launch/骨架，迁移完成后再接续 `library.reload` 等。迁移读写都在 GRDB 队列/独立上下文执行，完成态回主 actor。
- 与三卡点无直接关系，作为独立低优先级项进入 backlog；**先由 F 基线的启动段度量决定是否本轮做**。

### 7.4 验收（E）

- 红线以代码评审规则落库；新增正文渲染路径在 review 时按 §7.2 五条过一遍。
- 冷启动迁移若本轮做：启动到可交互（Today 首帧）的主线程阻塞段降到迁移后台化后的预算内。

---

## 8. 工作包 F：性能回归护栏

> 现状（已证）：全仓 **零 os_signpost/MetricKit**；`DiagnosticsModel`（`App/Settings/DiagnosticsModel.swift:10-25`）只是 routingTrace 的结构化 duration 落库聚合（`App/Settings/SettingsView.swift:281`），非实时；Xcode 工程仅 app + 两个 unit target（`project.yml`，无 `bundle.ui-testing`）；`BenchCore` 纯 CLI、不依赖 App，测不了 SwiftUI（`Package.swift`）。F 全从零建。

### 8.1 里程碑指标定义

| 指标 | 起止 | 采集点 |
|---|---|---|
| `readerOpen` | 点书 → 首次 `locationDidChange` | C 落地处 |
| `readerOpen.parse` / `readerOpen.navigator` | 分段 | 同上 |
| `keyboardAppear` | 聚焦意图 → `keyboardDidShow` | D 落地处（自动聚焦 sheet + composer） |
| `streamDelta` | delta 收到 → 视图提交 | B 落地处 |
| `textMeasure` | 一次全量测量（缓存缺失才计） | A 落地处；守卫断言命中率 |
| `selectionHitch` | 选区/手柄拖动期间主线程长阻塞计数 | debug 采样（CADisplayLink 或 `kdebug` 不可用时的 runloop 预算探针） |
| `aliveTextView` | 同屏常驻只读 UITextView 计数 | A 落地处（打点，供规模对照） |
| `launchInteractive` | 进程起 → Today 首帧可交互 | E 的 P2 若有 |

- **阈值策略**：先采集 2~4 周基线（真机 + 不同 iOS），再为每项设**预算**（中位数 + p95），预算不是一次性红线而是可回归的"护栏"；CI 用宽松阈值（防 flaky），开发期用严格阈值。

### 8.2 落地形态

- **`App/Performance/PerfSignposts.swift`**（或并入 DesignSystem 同级）：一个 `OSSignposter` 门面，DEBUG/内部构建启用在 app 侧所有里程碑打点。采用 `os.Logger`（subsystem `com.readloop.app` / category `perf`）同款风格，便于 `log stream` 观察。
- **Diagnostics 屏扩展**：把近期 signpost 摘要（次数/均值/p95/最大主线程连续阻塞）接到 `DiagnosticsModel` 之上的新聚合，显示在 `SettingsView` 的 Diagnostics 区（`SettingsView.swift:281` 已有展示位）。产出周期用户可自查，无需 Instruments。
- **Xcode UI target（可选做）**：`project.yml` 增加 `ReadLoopUITests`（`bundle.ui-testing`，target `ReadLoop`），用 fixture 大 EPUB 测 `readerOpen` 与 launch 的宽松阈值（`XCTMetric`/`measure`）。UI 测试易 flaky，**不作为唯一依赖**；主力是真机 Instruments + 上表打点。
- **单元/集成护栏**：文本测量缓存的"命中/未命中、失效条件、宽度桶界"、`withoutCitationBlock` 等价、去抖合并的字节一致性，全部写成现有测试体系内的确定性单测（`ReadLoopCoreTests` 风格，进 `swift test`），不走 UI 测试。
- 已有 `AnnotationLog`（`App/Reader/AnnotationLog.swift`，子系统 annotation）属排查用，用完待删；新护栏不与它混用。

### 8.3 验收（F）

- 三卡点与流式各有一条 signpost 曲线，能复现"优化前卡 / 优化后不卡"的差异。
- Diagnostics 屏能显示近期打点摘要。
- 缓存/去抖的确定性单测进入 `swift test` 现有体系，计数只增不减（以 CI 实际基线为准）。

---

## 9. 落地顺序与依赖

> 每个阶段含：动机 / 改动面 / 验收 / 风险与回滚。阶段之间可独立提交（Conventional Commits：perf/refactor 等前缀按仓库约定）。

| 阶段 | 工作包 | 内容 | 依赖 | 验收出口 |
|---|---|---|---|---|
| 0 | F 起点 | 落 `PerfSignposts` + Diagnostics 打点，采三卡点 + 流式基线 | 无 | 基线曲线 + 指标表（§8.1）定稿 |
| 1 | A | TextMeasureCache + RichTextBuilder；替换会话/档案正文为 MessageText | 阶段 0 | §3.6；`textMeasure` 命中率断言 |
| 2 | B | 流式去抖合并（保 withoutCitationBlock / 完成切换语义） | A | §4.3；`streamDelta` 不随长度线性增长 |
| 3 | C | 管线重排（async let open∥position+preferences、首 locationDidChange 揭盖、后置 highlights/notes/markOpened）+ Publication 缓存与预取 | 阶段 0（盖板需要基线）；不依赖 A | §5.5；`readerOpen` 曲线 |
| 4 | D | 键盘 frame 驱动滚动、去整树动画；两处自动聚焦 sheet 节奏 | A（safe-area 不重测前提） | §6.3；`keyboardAppear` 曲线 |
| 5 | E-P2 | 冷启动迁移离主（若基线证明值得） | 阶段 0 | §7.4 |
| 二期 | C-离主 / B-增量流 | 视 §10 R1 与基线决定 | — | — |

- **回滚**：各阶段改动集中在 DesignSystem / ReaderScreen+ReadiumReaderView / 会话 model，均可用 git revert 单阶段回滚；**阶段 0 的回滚定义 = 移除打点**，但它不改变行为，建议永久保留。
- **别动**：会话/标注的交互规格（§2.2）、死路径 `BrainDiscussionSheet`（勿误迁移）、GRDB 与 Agent 产出端（已正确离主，别"顺手"改回来）。

---

## 10. 风险与开放问题

- **R1（决定 C-离主是否可行）**：`Publication`/`Asset`/解析产物的并发安全与 `Sendable` 语义——跨打开缓存与移出主执行器都建立在它之上。落地 C 前先读 Readium 源码确认；不满足则按 §5.3 降级、§5.4 放弃。
- **R2（就绪信号精度）**：以首次 `locationDidChange` 为"真出页"，语义上是"能算出位置"而非"绘制完成"。若基线显示揭盖瞬间仍有可感闪白，备用方案是观察 navigator 内 WKWebView `scrollView.alpha`（私有侵入，默认不做）。
- **R3（⚠️ 主执行器负担量级）**：Readium parse/spread 创建在主执行器的 CPU 段时长尚未用 Instruments 证实，仅源码推断。阶段 0 必须实测，可能改变 C 的预算分配（缓存 vs 离主）。
- **R4（系统键盘冷启动）**：卡点 2 里最大头在系统，App 侧能消的是"不抢道 + 不整树重排"。D 的验收不应把"键盘总耗时"当 App 预算，要分系统/App 两段计量。
- **R5（真机 vs 模拟器 / iOS 版本）**：三卡点与指标都以**真机**为准（模拟器键盘、WebKit、Focus 行为均不同）；支持 iOS 26 及更早的文本选区行为差异已在 `SelectableText.swift:4-7` 注明，A 不得改变该兼容边界。
- **R6（动态类型/旋转）**：宽度/字号变化会命中缓存失效并触发重测——这是**设计内**成本，不是回归；护栏按"失效次数"而不是"绝对不测"断言。

---

## 附录：调研证据索引

**已证（据代码可直接判断）**
- GRDB 异步离主：`Sources/Persistence/AppDatabase.swift:6-23`；各仓库 `await db.writer.read/write` 全量统计
- 冷启动迁移同步在主：`AppDatabase.swift:10`、`App/AppModel.swift:46`
- Agent 产出端离主：`Sources/ReaderAgent/ReaderAgent.swift:128-148`、`Sources/AgentRuntime/AgentExecutor.swift:13-67`
- 流式消费整串重解析：`SessionReflectionSheet.swift:776-820`（含 `:797-798` 去 citation）、`AgentMarkdownText.swift:48-58`、`SelectableText.swift:89-113`
- FitTextView 整串量高：`SelectableText.swift:159-177`；整串比较 `:32`
- 会话正文非 Lazy、N 消息 ≈ N UITextView：`SessionReflectionSheet.swift:1077-1106,1135-1141`
- Thoughts 档案懒粒度在 section 而非单卡：`ThoughtsView.swift:120-121,187-274`
- Journal 卡 Lazy + 编辑 sheet 自动聚焦：`ThoughtsView.swift:214-228`、`JournalEntryCard.swift:283-324`
- Reader 自动聚焦：`AnnotationUI.swift:404-468`
- Reflection composer 手动聚焦：`SessionReflectionSheet.swift:1074,1178-1187,1318`
- Reader prepare 串行与依赖：`ReaderModel.swift:128-152`、`ReadiumReaderView.swift:44-98`
- Publication 零缓存 & 消费方：`ReadiumServices.swift:28-32`、`ReadiumMetadataReader.swift:11,23`、`ReadiumBookIndexer.swift:146`、`LibraryModel.swift:116-127`
- 无首帧就绪公开回调 / 用首个 locationDidChange：Readium `RT/Navigator/…`（NavigatorDelegate/VisualNavigatorDelegate/EPUBNavigatorDelegate、PaginationView.loadPages→updateCurrentLocation）
- GCDWebServer 惰性 serve / 常驻：`RT/…/GCDHTTPServer.swift:189-201`
- 可观测性空白：全仓无 os_signpost/MetricKit；`DiagnosticsModel.swift:10-25`；`project.yml` 无 UI 测试 target；`BenchCore` 纯 CLI
- 死路径：`MyMindView.swift:1069-1163`（BrainDiscussionSheet 无展示点）

**待验证（需 Instruments/真机）**
- Readium parse/spread 创建的主执行器 CPU 时长量级（R3）
- Publication/Asset 并发语义（R1）
- 首次键盘/选区的系统冷启动份额（R4）

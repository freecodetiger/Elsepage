# ElsePage 产品与架构认知基线

研究日期：2026-11-14。源码基线 `main@000f28633efa090842cb39bb06f7a7456081a3cb`，包含研究开始前已有的 Scheme 工作区差异。状态与证据口径见 [入口](README.md)。本文描述现状，不是新设计或实现方案。

## 1. 产品定位与用户问题

**定位：以 EPUB 阅读为入口，把用户自己的表达累积为可追溯思想档案的 iPhone 个人思考助手。** 阅读器、读后反思、基于阅读与历史的 AI 回应、长期 Brain 四部分共同构成产品。工程名 `ReadLoop`，README 使用 Elsepage / 页外，App 显示名为“页外”；命名并未在所有文档与构建输入中统一。

用户问题是“读过之后没有留下自己的理解、表达与观点变化”，以及把书摘搬到另一个 AI 工具时的上下文丢失。这是 PRD 提出的产品假设，源码证明系统在支持这条链路，**不证明用户需求、留存和真实市场优势已经得到验证**。目标人群为有 EPUB 阅读习惯、愿意读后花几分钟表达、接受 BYOK 配置的中文读者；18–35 岁来自 PRD，非埋点结论。

证据：[PRD §1、§2、§3](/Users/zpc/projects/elsepage/ReadLoop_PRD.md:27)；[README 产品说明](/Users/zpc/projects/elsepage/README.md:29)；[App 显示名与 EPUB 类型](/Users/zpc/projects/elsepage/App/Info.plist:9)；[实际三个 Tab](/Users/zpc/projects/elsepage/App/AppShell.swift:16)。

主要场景：

1. 把自己拥有的无 DRM EPUB 导入本地，安静阅读，恢复位置、搜索、划线和记笔记。
2. 读到不懂的句子时主动选句“问”，临时解释或追问，有需要才存为笔记。
3. 结束一次有意义的阅读，写下或说出自己的感想，先存本机，随后获得 AI 回应。
4. 在“想法”回看记录、继续讨论；在“我的”审视逐渐形成的看法、问题、记忆及其来源。
5. 配置自己的模型服务、可选检索服务，导出数据或控制删除。

## 2. 当前能力与完成度

Implemented 表示可达实现存在，不自动代表所有设备与 Provider 验收通过。运行列仅代表本次观察，完整证据见 [运行记录](README.md)。

| 能力 | 状态 | 当前源码事实与边界 | 本次运行 |
| --- | --- | --- | --- |
| 首次引导 | Implemented | 三步：导入 → AI 配置 → 首次阅读；可跳过。旧数据迁移策略由 `presentOnboardingIfFirstLaunch` 决定，没有独立欢迎页 | 已走通导入与跳过 AI |
| EPUB 导入 | Implemented | 单选 Files、外部 onOpenURL；安全作用域、协调复制、容器检查、内容指纹去重、元数据与封面读取，异步建索引 | 最小 EPUB 实际导入成功 |
| 书架 | Implemented | 封面网格、书名/作者搜索、最近阅读/书名/作者排序、删除；普通字号三列，无障碍字号一列 | 有书状态已观察 |
| Next Action | Partial | 只有当前书卡的“补写想法”；没有独立 Today Tab 或顶部 Next Action 卡 | 入口源码确认 |
| 阅读器 | Implemented | Readium EPUB、目录、书内搜索、位置恢复、4 个主题、字号/行高/边距、分页/滚动、跳转返回历史 | 正文、控制栏、目录、设置已观察 |
| 高亮与笔记 | Implemented | 4 色；Range 为身份，HighlightLayer 与多条 NoteEntry 独立；自定义浮层、重叠消歧、笔记预览/编辑、删除撤销 | 见运行记录中的实际覆盖 |
| 选句问答 Reader Help | Implemented | 用户主动提问；临时 thread；解释/追问/重试/复制/存为笔记，关闭丢弃，无 Reflection/Brain 写入 | idle 与未配置 Provider 错误已观察；成功回答待 Key |
| 阅读后文字 Reflection | Implemented | 会话结束满足阈值才邀请；原文先落库，再自动请求首次回应；允许跳过和事后补写 | 见运行记录 |
| 语音 Reflection | Implemented | Apple SFSpeechRecognizer，默认强制端上 zh-CN；手动启动、续录、可编辑转写、可选音频保存、合并/波形/播放/seek | 本次未验证真实识别准确率 |
| 独立表达润色 | Implemented | 独立 BYOK 请求；原话与整理版本分离；首次录音后满足条件可自动润色，失败保留原话 | 需 Key 验证 |
| 首次回应与追问 | Implemented | 首次保存自动请求；缺回应时有“让页外回应”；追问先持久化，稳定 messageID 保证重试幂等 | 无真实 Provider 成功证据 |
| 固定概要 | Implemented | 首次反思与首次 Agent response 派生，save-if-absent；缺概要时用本地截断文本回退 | 无 Key 时仅回退 |
| 想法档案 | Implemented | 按月/按书分组，搜索记录、书名、回应，详情复用对话；打开列表会调度补回应/概要 | 见运行记录 |
| Journal 结构化结果 | Partial | Parser 能提取 whatIThink/question 等，详情条件性显示“这次留下”；当前 Prompt 没有稳定要求产出 whatIThink | 不保证有内容 |
| Journal 用户编辑 | Partial | `applyThoughtEdit`、userEdited 与保护规则存在，但当前 ThoughtsView 没有调用编辑入口 | 不列为可用页面 |
| Personal Brain | Implemented | thought/question/memory tagged union、证据、关系、修订、查看/编辑/删除；稳定看法可存为记忆，问题可关联回答看法 | 有内容状态待样本与 Key |
| Brain 自动维护 | Implemented | 回应持久化后异步投影；LLM 提议、代码校验执行；失败不阻塞回应 | 未做真实模型验证 |
| Brain“继续想想” | Partial | 按钮设置 discussingItem；存在服务与 BrainDiscussionSheet，但没有 `.sheet` 消费该状态 | 无可达讨论面板 |
| 历史 Reflection 引用回跳 | Partial | 可以召回旧表达与显示连接；该证据在 ContextAssembler 里 `locator: nil`，不能据此跳到旧记录或原文 | 源码确认 |
| Memory 控制 | Partial | 可确认、不准确、修改、查看来源、单条“忘记”和全部清除；没有禁止某些内容进入记忆的 opt-out | 需注意“忘记”实际为硬删除 |
| 习惯与成就 | Implemented | 两种连续天数与 6 种成就定义，用户页展示与 toast；不是排行榜/积分系统 | 触发接线须按入口检查 |
| BYOK 设置 | Implemented | 13 个 Provider 预设（含自定义）；原生 Anthropic Messages，其余兼容协议；Model ID 手填；Keychain 存 Key | 未保存 Key |
| 书籍 RAG | Implemented | 结构提取 → child FTS/向量 → RRF → 可选 rerank → parent 窗口扩展 → 已读边界复检 | 最小书索引可用，语义/重排待配置 |
| 数据导出与清理 | Implemented | 单 JSON 导出、分享、录音清理、删全部书籍、两阶段全清；无导出包导入/还原 UI | 未对用户数据执行清除 |
| iCloud/多端同步、独立 Profile、知识图谱 UI、云 ASR、SSE | Planned | 文档方向或明确后延；当前没有这些可达产品能力 | 未声称实现 |
| App Store/TestFlight 完成度、真实留存、所有 Provider 可用性 | Unknown | 仓库清单与历史数据不能证明当前外部发布状态 | 需用户提供证据 |

关键源码：[引导复用真实导入](/Users/zpc/projects/elsepage/App/Onboarding/OnboardingModel.swift:35)；[importBook](/Users/zpc/projects/elsepage/App/Library/LibraryModel.swift:105)；[finishReading](/Users/zpc/projects/elsepage/App/Reader/ReaderScreen.swift:244)；[submit](/Users/zpc/projects/elsepage/App/Reflection/SessionReflectionSheet.swift:593)；[后台补齐](/Users/zpc/projects/elsepage/App/Thoughts/ThoughtsModel.swift:95)；[实际 Sheet 注册](/Users/zpc/projects/elsepage/App/MyMind/MyMindView.swift:83)；[结构化解析](/Users/zpc/projects/elsepage/Sources/ReflectionCore/JournalStructuredParser.swift:33)；[输出协议](/Users/zpc/projects/elsepage/Sources/ReaderAgent/ReaderAgentSystemPrompt.swift:544)；[Provider 预设](/Users/zpc/projects/elsepage/Sources/ModelProviders/ProviderConfiguration.swift:11)。

## 3. 最有差异化价值的能力

[推断] 最值得保护的是“原始表达 + 当次阅读位置/会话/标注 + 可验证的反馈证据 + 可修正的长期 Brain”的连续性。单纯让问答窗口更漂亮，不能替代这份用户资产。

[源码事实] 原文与 AI 对话分表；引用是 message-scoped evidence 快照；Brain 通过证据回到用户表达；旧陈述可保留修订；本地检索能连接同书及跨书旧反思。这使产品具备长期思想档案的基础。**效果质量、自动连接准确率和用户是否愿意持续输出仍属待验证，不能写成竞品领先结论。**

证据：[Reflection 与消息领域](/Users/zpc/projects/elsepage/Sources/ReflectionCore/Reflection.swift)；[同书/跨书候选](/Users/zpc/projects/elsepage/Sources/ReaderAgent/ReaderAgent.swift:267)；[引用校验](/Users/zpc/projects/elsepage/Sources/ReaderAgent/AgentCitationValidator.swift:29)；[投影执行](/Users/zpc/projects/elsepage/Sources/ReaderAgent/BrainProjectionService.swift:126)；[修订模型](/Users/zpc/projects/elsepage/Sources/BrainCore/BrainItemRevision.swift)。

## 4. 技术与模块架构

### 4.1 SwiftUI / UIKit 边界

App 的页面组织使用 SwiftUI，状态多为 `@MainActor @Observable` Model，通过 `@State` 持有、`@Bindable` 传递。不是每页独立 ViewModel：`SessionReflectionSheet.swift` 同时包含编辑器桥、提交 Model、对话 Model、多个 View；`MyMindView.swift` 同时包含列表、详情、编辑与孤立讨论 Sheet。

UIKit 是现有关键基础设施：

- `ReadiumReaderView: UIViewControllerRepresentable` → `ReaderHostViewController` → `EPUBNavigatorViewController`，其正文为 WebKit。
- `ReflectionUIKitTextView` / `ReflectionUITextView` 负责输入法 markedText、焦点、自然高度、外部清空与编辑同步。
- `SelectableTextView` / `FitTextView`、`SelectionKeeper` 处理长文本选择、富文本、量高缓存与链接点击。
- UIKit 同时用于封面、剪贴板、触感、无障碍播报、窗口截图。不得把这些桥误判为可以直接删除的视觉代码。

证据：[应用入口](/Users/zpc/projects/elsepage/App/ReadLoopApp.swift:3)；[UIKit 阅读器桥](/Users/zpc/projects/elsepage/App/Reader/ReadiumReaderView.swift:10)；[编辑器桥](/Users/zpc/projects/elsepage/App/Reflection/SessionReflectionSheet.swift:107)；[可选文本桥](/Users/zpc/projects/elsepage/App/DesignSystem/SelectableText.swift:278)。

### 4.2 入口、导航与装配

`ReadLoopApp` 启动 → `AppModel.start()` 离主线程打开数据库/迁移 → 装配 repositories、文件存储、Provider 工厂、检索、ReaderAgent、ReaderHelp、各页面 Model → `AppShell`。启动未完成显示进度，失败为静态 unavailable 页面。

Tab 是书架、想法、我的，各自 `NavigationStack`。书架 push 阅读器并使用 iOS 18 zoom；引导与想法/Brain 引用回跳由 AppShell fullScreenCover 打开阅读器。Settings 是三个 Tab 共用 Model、各自 Sheet 呈现。没有统一 Router、全局 NavigationPath、Deep Link 记录导航或登录流程。`onOpenURL` 是外部 EPUB 文件入口，非通用 App 路由。

证据：[start](/Users/zpc/projects/elsepage/App/AppModel.swift:47)；[Tab 与 fullScreenCover](/Users/zpc/projects/elsepage/App/AppShell.swift:16)；[书架 push](/Users/zpc/projects/elsepage/App/Library/LibraryView.swift:100)；详见 [导航图](00-navigation-map.md)。

### 4.3 页面与 Model 关系

| 页面 | 状态所有者 / 装配 | 关键依赖与边界 |
| --- | --- | --- |
| 首次引导 | AppModel.onboarding → OnboardingModel | 共享 LibraryModel / ProviderSettingsModel，完成写 UserDefaults |
| 书架 | AppModel.library → LibraryModel；View 内 LibraryNextActionModel | books、positions、stats、文件、Readium、索引队列；查询/排序是内存投影 |
| 阅读器及子 Sheet | LibraryModel 每次创建 ReaderModel，ReaderScreen 持有 | 同一 Model 管理位置、偏好、会话、标注、跳转、错误、多个呈现状态 |
| 临时问答 | ReaderModel 持有 ReaderHelpModel 与 helpSession | service 无 Reflection/Brain 仓库；持久化只经 saveHelpNote 回调 |
| 初始反思 | SessionReflectionModel | local submission → durable Reflection → conversation |
| 对话/档案详情 | ReflectionConversationModel | reflectionID、messages、provenance、pending send、audio、ReaderAgent |
| 想法列表 | ThoughtsModel | archive + Journal 派生加载 + 缺回应后台补齐；不仅是展示查询 |
| 我的 | MyMindModel + AchievementModel | Brain、来源反思、书籍、会话、连续天数；编辑后 reload |
| 设置 | SettingsRootModel 聚合 chat/rag/diagnostics/data/ragManagement | chat 与 RAG 共用持久化配置行；身份和录音偏好为 AppStorage |

证据：[页面装配](/Users/zpc/projects/elsepage/App/AppModel.swift:144)；[阅读器状态所有权](/Users/zpc/projects/elsepage/App/Reader/ReaderModel.swift:104)；[列表 reload 与副作用](/Users/zpc/projects/elsepage/App/Thoughts/ThoughtsModel.swift:63)；[设置聚合](/Users/zpc/projects/elsepage/App/Settings/SettingsRootModel.swift:8)。

### 4.4 Swift Package 结构

一个本地 `ReadLoopCore` Package，**16 个 library products + 2 个 CLI executables + 4 个 package test targets**。App 本身不在这些 package targets 中。Swift tools 6.0；iOS 18+ / portable macOS 14+；项目当前 Swift 6 strict concurrency，iPhone 为目标设备族。

| 模块 | 主要职责 | 主要直接依赖 |
| --- | --- | --- |
| LibraryCore | 书籍/指纹/书架统计/章节名 | Foundation |
| ReaderCore | Locator、阅读偏好、标注、请求/保存协调 | LibraryCore |
| ReadingSessionCore | 会话开始/结束/计数/有意义阅读判定 | LibraryCore、ReaderCore |
| ReflectionCore | 原始表达、消息、Journal、归档、概要、导出 | BrainCore、LibraryCore、ReaderCore、ReadingSessionCore、RetrievalCore |
| BrainCore | 看法/问题/记忆、证据/关系/演化/生命周期协议 | Foundation |
| AchievementCore | 行为型成就判定与记录 | LibraryCore、ReflectionCore |
| SpeechCore | 端上识别、文件转写、状态/可用性 | Apple Speech/AVFoundation（平台分支） |
| RetrievalCore | 分块、索引任务、已读边界、书证据检索/扩展 | LibraryCore、ReaderCore |
| ContextRouting | 语义计划 v2、校验、策略编译、LLM/确定性路由 | AgentRuntime、LibraryCore |
| ContextEngineering | 候选召回/排名/预算/组装、Brain 桥 | BrainCore、ContextRouting、RetrievalCore、ReflectionCore、ReaderCore、LibraryCore |
| AgentRuntime | 模型协议、预算、事件与单次有界执行器 | Foundation |
| ReaderAgent | 产品回应编排、ReaderHelp、引用校验、Brain 投影/概要 | AgentRuntime、BrainCore、ContextRouting、ContextEngineering、ReaderCore、ReflectionCore、RetrievalCore |
| ModelProviders | OpenAI 兼容、Anthropic、Embedding、Rerank、Keychain | AgentRuntime、RetrievalCore |
| Persistence | GRDB repositories、迁移、清除、隔离测试环境 | 领域模块、ModelProviders、ContextRouting、GRDB |
| AppInfrastructure | EPUB/音频文件、导入、无障碍、引导/日期/波形 | LibraryCore、ReaderCore |
| BenchCore | 样本、执行、judge、回归比较 | Agent/上下文/领域/模型模块 |
| readloop-bench / readloop-bench-compare | 开发 CLI，不是 App 页面 | BenchCore |

唯一 package 直接第三方依赖是 GRDB **7.11.1**；Xcode App 另引 Readium **3.11.0** 的 Shared/Streamer/Navigator。Readium 带入 Fuzi、SwiftSoup、GCDWebServer、ZIP 等传递依赖；不能称整个 App 仅有两个底层库。未发现 Analytics/Crash SDK 接入。DesignSystem 是 App 目录，**不是独立 Swift Package**。

证据：[完整 target / product 依赖声明](/Users/zpc/projects/elsepage/Package.swift:4)；[iOS、Swift、设备与 Readium 配置](/Users/zpc/projects/elsepage/project.yml:1)；[依赖 pins](/Users/zpc/projects/elsepage/Package.resolved)。

### 4.5 Readium 集成边界

`ReadiumServices` 是 `@MainActor` 的 Publication 共享入口；按文件路径/大小/修改时间及 allowUserInteraction 缓存，容量 4，合并同键 opening task。阅读器 preload 与 navigator open 复用解析；导入元数据与索引使用相应 interaction 策略。每次打开仍创建新的 navigator / WKWebView。

`ReadiumMetadataReader` 提取标题、作者、封面；`ReadiumBookContentExtractor` 将 Publication 的 readingOrder/content 元素转成领域文本块；`ReadiumReaderView.Coordinator` 将 Readium Locator 与完整 JSON 桥接为 BookLocator，并负责搜索、目录、装饰、高亮/下划线点击、选区、偏好提交、导航。

范围读取还会在 WebKit 内执行 selection/hit-test JS。这与可选菜单的命中和坐标约定紧耦合，不是通用纯 SwiftUI Popover。`isPrepared` 只代表位置/偏好门闩已放行，不能等同于 WebKit 首帧已绘制。

证据：[缓存与 open](/Users/zpc/projects/elsepage/App/Reader/ReadiumServices.swift:7)；[内容提取适配器](/Users/zpc/projects/elsepage/App/Reader/ReadiumBookIndexer.swift:9)；[选区与 JS 范围桥](/Users/zpc/projects/elsepage/App/Reader/ReadiumReaderView.swift:208)；[prepare 门闩](/Users/zpc/projects/elsepage/App/Reader/ReaderModel.swift:155)。

## 5. 数据、AI 与恢复机制

### 5.1 本地数据和标注

App support 下 `Database/readloop.sqlite`，GRDB DatabaseQueue、WAL、外键开启，迁移到 **v29**。书文件存 `Books`，音频由 AudioFileStore 管理，偏好/首次引导部分使用 UserDefaults；API Key 只进 Keychain，DB 只存 SecretReference。不是 SwiftData/Core Data，也没有自有后端或账号体系。

`BookLocator.json` 需要无损保留未知 Readium 字段；位置/偏好通过 latest-value 状态与延迟写入协调，退后台、退出、旋转会 flush。位置保存延迟 750ms，偏好 250ms，笔记编辑器 400ms；这不是“每次手势已同步刷盘”的保证。

标注事实模型为 `TextAnnotation(range, highlight?, notes[])`，新表 `textAnnotations` / `annotationNotes`。Persistence 仍镜像 legacy `highlights` / `notes` 供旧读取、统计、Reflection 链接、导出使用。**视觉重构不能自行把旧表当冗余删除。** 同范围再次高亮更新颜色；交叉高亮保守拒绝；删除高亮保留笔记；删除单条笔记不影响其余层。撤销提示是约 5 秒的当前会话快照，非永久回收站。

证据：[数据库与迁移](/Users/zpc/projects/elsepage/Sources/Persistence/AppDatabase.swift:6)；[写新模型并镜像旧层](/Users/zpc/projects/elsepage/Sources/Persistence/TextAnnotationRepository.swift:29)；[标注模型](/Users/zpc/projects/elsepage/Sources/ReaderCore/TextAnnotation.swift:146)；[无损 Locator](/Users/zpc/projects/elsepage/Sources/ReaderCore/BookLocator.swift:5)；[位置延迟写入](/Users/zpc/projects/elsepage/App/Reader/ReaderModel.swift:200)；[笔记 finalize](/Users/zpc/projects/elsepage/App/Reader/AnnotationUI.swift:627)。

### 5.2 AI、RAG、Evidence 与引用

Reflection 主链：本地原文 → 配置工厂 → 会话/附近文本 → LLM ContextRouter（8s）→ SemanticPlanValidator → ContextPolicyCompiler → 按需召回书籍、旧反思、Brain → ContextAssembler 去重/预算 → AgentExecutor 回复（45s / 1000 output tokens）→ AgentCitationValidator → 消息+证据+引用持久化 → 固定概要、异步 Brain 投影（独立20s）。这些是各子调用预算，**不是整个流程只需45s**。

本地书籍 RAG 的索引版本是 v3。child 负责 FTS5 trigram/embedding，parent 负责扩展后的上下文窗口；语义缺失可走词法，可选 reranker 失败回退融合结果。Reflection 也能做有界语义召回，Brain 有持久化向量与惰性刷新。RAG 不是云端知识库，Embedding/Reranker 请求会直发相应配置 Provider。

防剧透采用 CARC：已读边界可以放行当前 active retrieval child 的完整片段，**不等同于只看当前屏幕或严格不含游标后一个字**。边界未解析/无 progression 时保守降级；ReaderHelp 可只用选段和附近已读上下文。模型自身背景知识不受本地检索边界约束。

`AgentResponseEvidence` 是给当前消息实际传入的证据快照，`AgentCitation` 是该消息使用了哪些证据。`[E1]` 会变成应用内 `elsepage-citation://` 链接；未知引用被剔除、技术 citation 块不展示。Brain 作为**不可引用的个人上下文**进入模型，不能给它伪造书籍引用。旧反思证据目前 locator 为 nil；书籍证据回跳与“过去的你”展示应分别理解。

当前 Chat adapters HTTP **非流式**；ModelClient/Runtime 使用 stream 事件接口，但收到完整响应后才一次性 yield textDelta。UI 的 streaming 状态和 50ms buffer 不能当成真实 SSE 已实现。

证据：[回应/追问主链](/Users/zpc/projects/elsepage/Sources/ReaderAgent/ReaderAgent.swift:149)；[有界执行](/Users/zpc/projects/elsepage/Sources/AgentRuntime/AgentExecutor.swift:10)；[检索、扩展与索引](/Users/zpc/projects/elsepage/Sources/RetrievalCore/RetrievalServices.swift:57)；[已读边界](/Users/zpc/projects/elsepage/Sources/RetrievalCore/RetrievalModels.swift)；[旧反思无 Locator、Brain 不引用](/Users/zpc/projects/elsepage/Sources/ContextEngineering/ContextAssembler.swift:101)；[非流式 HTTP](/Users/zpc/projects/elsepage/Sources/ModelProviders/OpenAICompatibleModelClient.swift:17)；[引用验证](/Users/zpc/projects/elsepage/Sources/ReaderAgent/AgentCitationValidator.swift:29)；[引用链接消费](/Users/zpc/projects/elsepage/App/DesignSystem/AgentMarkdownText.swift:40)。

### 5.3 加载、失败、取消与恢复

| 环节 | 已实现机制 | 不应推断的能力 |
| --- | --- | --- |
| 启动 | 进度 → 依赖图就绪；DB 后台迁移；错误 unavailable | 无启动失败内置重试/修库入口 |
| 导入 | 状态圈；失败/重复 alert；staging 清理、指纹幂等 | 没有批量导入队列/逐项取消 UI；Files cancel/error 回调部分被忽略 |
| 阅读 | Publication cache、opening task 取消、位置恢复/flush；跳转历史有界 | 不证明强杀前最后750ms必不丢；无 navigator 自动重建恢复 UI |
| 标注 | 乐观投影、写失败回读、浮层清理、短时撤销 | 多次快写/退后台/旋转必须设备验证，不能只看 SwiftUI 图 |
| 正文搜索 | 250ms debounce、latest request token 防旧结果覆盖 | 不是跨书全文搜索 |
| Reflection | 稳定 draftID、原文先落库、失败回编辑、原话/润色分离 | 未提交草稿没有跨启动恢复保证 |
| Agent 首次回应 | in-flight 仲裁；已存回应直接复用；失败提示/按钮；想法页懒补齐 | 无 Reachability 驱动联网即重发、无持久化可恢复 Agent Run 队列 |
| 追问 | stable messageID、pending sending/failed、重发、已存用户文字不丢 | 未落库 pending UI 不等于 durable 消息；没有通用 Stop 按钮 |
| ReaderHelp | task.cancel、stream onTermination、关闭丢弃、重试；引用后缩到184pt保留 thread | 不是自动归档对话；没有跨 Reader 生命周期恢复 |
| 索引 | 持久化 job/资源游标、启动 resume、可重建/重新嵌入 | 不等于 BGTaskScheduler 后台任务；RAG 页不实时观察进度，需 reload |
| 音频 | draft/正式文件两阶段提升、提交后启动恢复、暂存删除回滚 | 无整包备份恢复；模拟器不能代表真机端上识别与音频中断 |
| 全清 | 清 DB/Keychain/文件/偏好、重装配、重新引导 | 跨 DB/Keychain/文件不是一个原子事务，失败可部分完成 |

证据：[cancel / discard](/Users/zpc/projects/elsepage/App/Reader/ReaderHelpModel.swift:132)；[追问交付](/Users/zpc/projects/elsepage/App/Reflection/SessionReflectionSheet.swift:834)；[首次回应仲裁](/Users/zpc/projects/elsepage/Sources/ReaderAgent/ReaderAgent.swift:176)；[任务恢复](/Users/zpc/projects/elsepage/App/Reader/ReadiumBookIndexer.swift:119)；[音频恢复协议](/Users/zpc/projects/elsepage/Sources/AppInfrastructure/AudioFileStore.swift)；[全清流程](/Users/zpc/projects/elsepage/App/Settings/DataSettingsModel.swift:176)；[DB 与 Keychain 两阶段](/Users/zpc/projects/elsepage/Sources/Persistence/LocalDataWipeService.swift:18)。

特别注意：`needsReview` Memory 目前仍符合 BrainRetriever eligible 条件（只排除 superseded / forgotten）；“待确认”不意味着绝不用于回应。索引恢复也有状态边界：Coordinator对中断的embedding任务选择embed，但Pipeline入口仅接收lexicalReady/ready，详见风险文档，不能概括为所有索引状态都能自动续跑。用户页“忘记”调用 repository.delete，是硬删除；因此不能声称所有忘记都会留审计痕迹。

## 6. 复用 UI 基础

`ElsepageTheme` 提供 spacing（6/10/16/20/28）、radius（12/24）、typography、material、shadow、motion。颜色实际数据在 AppInfrastructure 的 ElsepagePalette，SwiftUI 从它生成动态 UIColor，包含 background/surface/text/brand/interactive/success/warning/danger。当前 brand 与 interactive 为相同黑白值；封面占位另有 palette，不是完整主题系统。

现有组件：ElsepageIconButton / 44pt tap target、ElsepageBookCover、AgentMarkdownText、MessageText / SelectableTextBody、ReflectionTextEditor、VoiceReflectionControls / ReflectionAudioAttachment / WaveformScrubber、AchievementToast、ReaderAnnotationOverlays。大量原生 Form/List/Picker/ContentUnavailableView 也构成系统一致性的基础。页面仍有局部硬编码字号、间距与颜色；这里只记录分布，**不在本阶段作视觉审计评分或替换组件**。

证据：[视觉 token](/Users/zpc/projects/elsepage/App/DesignSystem/ElsepageTheme.swift:5)；[实际调色板](/Users/zpc/projects/elsepage/Sources/AppInfrastructure/AccessibilitySupport.swift:64)；[图标按钮与封面](/Users/zpc/projects/elsepage/App/DesignSystem/ElsepageComponents.swift:8)；[音频组件](/Users/zpc/projects/elsepage/App/Reflection/VoiceReflectionRecorder.swift:574)。

## 7. 文档与实现冲突

| 材料/设想 | 当前实现结论 |
| --- | --- |
| AGENTS 声称 PRD v0.2 | 文件实际 v0.4，迁移实际 v29；旧状态页不决定实现完成度 |
| 旧 Today / Library / Journal / My Mind 导航 | 当前只有书架/想法/我的；Journal 无独立入口 |
| PRD §21.2 说 Journal 用户编辑已交付 | 服务/测试在，但可达 ThoughtsView 无编辑 UI，Partial |
| PRD/brain 说“继续想想”复用链路 | Model / Sheet 在，展示接线缺失，Partial |
| 旧 Reader gate 的“聊聊”、高亮菜单笔记入口 | 当前选区为4色+笔记+问+复制；高亮菜单仅换色/删除 |
| Annotation Spec 的完整范围导出/多重 Note 选择 | 当前导出走 legacy highlights/notes；冲突菜单主要二选一，不能推断全规格已落地 |
| “忘记”保留审计轨迹 | 当前按钮实际硬删除，数据库存在 forgotten 枚举不证明该操作软删除 |
| 自动联网恢复 / 可恢复 Runtime | 实际为下次进入想法页懒补齐，无持久运行恢复 UI |
| ARCHITECTURE 的 memories / MemoryRetriever | v26已退役 memories；生产使用 Brain lane |
| 发布清单“5色高亮”“输出长度硬约束” | 源码为4色；自然语言长度指令与token预算不等于字符数硬验证 |
| project.yml 的 Reader productName / Scheme 旧产物名 | 本次提交工程实际生成 ReadLoop.app；用户已有 Scheme 差异参与构建 |
| release checklist “零真机证据” | DEBUG-LOOP 存历史真机记录；清单的全局断言不能照搬，也不能将旧真机证据冒充本次验收 |

## 8. 进入 UX 审计前需要的信息

1. 目标版本、首要用户与首发范围是否仍遵循 PRD v0.4，品牌名、iPhone 屏幕范围及 iPad 是否明确排除。
2. 用户最想改善的3条任务、失败/困惑的真实反馈，以及 Apple/Meta 中具体值得对齐的交互，而非笼统风格参考。
3. 可授权使用的代表性中文长 EPUB、复杂目录/图片/脚注样本、跨书反思和 Brain 演化样本；最小单页英文 fixture 不足以审计阅读体验。
4. 一台可手测的真实 iPhone、目标 iOS 版本、中文端上听写可用性，及大字号/VoiceOver/Reduce Motion 验收条件。
5. 可用的聊天 Provider，以及需要时独立 Embedding/Reranker 测试配置（凭据通过安全机制提供，不写文档）。
6. 对 Partial 能力的产品取舍：本轮只保留现状外观，还是另立后续功能修复；尤其 Journal 编辑、Brain 讨论、旧反思回跳、记忆 opt-out。本研究没有代为决定或实现。
7. 最新真机/TestFlight 验收、崩溃/性能资料、发布清单的实际完成状态，以及正式可保留/分享的截图数据范围。

# ElsePage UI/UX 现代化重构 · 产品理解阶段

**产品理解与源码取证已交付。后续用户明确授权视觉原型探索：当前已按方案 1 收敛出一版 iOS 原生书架样张，尚未写入 App。** 首次研究与运行证据保持为历史记录；新增探索见 [视觉原型 v0](01-visual-prototype.md)。

后续运行验证恢复：用户另行授权处理阻塞，已修复既有 iOS 测试中的旧 API 引用，13 个集成测试通过；已补装 Codex GSD 角色，新 Device 通道的打开/截图/控件读取/点击/文本输入/App重启后读取均通过，并新增有等待上限的只读快检入口。正式业务路径仍未因此自动验收。原研究记录与下文 V01–V07 保留为首次研究的历史证据；最新结果、命令和限制见 [运行验证恢复记录](00-runtime-verification.md)。没有修改业务或 UI 实现。

研究日期：2026-11-14（Asia/Shanghai）。源码基线 `main@000f28633efa090842cb39bb06f7a7456081a3cb`，研究前已有一处未暂存Scheme修改。本次构建与观察基于该工作区，不能当成纯HEAD的构建证明。

## 阅读入口

| 文档 | 回答的问题 |
| --- | --- |
| [产品与架构认知](00-product-understanding.md) | 产品定位、真实功能、差异化、技术栈、模块、数据、AI和恢复机制 |
| [页面与状态清单](00-screen-inventory.md) | 页面、Sheet、系统界面、Menu、Context Menu、Alert、主状态与不可达对象 |
| [导航图与用户路径](00-navigation-map.md) | 实际导航容器、首启/阅读/标注/问答/反思/Brain/设置路径、数据与状态流 |
| [重构边界与风险](00-refactor-risks.md) | 可以隔离的展示区域、十二类回归风险、现有缺口、后续验证边界 |
| [运行验证恢复记录](00-runtime-verification.md) | 后续测试修复、设备通道调查、实际结果与仍未完成的运行验证 |
| [视觉原型 v0](01-visual-prototype.md) | 用户授权后的A纸间/B清晰/C夜航三种交互方向，演示范围与待决策事项 |
| [字号与版式三方案](02-typography-layout-options.md) | 最新反馈后的1原生大字/2编辑目录/3封面主导，重建字级与空间比例，用户选择方案 1 |
| [书架原生收敛](03-native-refinement.md) | 方案 1 按 iOS/SwiftUI 最佳实践与奥卡姆剃刀收敛；删除项、版式规格与 SwiftUI 映射，已落地（书架，模拟器） |
| [我的的信息架构与组件](04-native-screens.md) | 我的改为分段控件并列三类内容，删除连续天数；6 个可复用组件、阅读页字号与引文组件，已落地（想法/我的；阅读器未改） |
| [Design System Guide](04-design-system-guide.md) | 语义色、字体、间距、圆角、边框/阴影、动效、组件状态；架构决定与使用规则 |
| [Component Catalog](04-component-catalog.md) | 按钮/图标按钮/列表行/标题/输入/卡片/空载错误/Banner/Toast 的状态与 API、快照 |
| [Migration Guidelines](04-migration-guidelines.md) | 逐屏迁移顺序、旧 token 映射、单屏步骤、验收清单与依赖边界 |
| [底部玻璃分体菜单](05-split-tab-bar.md) | 三 Tab 玻璃胶囊 + 右侧加号；iOS 26 glass / iOS 18 material / 减弱透明度 / 键盘 / 无障碍兜底；已落地 |
| [顶部标题行](06-header-row.md) | 大标题与右侧玻璃胶囊同一行；书架移除排序/导入按钮；自绘搜索框与键盘兜底；已落地 |
| [阅读体验重构报告](05-reader-redesign-report.md) | 阅读 chrome、排版、目录、选区/高亮、笔记、问答流式与错误、引用回跳；前后截图、问题映射、构建与未解决项 |
| [UI/UX 启发式评估](01-ux-audit.md) | 12 个维度、产品特性、视觉细节；区分已验证/高可信风险/待测试 |
| [用户旅程分析](01-user-journey-analysis.md) | 场景 A–I 的真实目标、当前路径、困惑、反馈缺口与更简单路径 |
| [优先问题清单](01-prioritized-issues.md) | 28 条问题、P0–P3、Top 10、Quick Wins、样板页与修复记录 |
| [最终 UI/UX 验收](07-final-uiux-review.md) | 视觉、交互、无障碍、性能与一致性验收；本轮修复与剩余问题 |
| [回归验收](07-regression-report.md) | EPUB、位置恢复、设置持久化、标注、AI 错误、生命周期、构建与测试 |
| [剩余问题清单](07-remaining-issues.md) | UX-001–028 最终状态、新发现 N-01–N-14、产品决策与发布前清单 |

## 证据与状态约定

- **Implemented**：可达实现与装配存在；不自动等于真机、所有Provider或全部失败路径验收通过。
- **Partial**：只有部分能力/接线/展示实现，或明确存在源码与产品规格缺口。
- **Planned**：文档方向、后延事项或被替代的旧IA；没有当前可达功能。
- **Unknown**：资料、配置、数据或运行条件不足，无法确定。
- “源码事实”与“本次运行观察”分开；推断明确标注，不把测试类名、注释、旧截图或旧计划当成真实交付。
- 源码链接含文件和尽可能准确的行号/符号。它们面向当前工作区；路径含本机绝对根，换机器应从同名仓库路径定位。未来源码变化后需重新校准行号。

## 研究范围与执行记录

本仓库是完整iPhone客户端与本地Swift Package，不是仅UI壳。纳入索引的自有Swift文件为 **App 45个 / Sources 111个 / Tests 68个**，合计224个；逐目录追踪声明、依赖、装配与所有用户呈现点，并对核心产品路径、状态/数据边界及相关测试深入核对。末尾提供完整Swift文件索引，便于复核和后续审计继续阅读。

阅读与对照材料包括根README、AGENTS、CLAUDE、CONTRIBUTING、PRD v0.4、Technical Design v0.2、历史ARCHITECTURE，以及DEBUG-LOOP、ReaderHelp、Annotation、Anti-Spoiler、性能、Brain、ADR、Provider矩阵、发布/UAT与规划资料。历史文档与当前实现的冲突已单列。没有把“文档全部完成”当“源码全部可达”；也没有把本研究视作224个文件每一行的形式化代码审计、依赖安全审计或全部测试断言的逐行复审。第三方Readium/GRDB依赖仅按集成边界调查，不修改依赖。当前环境没有CodeGraph工具，采用rg符号/引用搜索、配置注册、数据库迁移和测试交叉定位。

GSD入口已执行：`gsd-sdk query init.quick 'ElsePage UI UX modernization product understanding documentation only'`，任务编号 `261114-imy`。SDK报告标准GSD agent角色未安装；未安装/更换工具。按本次“只新增设计研究文档”的更具体边界，将计划、结果和执行限制收在本入口，未写`.planning`、未改STATE/ROADMAP、未自动commit。执行计划：

1. 建立源码、约束与运行基线：完成。
2. 追踪页面、模块、状态、导航和持久化：完成本次覆盖范围，未知项已标记。
3. 执行现有构建、包测试、可用运行与截图：已执行，成功与阻塞分开记录。
4. 装配五份文档并核验链接、证据与工作区：完成；本地链接、行号范围、Markdown表格及改动范围已核验。

应用技能：codebase-insight用于实现取证，swiftui-pro用于状态/导航边界核对，verification-before-completion用于证据与改动范围核验；没有使用创造/实现流程生成新UI。

## 本次运行环境

| 项目 | 实际值 |
| --- | --- |
| 开发工具 | Xcode 26.6，Build 17F113 |
| Swift | Apple Swift 6.3.3，arm64-apple-macosx26.0 |
| 模拟器 | iPhone 17 Pro，iOS 26.5，`C380BC09-F7BE-4A18-B856-10E516F9EB3C` |
| App | bundle `com.readloop.reader`，1.0.0 (1)，Debug，无签名模拟器构建 |
| 产物 | `ReadLoop.app`；productName 已统一为 ReadLoop（验收时曾为 Reader，与 TEST_HOST 指向的 ReadLoop.app 不一致，现已修正） |
| 测试内容 | 仓库CC0 `minimal.epub`，单章单屏英文，不含个人书库或真实Key |
| 真机/真实Provider | 本次没有执行，没有设置/读取用户Key |

AGENTS通常把Xcode/模拟器交给用户；本次用户明确要求环境具备时编译、运行和截图，因此仅按本轮授权执行。没有扩展为真机安装、TestFlight或发布。

## 验证结果与命令

原始证据已从临时目录复制到本机缓存留存：

[/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14)

截图与日志不进仓库，符合本轮只新增Markdown的边界。此目录仍是可被系统/用户清理的本机缓存，不是团队永久归档或跨机共享；如未来需要共享，应先按数据范围审查后搬到正式证据存储。DerivedData与xcresult原始bundle仍在临时工作目录。

| ID | 检查 | 本次结果 | 证据 |
| --- | --- | --- | --- |
| V01 | `swift test` | **PASS，exit0**；411个Swift Testing用例/15 suites + 28个XCTest，0失败 | [swift-test.log](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14/swift-test.log) |
| V02 | 现有Xcode工程模拟器App build | **BUILD SUCCEEDED，exit0**；不等于test target可编译 | [xcodebuild.log](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14/xcodebuild.log) |
| V03 | `-only-testing:ReadiumIntegrationTests ... test` | **TEST FAILED，exit65，编译阶段**；127/137/147/159行引用不存在的ReflectionDraft，另有连带类型推断错误。未执行集成测试用例，不把失败“修掉” | [xcode-test.log](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14/xcode-test.log)；[失败源码](/Users/zpc/projects/elsepage/Tests/ReadiumIntegrationTests/ReadiumPublicationIntegrationTests.swift:127) |
| V04 | DEBUG status/save | **PASS，exit0**；protocolVersion1、instrumentationVersion8；真实SessionReflectionModel+独立内存GRDB；保存、幂等、空白拒绝 | [result.json](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14/debug-save/033c3bca-6a65-4b67-bb49-75faa027b4ba/result.json) / [events.jsonl](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14/debug-save/033c3bca-6a65-4b67-bb49-75faa027b4ba/events.jsonl) |
| V05 | Simulator真实交互 | 首启三步、实际Files导入、跳过AI、书架、正文/控制栏、目录/设置、选区、无Provider问答失败、黄色高亮、空笔记预览/编辑：已观察 | P01–P16 |
| V06 | Perf直读 | 单次readerOpen≈1239ms，parse≈31ms，Navigator→firstPage≈557ms；n=1，只作取证，不作真机性能结论 | [perf-command.log](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14/perf-command.log) |
| V07 | 当前模拟器DB只读检查 | books1、textAnnotations2、Highlight1、空NoteEntry1、Reflection0、Brain0、bookChunks2、索引v3 lexicalReady；没有非空笔记已保存证据 | [persistent-state.json](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14/persistent-state.json) |

执行命令（实际derivedData与临时日志目录为`/tmp/elsepage-design-20261114`）：

```sh
swift test
xcodebuild -project ReadLoop.xcodeproj -scheme ReadLoop \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=C380BC09-F7BE-4A18-B856-10E516F9EB3C' \
  -derivedDataPath /tmp/elsepage-design-20261114/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ReadLoop.xcodeproj -scheme ReadLoop \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=C380BC09-F7BE-4A18-B856-10E516F9EB3C' \
  -derivedDataPath /tmp/elsepage-design-20261114/DerivedData \
  -resultBundlePath /tmp/elsepage-design-20261114/ReadiumIntegration.xcresult \
  -only-testing:ReadiumIntegrationTests CODE_SIGNING_ALLOWED=NO test
xcrun simctl install C380BC09-F7BE-4A18-B856-10E516F9EB3C \
  /tmp/elsepage-design-20261114/DerivedData/Build/Products/Debug-iphonesimulator/ReadLoop.app
xcrun simctl launch C380BC09-F7BE-4A18-B856-10E516F9EB3C com.readloop.reader
python3 Scripts/debug_loop.py status --wait 1 --output /tmp/elsepage-design-20261114/debug-status
python3 Scripts/debug_loop.py save --wait 1 --output /tmp/elsepage-design-20261114/debug-save
python3 Scripts/debug_loop.py perf --wait 1 --output /tmp/elsepage-design-20261114/perf
```

DEBUG HTTP监听进程经`lsof`确认是本次simulator App PID47333，而非复用未知真机转发。DEBUG测试session runID为`8074B2C1-64E3-49BF-89A4-905A4C012E17`（独立空白拒绝场景会另起session）；结果目录UUID并非该runID。没有把build1当成源码指纹；构建提交由本页基线与日志路径绑定。

最初按当时 project.yml 里写的 Reader.app 路径安装失败（NSPOSIXErrorDomain code2，文件不存在），随后按build日志的实际ReadLoop.app安装并启动成功。此处不是产品导入失败。productName 现已统一为 ReadLoop，该路径漂移不再存在。

App构建有现存废弃API等警告，包括Speech的AVAudioSession权限API、AudioFileStore的旧AVAssetExportSession API；本阶段保留，没有把warning描述为build失败，也没有顺手现代化代码。

## 截图索引

都是本次simctl实际截图（原始PNG，1206×2622），没有重绘/生成或合成假数据。P02仅为选择器空状态，随后测试fixture被放入该模拟器File Provider，再通过真实选择器导入。

| 编号 | 页面/状态 | PNG |
| --- | --- | --- |
| P01 | 首次导入引导 | [01-onboarding-import.png](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14/01-onboarding-import.png) |
| P02 | 系统Files选择器 / 本机空状态 | [02-file-picker.png](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14/02-file-picker.png) |
| P03 | EPUB导入成功 | [03-import-success.png](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14/03-import-success.png) |
| P04 | BYOK首次配置引导 | [04-onboarding-provider.png](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14/04-onboarding-provider.png) |
| P05 | 首次阅读引导 | [05-onboarding-first-read.png](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14/05-onboarding-first-read.png) |
| P06 | 书架与缺封面占位 | [06-library.png](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14/06-library.png) |
| P07 | 沉浸式正文 | [07-reader-immersive.png](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14/07-reader-immersive.png) |
| P08 | 阅读控制栏 | [08-reader-controls.png](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14/08-reader-controls.png) |
| P09 | 单章目录Sheet | [09-contents.png](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14/09-contents.png) |
| P10 | 阅读设置Sheet | [10-reader-appearance.png](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14/10-reader-appearance.png) |
| P11 | 原位选区工具栏 | [11-selection-toolbar.png](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14/11-selection-toolbar.png) |
| P12 | 临时问答idle | [12-reader-help-idle.png](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14/12-reader-help-idle.png) |
| P13 | 未配置Provider错误与重试 | [13-reader-help-no-provider.png](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14/13-reader-help-no-provider.png) |
| P14 | 黄色高亮已呈现 | [14-highlight.png](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14/14-highlight.png) |
| P15 | 空笔记预览 / 正文下划线 | [15-note-preview-empty.png](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14/15-note-preview-empty.png) |
| P16 | 空笔记编辑态 | [16-note-edit.png](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14/16-note-edit.png) |

## 阻塞与未完成运行验证

以下为首次研究结束时的状态。后续进展：第4项测试编译失败已修复并实际运行通过；第1项原 CUA 未修复，但替代的 Device 通道已实际通过基本交互与App重启后操作。其余业务未验收项没有因此自动完成，见 [恢复记录](00-runtime-verification.md)。

1. **电脑控制通道失效**：笔记编辑时paste返回`Computer Use server error -10005: cgWindowNotFound`；重新取窗口与状态仍失败。simctl截图和App的HTTP/进程仍活跃，因此只能归为控制工具失效，没有App崩溃证据。未用脚本注入文字、私有手势或DB造数伪装完成。
2. **真实AI数据缺失**：本次没有Key，未验证Test Connection成功、回应质量、真实引用回跳、Embedding/Reranker网络、Brain生成与长期质量。没有主动读取Keychain中的已有秘密。
3. **样书不足**：只有单章单页英文fixture；不覆盖中文长文、多章、图文混排、脚注、复杂选区、长书性能和不同DRM失败样本。
4. **iOS测试编译失败**：V03已记录。本阶段禁止修改实现及测试源码，没有修复或跳过失败测试后冒称全绿。
5. **本次未触达**：正式Session Reflection编辑/保存与档案详情、想法/我的/设置全部子页、正文搜索/标注列表、非空笔记保存、记忆编辑/来源、多条笔记、成就toast、系统分享与危险操作、真实语音、旋转/后台/强杀恢复。这些均只有相应源码或包级测试证据。
6. **没有自动UI测试基线**：project.yml没有XCUITest target；DEBUG闭环目前只是有限隔离业务场景；历史真机证据不等同当前全链回归。

## 首次研究的工作区保护与阶段交付

- 仅新增本目录五个Markdown文件，不修改业务/UI/测试/配置/现有文档。
- 研究前的`ReadLoop.xcodeproj/xcshareddata/xcschemes/ReadLoop.xcscheme`差异保留；前后binary diff的SHA256均为`4a4b42d97ca42274be34b146a331f62a873fa65eaf912d87c2d03a5eb26ea1d5`。
- `swift test`改写的Package.resolved已对照研究前副本恢复，仅撤销本次测试副作用，没有覆盖用户已有变更。
- 没有运行xcodegen，没有提交/推送/合并/部署，没有进入下一阶段。
- 后续UX审计需要的产品、样本、设备与配置清单见 [产品认知§8](00-product-understanding.md)。本轮不要求用户先提供这些信息才能交付当前研究。

## 自有Swift文件完整索引

以下是本次范围的可复查文件清单，**文件被列入不等于每行均已审计或每个状态已运行**。核心链路与具体判断的证据已在四份主体文档中逐项链接。目录中的CLI/Bench、测试fixture helper与DEBUG工具不是用户页面。

### App（45）

- `App/Achievement`：[AchievementModel.swift](/Users/zpc/projects/elsepage/App/Achievement/AchievementModel.swift)、[AchievementToast.swift](/Users/zpc/projects/elsepage/App/Achievement/AchievementToast.swift)
- `App`：[AppModel.swift](/Users/zpc/projects/elsepage/App/AppModel.swift)、[AppShell.swift](/Users/zpc/projects/elsepage/App/AppShell.swift)、[ReadLoopApp.swift](/Users/zpc/projects/elsepage/App/ReadLoopApp.swift)
- `App/DesignSystem`：[AgentMarkdownText.swift](/Users/zpc/projects/elsepage/App/DesignSystem/AgentMarkdownText.swift)、[ElsepageComponents.swift](/Users/zpc/projects/elsepage/App/DesignSystem/ElsepageComponents.swift)、[ElsepageTheme.swift](/Users/zpc/projects/elsepage/App/DesignSystem/ElsepageTheme.swift)、[Haptics.swift](/Users/zpc/projects/elsepage/App/DesignSystem/Haptics.swift)、[SelectableText.swift](/Users/zpc/projects/elsepage/App/DesignSystem/SelectableText.swift)
- `App/Library`：[LibraryGridView.swift](/Users/zpc/projects/elsepage/App/Library/LibraryGridView.swift)、[LibraryModel.swift](/Users/zpc/projects/elsepage/App/Library/LibraryModel.swift)、[LibraryNextActionModel.swift](/Users/zpc/projects/elsepage/App/Library/LibraryNextActionModel.swift)、[LibraryView.swift](/Users/zpc/projects/elsepage/App/Library/LibraryView.swift)、[ReadiumMetadataReader.swift](/Users/zpc/projects/elsepage/App/Library/ReadiumMetadataReader.swift)
- `App/MyMind`：[MyMindModel.swift](/Users/zpc/projects/elsepage/App/MyMind/MyMindModel.swift)、[MyMindView.swift](/Users/zpc/projects/elsepage/App/MyMind/MyMindView.swift)
- `App/Onboarding`：[OnboardingModel.swift](/Users/zpc/projects/elsepage/App/Onboarding/OnboardingModel.swift)、[OnboardingView.swift](/Users/zpc/projects/elsepage/App/Onboarding/OnboardingView.swift)
- `App/Performance`：[DebugHTTPServer.swift](/Users/zpc/projects/elsepage/App/Performance/DebugHTTPServer.swift)、[DebugLoop.swift](/Users/zpc/projects/elsepage/App/Performance/DebugLoop.swift)、[Perf.swift](/Users/zpc/projects/elsepage/App/Performance/Perf.swift)、[PerfDiagnosticsView.swift](/Users/zpc/projects/elsepage/App/Performance/PerfDiagnosticsView.swift)
- `App/Reader`：[AnnotationLog.swift](/Users/zpc/projects/elsepage/App/Reader/AnnotationLog.swift)、[AnnotationUI.swift](/Users/zpc/projects/elsepage/App/Reader/AnnotationUI.swift)、[ReaderHelpModel.swift](/Users/zpc/projects/elsepage/App/Reader/ReaderHelpModel.swift)、[ReaderHelpSheet.swift](/Users/zpc/projects/elsepage/App/Reader/ReaderHelpSheet.swift)、[ReaderModel.swift](/Users/zpc/projects/elsepage/App/Reader/ReaderModel.swift)、[ReaderScreen.swift](/Users/zpc/projects/elsepage/App/Reader/ReaderScreen.swift)、[ReadiumBookIndexer.swift](/Users/zpc/projects/elsepage/App/Reader/ReadiumBookIndexer.swift)、[ReadiumReaderView.swift](/Users/zpc/projects/elsepage/App/Reader/ReadiumReaderView.swift)、[ReadiumServices.swift](/Users/zpc/projects/elsepage/App/Reader/ReadiumServices.swift)
- `App/Reflection`：[SessionReflectionSheet.swift](/Users/zpc/projects/elsepage/App/Reflection/SessionReflectionSheet.swift)、[VoiceReflectionRecorder.swift](/Users/zpc/projects/elsepage/App/Reflection/VoiceReflectionRecorder.swift)
- `App/Settings`：[ConversationIdentitySettingsView.swift](/Users/zpc/projects/elsepage/App/Settings/ConversationIdentitySettingsView.swift)、[DataSettingsModel.swift](/Users/zpc/projects/elsepage/App/Settings/DataSettingsModel.swift)、[DiagnosticsModel.swift](/Users/zpc/projects/elsepage/App/Settings/DiagnosticsModel.swift)、[ProviderSettingsModel.swift](/Users/zpc/projects/elsepage/App/Settings/ProviderSettingsModel.swift)、[RAGManagementModel.swift](/Users/zpc/projects/elsepage/App/Settings/RAGManagementModel.swift)、[RAGManagementView.swift](/Users/zpc/projects/elsepage/App/Settings/RAGManagementView.swift)、[RAGSettingsModel.swift](/Users/zpc/projects/elsepage/App/Settings/RAGSettingsModel.swift)、[SettingsRootModel.swift](/Users/zpc/projects/elsepage/App/Settings/SettingsRootModel.swift)、[SettingsView.swift](/Users/zpc/projects/elsepage/App/Settings/SettingsView.swift)
- `App/Thoughts`：[ThoughtsModel.swift](/Users/zpc/projects/elsepage/App/Thoughts/ThoughtsModel.swift)、[ThoughtsView.swift](/Users/zpc/projects/elsepage/App/Thoughts/ThoughtsView.swift)

### Sources（111）

- `Sources/AchievementCore`：[Achievement.swift](/Users/zpc/projects/elsepage/Sources/AchievementCore/Achievement.swift)
- `Sources/AgentRuntime`：[AgentDomain.swift](/Users/zpc/projects/elsepage/Sources/AgentRuntime/AgentDomain.swift)、[AgentExecutor.swift](/Users/zpc/projects/elsepage/Sources/AgentRuntime/AgentExecutor.swift)、[FakeModelClient.swift](/Users/zpc/projects/elsepage/Sources/AgentRuntime/FakeModelClient.swift)、[ModelContracts.swift](/Users/zpc/projects/elsepage/Sources/AgentRuntime/ModelContracts.swift)、[TranscriptPolishService.swift](/Users/zpc/projects/elsepage/Sources/AgentRuntime/TranscriptPolishService.swift)
- `Sources/AppInfrastructure`：[AccessibilitySupport.swift](/Users/zpc/projects/elsepage/Sources/AppInfrastructure/AccessibilitySupport.swift)、[AudioFileStore.swift](/Users/zpc/projects/elsepage/Sources/AppInfrastructure/AudioFileStore.swift)、[AudioWaveform.swift](/Users/zpc/projects/elsepage/Sources/AppInfrastructure/AudioWaveform.swift)、[BookFileStore.swift](/Users/zpc/projects/elsepage/Sources/AppInfrastructure/BookFileStore.swift)、[BookImporter.swift](/Users/zpc/projects/elsepage/Sources/AppInfrastructure/BookImporter.swift)、[ElsepageDateFormat.swift](/Users/zpc/projects/elsepage/Sources/AppInfrastructure/ElsepageDateFormat.swift)、[OnboardingFlow.swift](/Users/zpc/projects/elsepage/Sources/AppInfrastructure/OnboardingFlow.swift)
- `Sources/BenchCore`：[BenchAdapters.swift](/Users/zpc/projects/elsepage/Sources/BenchCore/BenchAdapters.swift)、[BenchCompare.swift](/Users/zpc/projects/elsepage/Sources/BenchCore/BenchCompare.swift)、[BenchJudge.swift](/Users/zpc/projects/elsepage/Sources/BenchCore/BenchJudge.swift)、[BenchModelClientFactory.swift](/Users/zpc/projects/elsepage/Sources/BenchCore/BenchModelClientFactory.swift)、[BenchPipeline.swift](/Users/zpc/projects/elsepage/Sources/BenchCore/BenchPipeline.swift)、[BenchRunner.swift](/Users/zpc/projects/elsepage/Sources/BenchCore/BenchRunner.swift)、[BenchSample.swift](/Users/zpc/projects/elsepage/Sources/BenchCore/BenchSample.swift)、[JudgePrompt.swift](/Users/zpc/projects/elsepage/Sources/BenchCore/JudgePrompt.swift)
- `Sources/BrainCore`：[BrainEmbeddingStore.swift](/Users/zpc/projects/elsepage/Sources/BrainCore/BrainEmbeddingStore.swift)、[BrainItem.swift](/Users/zpc/projects/elsepage/Sources/BrainCore/BrainItem.swift)、[BrainItemRevision.swift](/Users/zpc/projects/elsepage/Sources/BrainCore/BrainItemRevision.swift)、[BrainLifecycle.swift](/Users/zpc/projects/elsepage/Sources/BrainCore/BrainLifecycle.swift)、[BrainMutation.swift](/Users/zpc/projects/elsepage/Sources/BrainCore/BrainMutation.swift)、[BrainProjectionTrace.swift](/Users/zpc/projects/elsepage/Sources/BrainCore/BrainProjectionTrace.swift)、[BrainRepository.swift](/Users/zpc/projects/elsepage/Sources/BrainCore/BrainRepository.swift)
- `Sources/ContextEngineering`：[BrainContextProvider.swift](/Users/zpc/projects/elsepage/Sources/ContextEngineering/BrainContextProvider.swift)、[BrainRetriever.swift](/Users/zpc/projects/elsepage/Sources/ContextEngineering/BrainRetriever.swift)、[ContextAssembler.swift](/Users/zpc/projects/elsepage/Sources/ContextEngineering/ContextAssembler.swift)、[ContextCandidate.swift](/Users/zpc/projects/elsepage/Sources/ContextEngineering/ContextCandidate.swift)、[ContextCandidateRanker.swift](/Users/zpc/projects/elsepage/Sources/ContextEngineering/ContextCandidateRanker.swift)、[ContextSource.swift](/Users/zpc/projects/elsepage/Sources/ContextEngineering/ContextSource.swift)、[HybridFusion.swift](/Users/zpc/projects/elsepage/Sources/ContextEngineering/HybridFusion.swift)、[QueryTimeSemanticRanking.swift](/Users/zpc/projects/elsepage/Sources/ContextEngineering/QueryTimeSemanticRanking.swift)、[ReflectionLexicalMatcher.swift](/Users/zpc/projects/elsepage/Sources/ContextEngineering/ReflectionLexicalMatcher.swift)、[ReflectionRetriever.swift](/Users/zpc/projects/elsepage/Sources/ContextEngineering/ReflectionRetriever.swift)、[RetrievalCandidate.swift](/Users/zpc/projects/elsepage/Sources/ContextEngineering/RetrievalCandidate.swift)、[SemanticRanking.swift](/Users/zpc/projects/elsepage/Sources/ContextEngineering/SemanticRanking.swift)、[SemanticVectorCache.swift](/Users/zpc/projects/elsepage/Sources/ContextEngineering/SemanticVectorCache.swift)
- `Sources/ContextRouting`：[ContextPolicyCompiler.swift](/Users/zpc/projects/elsepage/Sources/ContextRouting/ContextPolicyCompiler.swift)、[ContextRoutingModels.swift](/Users/zpc/projects/elsepage/Sources/ContextRouting/ContextRoutingModels.swift)、[LLMReaderContextRouter.swift](/Users/zpc/projects/elsepage/Sources/ContextRouting/LLMReaderContextRouter.swift)、[PlannerWirePlan.swift](/Users/zpc/projects/elsepage/Sources/ContextRouting/PlannerWirePlan.swift)、[SemanticContextPlan.swift](/Users/zpc/projects/elsepage/Sources/ContextRouting/SemanticContextPlan.swift)、[SemanticPlanValidator.swift](/Users/zpc/projects/elsepage/Sources/ContextRouting/SemanticPlanValidator.swift)
- `Sources/LibraryCore`：[Book.swift](/Users/zpc/projects/elsepage/Sources/LibraryCore/Book.swift)、[BookLibraryStats.swift](/Users/zpc/projects/elsepage/Sources/LibraryCore/BookLibraryStats.swift)、[ChapterTitle.swift](/Users/zpc/projects/elsepage/Sources/LibraryCore/ChapterTitle.swift)
- `Sources/ModelProviders`：[AnthropicModelClient.swift](/Users/zpc/projects/elsepage/Sources/ModelProviders/AnthropicModelClient.swift)、[ConfiguredModelClientFactory.swift](/Users/zpc/projects/elsepage/Sources/ModelProviders/ConfiguredModelClientFactory.swift)、[OpenAICompatibleEmbeddingProvider.swift](/Users/zpc/projects/elsepage/Sources/ModelProviders/OpenAICompatibleEmbeddingProvider.swift)、[OpenAICompatibleModelClient.swift](/Users/zpc/projects/elsepage/Sources/ModelProviders/OpenAICompatibleModelClient.swift)、[ProviderConfiguration.swift](/Users/zpc/projects/elsepage/Sources/ModelProviders/ProviderConfiguration.swift)、[SecretStore.swift](/Users/zpc/projects/elsepage/Sources/ModelProviders/SecretStore.swift)、[SiliconFlowReranker.swift](/Users/zpc/projects/elsepage/Sources/ModelProviders/SiliconFlowReranker.swift)
- `Sources/Persistence`：[AchievementRepositories.swift](/Users/zpc/projects/elsepage/Sources/Persistence/AchievementRepositories.swift)、[AppDatabase.swift](/Users/zpc/projects/elsepage/Sources/Persistence/AppDatabase.swift)、[BookIndexRepository.swift](/Users/zpc/projects/elsepage/Sources/Persistence/BookIndexRepository.swift)、[BrainRepositories.swift](/Users/zpc/projects/elsepage/Sources/Persistence/BrainRepositories.swift)、[JournalRepositories.swift](/Users/zpc/projects/elsepage/Sources/Persistence/JournalRepositories.swift)、[LocalDataWipeService.swift](/Users/zpc/projects/elsepage/Sources/Persistence/LocalDataWipeService.swift)、[ProviderConfigurationRepository.swift](/Users/zpc/projects/elsepage/Sources/Persistence/ProviderConfigurationRepository.swift)、[ReflectionRepositories.swift](/Users/zpc/projects/elsepage/Sources/Persistence/ReflectionRepositories.swift)、[ReflectionTestEnvironment.swift](/Users/zpc/projects/elsepage/Sources/Persistence/ReflectionTestEnvironment.swift)、[Repositories.swift](/Users/zpc/projects/elsepage/Sources/Persistence/Repositories.swift)、[RoutingTraceRepository.swift](/Users/zpc/projects/elsepage/Sources/Persistence/RoutingTraceRepository.swift)、[TextAnnotationRepository.swift](/Users/zpc/projects/elsepage/Sources/Persistence/TextAnnotationRepository.swift)
- `Sources/ReaderAgent`：[AgentCitationValidator.swift](/Users/zpc/projects/elsepage/Sources/ReaderAgent/AgentCitationValidator.swift)、[BrainProjectionService.swift](/Users/zpc/projects/elsepage/Sources/ReaderAgent/BrainProjectionService.swift)、[ReaderAgent.swift](/Users/zpc/projects/elsepage/Sources/ReaderAgent/ReaderAgent.swift)、[ReaderAgentPolicy.swift](/Users/zpc/projects/elsepage/Sources/ReaderAgent/ReaderAgentPolicy.swift)、[ReaderAgentSystemPrompt.swift](/Users/zpc/projects/elsepage/Sources/ReaderAgent/ReaderAgentSystemPrompt.swift)、[ReaderHelp.swift](/Users/zpc/projects/elsepage/Sources/ReaderAgent/ReaderHelp.swift)、[ReaderHelpService.swift](/Users/zpc/projects/elsepage/Sources/ReaderAgent/ReaderHelpService.swift)、[ReflectionSummaryService.swift](/Users/zpc/projects/elsepage/Sources/ReaderAgent/ReflectionSummaryService.swift)、[SessionContextBuilder.swift](/Users/zpc/projects/elsepage/Sources/ReaderAgent/SessionContextBuilder.swift)
- `Sources/ReaderCore`：[AnnotationMenuPlacer.swift](/Users/zpc/projects/elsepage/Sources/ReaderCore/AnnotationMenuPlacer.swift)、[BookLocator.swift](/Users/zpc/projects/elsepage/Sources/ReaderCore/BookLocator.swift)、[ReaderCoordination.swift](/Users/zpc/projects/elsepage/Sources/ReaderCore/ReaderCoordination.swift)、[TextAnnotation.swift](/Users/zpc/projects/elsepage/Sources/ReaderCore/TextAnnotation.swift)
- `Sources/ReadingSessionCore`：[ReadingSession.swift](/Users/zpc/projects/elsepage/Sources/ReadingSessionCore/ReadingSession.swift)、[ReadingSessionService.swift](/Users/zpc/projects/elsepage/Sources/ReadingSessionCore/ReadingSessionService.swift)
- `Sources/ReflectionCore`：[Journal.swift](/Users/zpc/projects/elsepage/Sources/ReflectionCore/Journal.swift)、[JournalEntryService.swift](/Users/zpc/projects/elsepage/Sources/ReflectionCore/JournalEntryService.swift)、[JournalStructuredParser.swift](/Users/zpc/projects/elsepage/Sources/ReflectionCore/JournalStructuredParser.swift)、[PersonalDataExporter.swift](/Users/zpc/projects/elsepage/Sources/ReflectionCore/PersonalDataExporter.swift)、[Reflection.swift](/Users/zpc/projects/elsepage/Sources/ReflectionCore/Reflection.swift)、[ReflectionArchive.swift](/Users/zpc/projects/elsepage/Sources/ReflectionCore/ReflectionArchive.swift)、[ReflectionSummary.swift](/Users/zpc/projects/elsepage/Sources/ReflectionCore/ReflectionSummary.swift)、[ReflectionTextDraft.swift](/Users/zpc/projects/elsepage/Sources/ReflectionCore/ReflectionTextDraft.swift)、[Streak.swift](/Users/zpc/projects/elsepage/Sources/ReflectionCore/Streak.swift)、[StreamingResponseBuffer.swift](/Users/zpc/projects/elsepage/Sources/ReflectionCore/StreamingResponseBuffer.swift)、[TextReflectionSubmissionService.swift](/Users/zpc/projects/elsepage/Sources/ReflectionCore/TextReflectionSubmissionService.swift)、[ThoughtsArchiveProjection.swift](/Users/zpc/projects/elsepage/Sources/ReflectionCore/ThoughtsArchiveProjection.swift)、[TodayProductState.swift](/Users/zpc/projects/elsepage/Sources/ReflectionCore/TodayProductState.swift)、[VoiceReflectionSubmissionService.swift](/Users/zpc/projects/elsepage/Sources/ReflectionCore/VoiceReflectionSubmissionService.swift)
- `Sources/RetrievalCore`：[BookIndexStatus.swift](/Users/zpc/projects/elsepage/Sources/RetrievalCore/BookIndexStatus.swift)、[RetrievalModels.swift](/Users/zpc/projects/elsepage/Sources/RetrievalCore/RetrievalModels.swift)、[RetrievalServices.swift](/Users/zpc/projects/elsepage/Sources/RetrievalCore/RetrievalServices.swift)、[SmallToBigExpander.swift](/Users/zpc/projects/elsepage/Sources/RetrievalCore/SmallToBigExpander.swift)、[StructureAwareChunker.swift](/Users/zpc/projects/elsepage/Sources/RetrievalCore/StructureAwareChunker.swift)
- `Sources/SpeechCore`：[FileTranscriptionService.swift](/Users/zpc/projects/elsepage/Sources/SpeechCore/FileTranscriptionService.swift)、[SpeechBiasTerms.swift](/Users/zpc/projects/elsepage/Sources/SpeechCore/SpeechBiasTerms.swift)、[SpeechRecognitionAvailability.swift](/Users/zpc/projects/elsepage/Sources/SpeechCore/SpeechRecognitionAvailability.swift)、[SpeechRecognitionConfiguration.swift](/Users/zpc/projects/elsepage/Sources/SpeechCore/SpeechRecognitionConfiguration.swift)、[SystemSpeechTranscriptionProvider.swift](/Users/zpc/projects/elsepage/Sources/SpeechCore/SystemSpeechTranscriptionProvider.swift)、[VoiceReflectionState.swift](/Users/zpc/projects/elsepage/Sources/SpeechCore/VoiceReflectionState.swift)
- `Sources/readloop-bench`：[main.swift](/Users/zpc/projects/elsepage/Sources/readloop-bench/main.swift)
- `Sources/readloop-bench-compare`：[main.swift](/Users/zpc/projects/elsepage/Sources/readloop-bench-compare/main.swift)

### Tests（68）

- `Tests/AgentProviderTests`：[AgentCitationValidatorTests.swift](/Users/zpc/projects/elsepage/Tests/AgentProviderTests/AgentCitationValidatorTests.swift)、[AgentProviderTests.swift](/Users/zpc/projects/elsepage/Tests/AgentProviderTests/AgentProviderTests.swift)、[AnthropicModelClientTests.swift](/Users/zpc/projects/elsepage/Tests/AgentProviderTests/AnthropicModelClientTests.swift)、[ContextAssemblerTests.swift](/Users/zpc/projects/elsepage/Tests/AgentProviderTests/ContextAssemblerTests.swift)、[ContextCandidateRankerTests.swift](/Users/zpc/projects/elsepage/Tests/AgentProviderTests/ContextCandidateRankerTests.swift)、[ContextRoutingTests.swift](/Users/zpc/projects/elsepage/Tests/AgentProviderTests/ContextRoutingTests.swift)、[HybridRetrievalTests.swift](/Users/zpc/projects/elsepage/Tests/AgentProviderTests/HybridRetrievalTests.swift)、[ModelClientRoutingTests.swift](/Users/zpc/projects/elsepage/Tests/AgentProviderTests/ModelClientRoutingTests.swift)、[ReaderHelpServiceTests.swift](/Users/zpc/projects/elsepage/Tests/AgentProviderTests/ReaderHelpServiceTests.swift)、[ReflectionSummaryServiceTests.swift](/Users/zpc/projects/elsepage/Tests/AgentProviderTests/ReflectionSummaryServiceTests.swift)、[TranscriptPolishServiceTests.swift](/Users/zpc/projects/elsepage/Tests/AgentProviderTests/TranscriptPolishServiceTests.swift)
- `Tests/AgentRuntimeTests`：[AgentRuntimeTests.swift](/Users/zpc/projects/elsepage/Tests/AgentRuntimeTests/AgentRuntimeTests.swift)
- `Tests/BenchCoreTests`：[BenchCompareTests.swift](/Users/zpc/projects/elsepage/Tests/BenchCoreTests/BenchCompareTests.swift)、[BenchCoreTests.swift](/Users/zpc/projects/elsepage/Tests/BenchCoreTests/BenchCoreTests.swift)、[BenchJudgeTests.swift](/Users/zpc/projects/elsepage/Tests/BenchCoreTests/BenchJudgeTests.swift)
- `Tests/ReadLoopCoreTests`：[AccessibilitySupportTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/AccessibilitySupportTests.swift)、[AchievementTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/AchievementTests.swift)、[AgentCitationPersistenceTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/AgentCitationPersistenceTests.swift)、[AgentDiscussionCountTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/AgentDiscussionCountTests.swift)、[AnnotationMenuPlacerTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/AnnotationMenuPlacerTests.swift)、[AnthropicProviderPersistenceTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/AnthropicProviderPersistenceTests.swift)、[AudioFileStoreTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/AudioFileStoreTests.swift)、[AudioWaveformTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/AudioWaveformTests.swift)、[BookIndexPersistenceTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/BookIndexPersistenceTests.swift)、[BookIndexStatusTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/BookIndexStatusTests.swift)、[BrainPersistenceTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/BrainPersistenceTests.swift)、[BrainProjectionTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/BrainProjectionTests.swift)、[ChapterTitleTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/ChapterTitleTests.swift)、[CrossBookRetrievalTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/CrossBookRetrievalTests.swift)、[ImportHardeningTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/ImportHardeningTests.swift)、[InFlightReplyTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/InFlightReplyTests.swift)、[JournalStructuredTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/JournalStructuredTests.swift)、[LexicalSearchCJKTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/LexicalSearchCJKTests.swift)、[LibraryStatsTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/LibraryStatsTests.swift)、[LocalBookRetrieverRerankTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/LocalBookRetrieverRerankTests.swift)、[LocalDataWipeTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/LocalDataWipeTests.swift)、[LocatorAndRestorationTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/LocatorAndRestorationTests.swift)、[OnboardingFlowTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/OnboardingFlowTests.swift)、[OpenAICompatibleEmbeddingProviderTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/OpenAICompatibleEmbeddingProviderTests.swift)、[OpenAICompatibleModelClientTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/OpenAICompatibleModelClientTests.swift)、[PersistenceHardeningTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/PersistenceHardeningTests.swift)、[PersonalDataExporterTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/PersonalDataExporterTests.swift)、[ProductLoopIntegrationTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/ProductLoopIntegrationTests.swift)、[ReaderContextRouterTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/ReaderContextRouterTests.swift)、[ReaderCoordinationTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/ReaderCoordinationTests.swift)、[ReaderFoundationTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/ReaderFoundationTests.swift)、[ReaderHelpContextTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/ReaderHelpContextTests.swift)、[ReflectionArchiveTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/ReflectionArchiveTests.swift)、[ReflectionLoopServiceTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/ReflectionLoopServiceTests.swift)、[ReflectionPersistenceTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/ReflectionPersistenceTests.swift)、[ReflectionTestEnvironmentTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/ReflectionTestEnvironmentTests.swift)、[ReflectionTextDraftTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/ReflectionTextDraftTests.swift)、[RetrievalChunkingTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/RetrievalChunkingTests.swift)、[RetrievalRankingTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/RetrievalRankingTests.swift)、[RetrievalSemanticPipelineTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/RetrievalSemanticPipelineTests.swift)、[RoutingTracePersistenceTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/RoutingTracePersistenceTests.swift)、[SessionContextBuilderTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/SessionContextBuilderTests.swift)、[SiliconFlowRerankerTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/SiliconFlowRerankerTests.swift)、[SmallToBigExpanderTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/SmallToBigExpanderTests.swift)、[SpeechRecognitionConfigurationTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/SpeechRecognitionConfigurationTests.swift)、[StreakCalculatorTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/StreakCalculatorTests.swift)、[StreamingResponseBufferTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/StreamingResponseBufferTests.swift)、[TestFixtures.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/TestFixtures.swift)、[TextAnnotationPersistenceTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/TextAnnotationPersistenceTests.swift)、[TodayReflectionPromptTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/TodayReflectionPromptTests.swift)、[VoiceReflectionTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/VoiceReflectionTests.swift)、[XcodeProjectMembershipTests.swift](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/XcodeProjectMembershipTests.swift)
- `Tests/ReadiumIntegrationTests`：[ReadiumPublicationIntegrationTests.swift](/Users/zpc/projects/elsepage/Tests/ReadiumIntegrationTests/ReadiumPublicationIntegrationTests.swift)

### 关键文档与配置索引

- [AGENTS.md](/Users/zpc/projects/elsepage/AGENTS.md)
- [CLAUDE.md](/Users/zpc/projects/elsepage/CLAUDE.md)
- [README.md](/Users/zpc/projects/elsepage/README.md)
- [CONTRIBUTING.md](/Users/zpc/projects/elsepage/CONTRIBUTING.md)
- [ReadLoop_PRD.md](/Users/zpc/projects/elsepage/ReadLoop_PRD.md)
- [ReadLoop_Technical_Design.md](/Users/zpc/projects/elsepage/ReadLoop_Technical_Design.md)
- [ARCHITECTURE.md](/Users/zpc/projects/elsepage/ARCHITECTURE.md)
- [Package.swift](/Users/zpc/projects/elsepage/Package.swift)
- [Package.resolved](/Users/zpc/projects/elsepage/Package.resolved)
- [project.yml](/Users/zpc/projects/elsepage/project.yml)
- [App/Info.plist](/Users/zpc/projects/elsepage/App/Info.plist)
- [ReadLoop.xcodeproj/project.pbxproj](/Users/zpc/projects/elsepage/ReadLoop.xcodeproj/project.pbxproj)
- [ReadLoop.xcodeproj/xcshareddata/xcschemes/ReadLoop.xcscheme](/Users/zpc/projects/elsepage/ReadLoop.xcodeproj/xcshareddata/xcschemes/ReadLoop.xcscheme)
- [.planning/PROJECT.md](/Users/zpc/projects/elsepage/.planning/PROJECT.md)
- [.planning/ROADMAP.md](/Users/zpc/projects/elsepage/.planning/ROADMAP.md)
- [.planning/STATE.md](/Users/zpc/projects/elsepage/.planning/STATE.md)
- [.planning/LAUNCH-READINESS.md](/Users/zpc/projects/elsepage/.planning/LAUNCH-READINESS.md)

仓库已有docs文档索引（研究开始时42份，按功能与历史材料对照；不把过期“Implemented”标记当事实）：

- [docs/ANNOTATION_MODEL_SPEC.md](/Users/zpc/projects/elsepage/docs/ANNOTATION_MODEL_SPEC.md)
- [docs/ANTI_SPOILER_SPEC.md](/Users/zpc/projects/elsepage/docs/ANTI_SPOILER_SPEC.md)
- [docs/DEBUG-LOOP.md](/Users/zpc/projects/elsepage/docs/DEBUG-LOOP.md)
- [docs/DEVELOPMENT.md](/Users/zpc/projects/elsepage/docs/DEVELOPMENT.md)
- [docs/ELSEPAGE_SWIFT_AGENT_RUNTIME_GUIDE.md](/Users/zpc/projects/elsepage/docs/ELSEPAGE_SWIFT_AGENT_RUNTIME_GUIDE.md)
- [docs/HANDOFF-2026-09-07-interaction-perf.md](/Users/zpc/projects/elsepage/docs/HANDOFF-2026-09-07-interaction-perf.md)
- [docs/INTERACTION-PERF-MANUAL-TEST.md](/Users/zpc/projects/elsepage/docs/INTERACTION-PERF-MANUAL-TEST.md)
- [docs/INTERACTION_PERFORMANCE_SPEC.md](/Users/zpc/projects/elsepage/docs/INTERACTION_PERFORMANCE_SPEC.md)
- [docs/PROJECT_HIGHLIGHTS.md](/Users/zpc/projects/elsepage/docs/PROJECT_HIGHLIGHTS.md)
- [docs/READER_EXPERIENCE_OPTIMIZATION_PLAN.md](/Users/zpc/projects/elsepage/docs/READER_EXPERIENCE_OPTIMIZATION_PLAN.md)
- [docs/READER_FOUNDATION_XCODE_GATE.md](/Users/zpc/projects/elsepage/docs/READER_FOUNDATION_XCODE_GATE.md)
- [docs/READER_HELP_SPEC.md](/Users/zpc/projects/elsepage/docs/READER_HELP_SPEC.md)
- [docs/adr/0001-llm-context-routing.md](/Users/zpc/projects/elsepage/docs/adr/0001-llm-context-routing.md)
- [docs/adr/0002-client-interaction-performance.md](/Users/zpc/projects/elsepage/docs/adr/0002-client-interaction-performance.md)
- [docs/assets/branding/README.md](/Users/zpc/projects/elsepage/docs/assets/branding/README.md)
- [docs/bench/README.md](/Users/zpc/projects/elsepage/docs/bench/README.md)
- [docs/bench/REGRESSION.md](/Users/zpc/projects/elsepage/docs/bench/REGRESSION.md)
- [docs/bench/judge-prompt.md](/Users/zpc/projects/elsepage/docs/bench/judge-prompt.md)
- [docs/brain.md](/Users/zpc/projects/elsepage/docs/brain.md)
- [docs/exec-plans/active/client-interaction-performance.md](/Users/zpc/projects/elsepage/docs/exec-plans/active/client-interaction-performance.md)
- [docs/exec-plans/active/concurrent-p0-worktrees.md](/Users/zpc/projects/elsepage/docs/exec-plans/active/concurrent-p0-worktrees.md)
- [docs/exec-plans/active/context-engineering-evolution.md](/Users/zpc/projects/elsepage/docs/exec-plans/active/context-engineering-evolution.md)
- [docs/exec-plans/active/context-planner-protocol-refactor.md](/Users/zpc/projects/elsepage/docs/exec-plans/active/context-planner-protocol-refactor.md)
- [docs/exec-plans/active/llm-context-routing.md](/Users/zpc/projects/elsepage/docs/exec-plans/active/llm-context-routing.md)
- [docs/exec-plans/active/local-book-retrieval.md](/Users/zpc/projects/elsepage/docs/exec-plans/active/local-book-retrieval.md)
- [docs/exec-plans/active/memory-phase-worktrees.md](/Users/zpc/projects/elsepage/docs/exec-plans/active/memory-phase-worktrees.md)
- [docs/exec-plans/active/overnight-mvp.md](/Users/zpc/projects/elsepage/docs/exec-plans/active/overnight-mvp.md)
- [docs/exec-plans/active/product-loop-integration.md](/Users/zpc/projects/elsepage/docs/exec-plans/active/product-loop-integration.md)
- [docs/maintenance/repository-hygiene-2026-10-22.md](/Users/zpc/projects/elsepage/docs/maintenance/repository-hygiene-2026-10-22.md)
- [docs/prototypes/README.md](/Users/zpc/projects/elsepage/docs/prototypes/README.md)
- [docs/providers/VERIFICATION-MATRIX.md](/Users/zpc/projects/elsepage/docs/providers/VERIFICATION-MATRIX.md)
- [docs/release/APP-REVIEW-NOTES.md](/Users/zpc/projects/elsepage/docs/release/APP-REVIEW-NOTES.md)
- [docs/release/APP-STORE-METADATA.md](/Users/zpc/projects/elsepage/docs/release/APP-STORE-METADATA.md)
- [docs/release/PRIVACY-CLAIMS-EVIDENCE.md](/Users/zpc/projects/elsepage/docs/release/PRIVACY-CLAIMS-EVIDENCE.md)
- [docs/release/PRIVACY-POLICY.en.md](/Users/zpc/projects/elsepage/docs/release/PRIVACY-POLICY.en.md)
- [docs/release/PRIVACY-POLICY.zh-Hans.md](/Users/zpc/projects/elsepage/docs/release/PRIVACY-POLICY.zh-Hans.md)
- [docs/release/UAT-CHECKLIST.md](/Users/zpc/projects/elsepage/docs/release/UAT-CHECKLIST.md)
- [docs/release/VERSIONING.md](/Users/zpc/projects/elsepage/docs/release/VERSIONING.md)
- [docs/testing/annotations/2026-09-13-annotation-model-refactor-checklist.md](/Users/zpc/projects/elsepage/docs/testing/annotations/2026-09-13-annotation-model-refactor-checklist.md)
- [docs/testing/reader-help/2026-09-13-delivery-checklist.md](/Users/zpc/projects/elsepage/docs/testing/reader-help/2026-09-13-delivery-checklist.md)
- [docs/testing/voice/2026-09-13-delivery-checklist.md](/Users/zpc/projects/elsepage/docs/testing/voice/2026-09-13-delivery-checklist.md)
- [docs/testing/voice/2026-10-09-transcription-measurement.md](/Users/zpc/projects/elsepage/docs/testing/voice/2026-10-09-transcription-measurement.md)

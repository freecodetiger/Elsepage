# UI/UX 重构边界与回归风险

首次研究只新增设计文档，没有实施下列产品变更、修复业务缺口或确定新交互。风险分级是基于耦合与用户数据后果的工程判断，不是已完成UX审计。基线与实际测试见 [README](README.md)。

后续验证维护例外：用户授权后，已修正既有 iOS 集成测试中的旧 API 引用，13 个测试实际通过；未修改产品实现。下文保留首次发现及风险背景，R11 的原编译阻塞现已解除。另已补装GSD角色并恢复Device基础交互，正式业务路径尚未补验，细节见 [运行验证恢复记录](00-runtime-verification.md)。

## 1. 可以相对安全调整的部分

前提是只改展示，不改变Model所有权、持久化、任务触发与呈现生命周期：

| 相对低风险区域 | 可隔离的展示边界 | 需要保留的约束 |
| --- | --- | --- |
| 书架卡片元数据排版、空状态文案 | LibraryGridView / LibraryView | 每书稳定BookID、cover task、独立补写按钮、删除入口和无障碍label |
| 想法卡片与分组标题 | ThoughtCard / archiveSection | summary fallback、原文优先级、搜索/分组重置selectedEntry；不能改动reload副作用 |
| 我的页分区标题/徽章视觉 | BrainItemRow / badgeRow / streakBadge | 每种状态标签、来源性质与置信度、非空/空态语义、成就真实触发 |
| 设置状态行与静态说明 | SettingsView.statusRow | 角色实际配置状态、Key不可回显、危险操作的范围与确认 |
| DesignSystem token 的小范围试验 | ElsepageTheme / ElsepageComponents | 白/黑/柔和阅读主题独立，动态字号、对比度、44pt、Reduce Motion、UIKit显式字体/颜色 |

“相对低风险”不表示可以绕过验证；全局token改变会传播到所有页面，若连UIKit富文本、阅读器纸色一起更换，应升级为中高风险。

## 2. 风险登记

| ID / 等级 | 模块与触发条件 | 回归后果与源码证据 | 后续重构边界 / 验证要求 |
| --- | --- | --- | --- |
| R01 高 | AppShell、三NavigationStack、push与fullScreenCover混合；移动页面或替换dismiss | 退出错误容器、切错Tab、会话结束漏写、反思关闭后不退出阅读器。[根cover](/Users/zpc/projects/elsepage/App/AppShell.swift:38)；[书架push](/Users/zpc/projects/elsepage/App/Library/LibraryView.swift:100)；[反思关闭后dismiss](/Users/zpc/projects/elsepage/App/Reader/ReaderScreen.swift:104) | 保留ReaderModel身份和入口上下文；逐一验证书架打开/引导打开/来源打开，完成和取消两条返回链。不要以新Router掩盖现有副作用 |
| R02 高 | 书籍导入/删除入口、文件选择器、补写入口 | 误导用户以为只移除封面，实际级联删除反思/会话；staging、重复与多次触发有数据后果。[importBook](/Users/zpc/projects/elsepage/App/Library/LibraryModel.swift:105)；[delete](/Users/zpc/projects/elsepage/App/Library/LibraryModel.swift:219)；[原子补偿](/Users/zpc/projects/elsepage/Sources/AppInfrastructure/BookImporter.swift:14) | UI保持既有服务；测试重复/损坏/文件权限/删除失败，显示真实删除范围。UI-only变更不重写指纹或文件事务 |
| R03 高 | ReaderScreen、ReadiumReaderView、ReadiumServices；改safe area/手势/首帧/返回 | Locator错位、翻页竞争、缓存身份错误、打开失败白屏；isPrepared并非WebKit已绘制；结束会话失败返回nil当前仍dismiss。[open](/Users/zpc/projects/elsepage/App/Reader/ReadiumReaderView.swift:46)；[finishReading](/Users/zpc/projects/elsepage/App/Reader/ReaderScreen.swift:244) | 保留UIKit嵌套、Locator JSON与navigator生命周期；不要复用同一个VC跨打开；真机长书、旋转、后台、首开/复开与脚注/链接回跳专项 |
| R04 极高 | AnnotationRange、菜单锚点、JS命中、Note双态、多次快速编辑 | 划错文本、删错层、空文本丢失、过期写回；UI投影与legacy镜像同时存在，Note不是Highlight附属。[replaceAnnotation](/Users/zpc/projects/elsepage/App/Reader/ReaderModel.swift:253)；[镜像写入](/Users/zpc/projects/elsepage/Sources/Persistence/TextAnnotationRepository.swift:29)；[编辑生命周期](/Users/zpc/projects/elsepage/App/Reader/AnnotationUI.swift:434) | 不改变range identity/JSON/表；维持一菜单互斥、旋转后台清锚、独立层删除。覆盖同Range多笔记、部分重叠、快速换色/追加/切条/关闭/撤销/重开，DB断言与视觉共同验证 |
| R05 极高 | AgentMarkdownText、Evidence、引用链接、来源读取 | 把个人推断装成书证据、跳错书/位置、技术citation块泄露；旧反思locator=nil，Brain不可引用。[校验](/Users/zpc/projects/elsepage/Sources/ReaderAgent/AgentCitationValidator.swift:29)；[证据映射](/Users/zpc/projects/elsepage/Sources/ContextEngineering/ContextAssembler.swift:101)；[同书回跳约束](/Users/zpc/projects/elsepage/App/Thoughts/ThoughtsView.swift:305) | 维持message-scoped evidence/citation、已读边界；附近/书段/过去表达分开；不得为视觉统一补造locator。引用真跑需Key；校验测试不能替代回跳体验 |
| R06 高 | Provider/RAG设置、Onboarding、想法页自动补齐 | 配置字段丢失、Key残留、配置变动导致意外外发/批量请求、把已保存当已连接。[save与Key回滚](/Users/zpc/projects/elsepage/App/Settings/ProviderSettingsModel.swift:96)；[角色启停](/Users/zpc/projects/elsepage/App/Settings/RAGSettingsModel.swift)；[自动补齐](/Users/zpc/projects/elsepage/App/Thoughts/ThoughtsModel.swift:95) | 保留chat/RAG共享配置行的字段携带；离页清transient secrets；进入页面不能意外增加load次数；明确用户动作何时发请求。真实Key通过安全工具提供，不入文档 |
| R07 极高 | ReflectionConversationModel、ThoughtsModel、MyMindModel、异步Brain | 原文被派生内容覆盖、重复回应、删除后显示旧数据、Brain更新时序误导；页面加载可能触发LLM。[保存](/Users/zpc/projects/elsepage/App/Reflection/SessionReflectionSheet.swift:593)；[in-flight仲裁](/Users/zpc/projects/elsepage/Sources/ReaderAgent/ReaderAgent.swift:176)；[异步投影](/Users/zpc/projects/elsepage/Sources/ReaderAgent/BrainProjectionService.swift:28) | 保留stable ID、原文/整理稿/概要分层、最后轮删除；不能把completed当Brain完成。详情采用值快照、列表reload和异步投影无订阅，刷新与数据同步需专项核查 |
| R08 极高 | 数据清理、导出、启动/索引恢复 | 永久数据损失、跨存储部分清除、假“恢复成功”。[wipe](/Users/zpc/projects/elsepage/App/Settings/DataSettingsModel.swift:176)；[DB后Keychain](/Users/zpc/projects/elsepage/Sources/Persistence/LocalDataWipeService.swift:18)；[resume](/Users/zpc/projects/elsepage/App/Reader/ReadiumBookIndexer.swift:119) | 区分删录音/删书/清记忆/全清；保留两阶段确认；不把导出称备份还原。故障测试必须断言DB与文件，旧用户迁移/强杀需设备验证 |
| R09 高 | UIKit输入/选择、语音、音频附件、键盘与滚动 | 中文IME未提交被发出、草稿复活/丢失、音频引用悬空、长文本卡顿。[ReflectionTextSynchronization](/Users/zpc/projects/elsepage/App/Reflection/SessionReflectionSheet.swift:17)；[SelectionKeeper](/Users/zpc/projects/elsepage/App/DesignSystem/SelectableText.swift:620)；[两阶段音频](/Users/zpc/projects/elsepage/Sources/AppInfrastructure/AudioFileStore.swift) | 不把UITextView直接换TextEditor而忽略markedText/选区/量高；保留原话、端上zh-CN和模型缺失提示；真机权限/中断/续录/多段合并/波形seek专项 |
| R10 中高 | 全局token、动态字号、语义色、Reduce Motion、触感 | 低对比度、按钮触达小、无障碍信息丢失、阅读字级改变；EPUB字号不随系统Dynamic Type。[token](/Users/zpc/projects/elsepage/App/DesignSystem/ElsepageTheme.swift:5)；[palette](/Users/zpc/projects/elsepage/Sources/AppInfrastructure/AccessibilitySupport.swift:64)；[EPUB偏好映射](/Users/zpc/projects/elsepage/App/Reader/ReadiumReaderView.swift:416) | 主壳与正文分层；包级对比度测试+AX5/VoiceOver/暗色/减少动态设备走查。局部固定字号不能据此声称全站Dynamic Type完整 |
| R11 高（验收基础） | 工程生成、Scheme、iOS集成测试 | swift test绿不能替代App和iOS验证。首次发现的ReflectionDraft旧引用编译失败已通过测试维护解除，13个集成测试通过；仍无项目XCUITest基线。[当前测试](/Users/zpc/projects/elsepage/Tests/ReadiumIntegrationTests/ReadiumPublicationIntegrationTests.swift:127)；[修复证据](00-runtime-verification.md)；[产物配置](/Users/zpc/projects/elsepage/project.yml:34)；[实际PRODUCT_NAME](/Users/zpc/projects/elsepage/ReadLoop.xcodeproj/project.pbxproj:956) | 构建与测试结果仅针对现有工程；不可重新生成工程后声称同样通过。保持包级/iOS集成/真实UI三种证据独立；本轮没有修改工程配置 |
| R12 高（范围控制） | 旧文档与不可达能力进入“视觉重构” | 无意加入新功能或改数据语义：Journal编辑、Brain继续想想、opt-out等可能被设计稿假定存在。[孤立讨论Sheet](/Users/zpc/projects/elsepage/App/MyMind/MyMindView.swift:1170)；[无UI调用的编辑服务](/Users/zpc/projects/elsepage/App/Thoughts/ThoughtsModel.swift:161) | 不把缺口修复混入纯UI工作；先由产品决定保留/移除占位/后续实现。与P1–P9冲突需先PRD记录，本次无豁免或实现改动 |

## 3. 已有缺口与必须保持诚实的状态

这些问题是首次研究发现；除注明的测试维护外，**没有修复产品实现**：

- **首次运行证实，后续测试与基础交互已恢复**：原 iOS 集成测试因 ReflectionDraft 旧引用编译失败，exit65；修正为当前 ReflectionTextDraft API 后，13 个集成测试通过、exit0。App build 原本成功。原模拟器UI通道连续 cgWindowNotFound；第一次 Device 恢复尝试控件读取两次超时，第二轮串行准备后控件/输入/点击/重启后读取通过。没有修复原CUA提供方，也没有App崩溃证据。见 [恢复证据](00-runtime-verification.md)。
- **可达性源码证实**：BrainDiscussionSheet无展示点；选区reflectOnSelection无工具栏调用；Journal用户编辑服务无当前UI入口。
- **数据语义源码证实**：Memory“忘记”为硬删除；needsReview仍可被BrainRetriever召回；过去Reflection证据无Locator；JSON导出不包含完整新Range模型，也无还原入口。
- **恢复接线存在具体矛盾**：BookIndexCoordinator对持久化 `.embedding` 状态选择 `.embed`，但BookIndexPipeline.embed入口仅接受lexicalReady/ready，直接返回。中断语义索引可能停留旧状态；本次只有lexicalReady，无真实Embedding Key，未实测此中断路径。不能把“有resume方法”写成全部索引状态已恢复验证。证据：[action(for:)](/Users/zpc/projects/elsepage/App/Reader/ReadiumBookIndexer.swift:157)；[embed(bookID:) guard](/Users/zpc/projects/elsepage/Sources/RetrievalCore/RetrievalServices.swift:190)。
- **需进一步故障验证**：Note快速切换未写文本、乐观标注多次写入排序/删除撤销、legacy镜像删除一致性、全清中Keychain失败后的部分完成。这些是风险项，不在缺少独立失败证据时宣称确定Bug。
- **成就注入存在入口差异**：AppShell的全屏Reader传入achievements；LibraryView的push Reader未传，ReaderScreen.init会把model.achievements设为默认nil。书架结束阅读后的反思与其他入口可能缺少相同成就处理，不能声明各入口行为完全一致。源码：[LibraryView.swift:101](/Users/zpc/projects/elsepage/App/Library/LibraryView.swift:101)、[ReaderScreen.swift:18](/Users/zpc/projects/elsepage/App/Reader/ReaderScreen.swift:18)、[AppShell.swift:39](/Users/zpc/projects/elsepage/App/AppShell.swift:39)。本次未运行反思后的成就验证。
- **不能用注释代替实现**：BrainProjectionService注释称“事务执行”，实际多次repository调用分开write，不能声明一次投影中item+evidence+revision全部原子提交。证据：[execute](/Users/zpc/projects/elsepage/Sources/ReaderAgent/BrainProjectionService.swift:126)；[save与attachEvidence独立write](/Users/zpc/projects/elsepage/Sources/Persistence/BrainRepositories.swift:40)。
- **未量化**：真实长期记忆质量、跨书连接准确率、首帧p95、键盘卡顿、中文/英文语音准确率。模拟器单次约1239ms打开数据不是性能SLO或真机基线。

## 4. 后续变更的证据要求（本阶段未执行开发）

| 改动区域 | 已有有价值的测试证据 | 仍必须补的运行证据 |
| --- | --- | --- |
| 导入/位置/标注 | [导入失败与幂等](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/ImportHardeningTests.swift)、[Locator恢复](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/LocatorAndRestorationTests.swift)、[新模型持久化/迁移](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/TextAnnotationPersistenceTests.swift)、[最新值/搜索协调](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/ReaderCoordinationTests.swift) | 实际Files导入、跨资源读书、重叠命中、笔记编辑、旋转、强杀恢复 |
| 反思/对话 | [原文先保存与会话](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/ReflectionLoopServiceTests.swift)、[并发首回](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/InFlightReplyTests.swift)、[包级完整链](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/ProductLoopIntegrationTests.swift)、[DEBUG覆盖边界](/Users/zpc/projects/elsepage/docs/DEBUG-LOOP.md) | 真实界面提交、错误/重试、键盘IME、真实Provider；DEBUG save只验证有限隔离动作 |
| 引用/RAG | [引用校验](/Users/zpc/projects/elsepage/Tests/AgentProviderTests/AgentCitationValidatorTests.swift)、[语义流水线](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/RetrievalSemanticPipelineTests.swift)、[扩展边界](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/SmallToBigExpanderTests.swift)、[临时问答权限](/Users/zpc/projects/elsepage/Tests/AgentProviderTests/ReaderHelpServiceTests.swift) | 真实输出回原文、无Key/断网、当前child边界、跨书旧表达、索引中断恢复 |
| Brain/Journal | [投影/修订](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/BrainProjectionTests.swift)、[持久化](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/BrainPersistenceTests.swift)、[派生与防覆盖](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/JournalStructuredTests.swift) | 有真实看法/问题/记忆时的详情、编辑、来源、删除、退回列表刷新 |
| 音频/无障碍 | [语音领域](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/VoiceReflectionTests.swift)、[音频事务](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/AudioFileStoreTests.swift)、[对比度/标签](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/AccessibilitySupportTests.swift) | 真机录音/端上模型缺失、VoiceOver、AX5、Reduce Motion、暗色及横屏 |
| 数据清理 | [wipe与Keychain fake](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/LocalDataWipeTests.swift)、[导出排除密钥](/Users/zpc/projects/elsepage/Tests/ReadLoopCoreTests/PersonalDataExporterTests.swift) | 可丢弃测试库中注入磁盘/Keychain故障，再检查部分完成和引导重建 |

本次411个Swift Testing + 28个XCTest通过，但没有XCUITest target；App中的多数Model不属于portable package tests。`XcodeProjectMembershipTests`只查文件名出现在pbxproj，不验证SwiftUI呈现、手势或实际编译行为。

## 5. 回滚与兼容边界

为后续审计提供约束，不是本轮实施计划：视觉改动应可逐功能回滚，保留View调用的Model/Service契约、Locator/Range与数据库schema。若以后需要迁移数据或更改删除/记忆/自动请求语义，必须作为单独产品/架构变更评估，先准备旧数据样本、前后数据库与文件证据、恢复策略，不能只靠revert UI代码回滚用户已写入的新数据。

首次研究没有改schema、Prompt、服务、依赖、工程生成或测试源码；保留研究前已有Scheme差异。后续仅维护上述iOS测试旧API引用，没有改变产品实现。进入UX审计前还缺的信息见 [产品认知 §8](00-product-understanding.md)。

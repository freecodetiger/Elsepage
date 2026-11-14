# 完整页面与界面状态清单

基线：2026-11-14，`000f286` + 研究前已有 Scheme 差异。清单按 **App 全部呈现点、用户任务和状态分支** 建立；页面存在不等于运行已验证。运行证据编号 P01–P16 见 [README](README.md)。业务事实见 [产品与架构](00-product-understanding.md)，风险编号见 [风险表](00-refactor-risks.md)。

I = Implemented；P = Partial；Planned / Unknown 完整拼写。表中“入口 → 退出”同时说明呈现容器；主任务/交互、业务状态、源码符号、复用组件及风险分别记录。无证据编号的页面均为源码确认，未完成本次界面验证。

## 1. 启动、引导与书架

| ID / 名称 / 模块 / 状态 | 入口 → 退出 | 主任务与核心交互 | 依赖业务状态 | 源码 / 符号 | 当前组件 | 重构风险 / 本次证据 |
| --- | --- | --- | --- | --- | --- | --- |
| A00 启动状态 / App / I | 进程启动 → 自动进入 Shell；失败无页内重试 | 等待本地书库；阅读错误说明 | library 等 Model 是否组装完成、startupError | [ReadLoopApp.body](/Users/zpc/projects/elsepage/App/ReadLoopApp.swift:9) | ProgressView、ContentUnavailableView | R01/R08；不可用界面无恢复按钮；启动失败未复现 |
| A01 主 Shell / App / I | 启动成功 → 切三个 Tab 或进入阅读器 | 书架/想法/我的，接收外部导入后切书架 | AppTab、readerDestination、onboarding | [AppShell](/Users/zpc/projects/elsepage/App/AppShell.swift:16) | TabView、三个 NavigationStack | R01；P06 |
| O01 导入第一本书 / Onboarding / I | 首启 fullScreenCover → 继续/跳过到 O02 | 选择 EPUB；显示导入中/成功/失败 | flow.step、isImporting、importedBook、importError | [stepContent](/Users/zpc/projects/elsepage/App/Onboarding/OnboardingView.swift:104)；[importEPUB](/Users/zpc/projects/elsepage/App/Onboarding/OnboardingModel.swift:35) | ElsepageIconButton、ProgressView、原生 fileImporter | R02；P01/P02/P03 |
| O02 AI 配置 / Onboarding / I | O01 → 返回上步、连接成功后继续、跳过 | 预设、Model ID、Key；自定义地址；保存并测连接 | ProviderSettingsModel、hasSucceededConnectionTest、isWorking | [providerFields](/Users/zpc/projects/elsepage/App/Onboarding/OnboardingView.swift:143) | Picker、TextField、SecureField、语义反馈 Label | R06；P04；未做真实连接 |
| O03 首次阅读引导 / Onboarding / I | O02 → 打开导入书或稍后回书架 | 指向首次阅读和读后表达，无自动生成示例 | importedBook、completion flag | [primaryAction / finish](/Users/zpc/projects/elsepage/App/Onboarding/OnboardingView.swift:226) | 共享 heading、主按钮 | R01；P05；完成后不重复引导 |
| L01 书架 / Library / I | Tab → push R01；设置 Sheet；反思 Sheet | 浏览/搜索/排序/刷新/导入/删除/补写 | books、visibleBooks、covers、stats、progress、pendingReflection | [LibraryView](/Users/zpc/projects/elsepage/App/Library/LibraryView.swift:31)；[LibraryGridView](/Users/zpc/projects/elsepage/App/Library/LibraryGridView.swift:57) | ElsepageBookCover、ProgressView、原生 Search、Menu | R01/R02；P06；空书架/搜索空态仅源码 |
| L02 系统 EPUB 文件选择器 / Library、Onboarding / I | fileImporter → 选择单书或取消 | 浏览 Files/iCloud/本机，选择 EPUB | UTType.epub、security scoped URL、result | [fileImporter](/Users/zpc/projects/elsepage/App/Library/LibraryView.swift:71)；[fileImporter](/Users/zpc/projects/elsepage/App/Onboarding/OnboardingView.swift:43) | iOS 系统文档选择器 | R02；P02；系统提供器 UI 非 App 自绘 |

## 2. 阅读器、标注与临时问答

| ID / 名称 / 模块 / 状态 | 入口 → 退出 | 主任务与核心交互 | 依赖业务状态 | 源码 / 符号 | 当前组件 | 重构风险 / 本次证据 |
| --- | --- | --- | --- | --- | --- | --- |
| R01 阅读正文 / Reader / I | 书架 push；引导/引用 fullScreenCover →“读到这里”或返回；可能先呈现 F01 | 阅读/翻页/滚动；轻点显隐控制栏；结束会话 | isPrepared、showsControls、preferences、currentLocator、activeSession、scenePhase | [ReaderScreen](/Users/zpc/projects/elsepage/App/Reader/ReaderScreen.swift:31)；[ReadiumReaderView](/Users/zpc/projects/elsepage/App/Reader/ReadiumReaderView.swift:10) | 封面加载占位、UIKit navigator、readerChrome | R01/R03；P07/P08 |
| R02 目录 Sheet / Reader / I | 底栏目录 → 选章跳转并关闭 / 完成 / 下滑 | 层级目录、当前章勾选 | chapters、currentChapterID | [ContentsSheet](/Users/zpc/projects/elsepage/App/Reader/ReaderScreen.swift:307) | NavigationStack、List、medium/large detents | R03/R05；P09（仅一章样书） |
| R03 搜索 Sheet / Reader / I | 顶栏搜索 → 点击结果跳转关闭 / 完成 / 下滑 | 空输入、检索中、无结果、命中列表 | query、isSearching、searchResults、latestRequest token | [ReaderSearchSheet](/Users/zpc/projects/elsepage/App/Reader/ReaderScreen.swift:345)；[search](/Users/zpc/projects/elsepage/App/Reader/ReaderModel.swift:812) | searchable、List、ContentUnavailableView | R03/R05；本次未运行 |
| R04 标注列表 Sheet / Reader / I | 底栏标注 → 高亮跳原位菜单 / 笔记跳原位再编辑 / 完成 | 看原文、颜色、笔记、章节/进度；按原文位置排序 | highlights / notes 投影、chapters | [ReaderAnnotationsSheet](/Users/zpc/projects/elsepage/App/Reader/ReaderScreen.swift:389) | List、颜色圆点、Note 图标 | R04；新模型 notes.highlightID 为 nil，聚合展示需核验 |
| R05 阅读设置 Sheet / Reader / I | 顶栏文字设置 → 完成 / 下滑并保存 | 自动/明亮/柔和/深色；字号、行高、边距；分页/滚动 | ReaderPreferences、savePreferences | [ReaderAppearanceSheet](/Users/zpc/projects/elsepage/App/Reader/ReaderScreen.swift:509) | Form、Slider、分段 Picker、主题按钮 | R03/R10；P10；未遍历全部主题/阅读模式 |
| R06 选区浮动工具栏 / Reader / I | 正文长按 → 点颜色/笔记/问/复制、点外部或导航清理 | 4 色直接高亮、独立笔记、问 AI、复制 | ReaderSelectionContext、range、frame、annotationMenu | [ReaderAnnotationOverlays / SelectionToolbar](/Users/zpc/projects/elsepage/App/Reader/AnnotationUI.swift:47)；[shouldShowMenuForSelection](/Users/zpc/projects/elsepage/App/Reader/ReadiumReaderView.swift:208) | AnchoredMenu、SelectionCatcher、AnnotationMenuPlacer | R03/R04；P11；不是 SwiftUI `.popover` |
| R07 已有高亮菜单 / Reader / I | 点击 decoration / 标注列表跳转 → 换色/删除/点外部 | 只改色或删高亮；不带附属笔记入口 | highlight UUID、anchor、menu grace window | [HighlightMenu](/Users/zpc/projects/elsepage/App/Reader/AnnotationUI.swift:311)；[showHighlightMenu](/Users/zpc/projects/elsepage/App/Reader/ReaderModel.swift:457) | 4 色按钮、锚点 material 浮层 | R04；高亮创建 P14；菜单本次未遍历 |
| R08 重叠消歧菜单 / Reader / I | 命中 Note 与 Highlight 的重叠点 → 选择笔记或高亮 | 决定操作哪一层 | decoration JS hit-test、ReaderAnnotationConflict | [AnnotationConflictMenu](/Users/zpc/projects/elsepage/App/Reader/AnnotationUI.swift:276)；[handleHighlightActivation](/Users/zpc/projects/elsepage/App/Reader/ReaderModel.swift:514) | AnchoredMenu、二选一按钮 | R04；多 Note 候选选择并非完整实现 |
| R09 笔记 Sheet / Reader / I | 选区笔记、下划线、标注列表 → 完成/下滑 finalize | 默认 Markdown 预览；切编辑、续加、切第N条；清空内容触发删除 | noteEditorRequest、effectiveTarget、relatedNotes、text、saveTask | [NoteEditorSheet](/Users/zpc/projects/elsepage/App/Reader/AnnotationUI.swift:434) | AgentMarkdownText、TextEditor、分段 Picker、Menu | R04/R09；P15/P16；文字保存未完成实测 |
| R10 临时“问 AI” Sheet / Reader Help / I | 选区“问” → X 取消并丢弃；不可下滑关闭 | 解释、输入具体问题、追问、重试、复制、存笔记；引用/保存后缩184pt | ReaderHelpModel.state、turns、provenance、latestResponseID、isSaved、saveError | [ReaderHelpSheet](/Users/zpc/projects/elsepage/App/Reader/ReaderHelpSheet.swift:7)；[ReaderHelpModel](/Users/zpc/projects/elsepage/App/Reader/ReaderHelpModel.swift:21) | quoteCard、AgentMarkdownText（上标引用）、输入框、detents | R05/R06；P12/P13，成功/引用待 Key |
| R11 阅读轻提示 / Reader / I | 复制/重叠拒绝/删除/回原文 → 5秒消失；删除时可撤销 | 接收结果反馈、撤销删除快照 | ReaderTransientNotice.Kind、noticeTask | [TransientNoticePill](/Users/zpc/projects/elsepage/App/Reader/AnnotationUI.swift:382)；[showNotice / undoNotice](/Users/zpc/projects/elsepage/App/Reader/ReaderModel.swift:670) | 胶囊浮层、撤销按钮 | R04；不是系统 toast/持久回收站 |

## 3. Reflection 与历史档案

| ID / 名称 / 模块 / 状态 | 入口 → 退出 | 主任务与核心交互 | 依赖业务状态 | 源码 / 符号 | 当前组件 | 重构风险 / 本次证据 |
| --- | --- | --- | --- | --- | --- | --- |
| F01 “留下些什么”编辑 Sheet / Reflection / I | R01结束合格会话或 L01补写 → 今天先不了；保存转F02；阅读结束关闭后再退出阅读器 | 文字/语音、原话/优化版、保存；未配置 AI 仍可存 | SessionReflectionModel.state、draft、isVoiceRecording、summary、locator、draftID | [SessionReflectionSheet](/Users/zpc/projects/elsepage/App/Reflection/SessionReflectionSheet.swift:1066)；[submit](/Users/zpc/projects/elsepage/App/Reflection/SessionReflectionSheet.swift:593) | ReflectionTextEditor、VoiceReflectionControls、header、ElsepageTheme | R01/R07/R09；本次仅隔离保存场景 PASS，正式 Sheet 未走通 |
| F02 已保存反思对话 / Reflection / I | F01保存后 / T02 → 完成或详情返回 | 原文、音频、AI消息、追问、缺回应重试、来源展开、引用、最后一轮删除 | messages、isResponding、streamingResponse、responseProvenance、pendingUserMessage、isDeleted | [ReflectionConversationView](/Users/zpc/projects/elsepage/App/Reflection/SessionReflectionSheet.swift:1300)；[ReflectionConversationModel](/Users/zpc/projects/elsepage/App/Reflection/SessionReflectionSheet.swift:673) | SelectableTextBody、AgentMarkdownText、ReflectionComposer、音频附件 | R05/R07/R09；无本次正式页面证据 |
| F03 语音与音频附件状态 / Reflection / I | F01/F02手动麦克风 → 停止/取消/离开；附件播放或删除 | 点按/长按录音、续录、转写；保存开关；波形seek | VoiceReflectionState、availability、permission、saveAudio、draftAudioURLs、player state | [VoiceReflectionControls](/Users/zpc/projects/elsepage/App/Reflection/VoiceReflectionRecorder.swift:158)；[ReflectionAudioAttachment](/Users/zpc/projects/elsepage/App/Reflection/VoiceReflectionRecorder.swift:574) | micButton、ProgressView、WaveformScrubber、Menu | R09；非独立页面；无真实麦克风验收 |
| T01 想法列表 / Thoughts / I | 想法 Tab → T02 / 设置；返回 Tab | 按时间/书分组，搜索，点卡片，刷新 | entries、isLoading、searchText、grouping；reload可启动补齐 | [ThoughtsView](/Users/zpc/projects/elsepage/App/Thoughts/ThoughtsView.swift:8)；[reload](/Users/zpc/projects/elsepage/App/Thoughts/ThoughtsModel.swift:63) | ThoughtCard、archiveSection、Search、更多菜单、AchievementToast | R06/R07；本次未触达 |
| T02 阅读记录详情 / Thoughts / I | T01卡片 push → 自绘返回；删除整会话后 dismiss；原文回跳 fullScreenCover | 固定概要、原文、对话、可选“这次留下” | ReflectionArchiveEntry快照、journal快照、conversation | [ThoughtRecordDetailView](/Users/zpc/projects/elsepage/App/Thoughts/ThoughtsView.swift:254) | ThoughtRecordHeader、ReflectionConversationView、ThoughtRecordExtras | R01/R05/R07；仅同书 locator 回跳，快照刷新需核验 |
| T03 来源依据展开 / Reflection / I | F02消息下 DisclosureGroup → 折叠/点击引用 | 查看本条回应依据摘要、书段摘录、可用回原文 | AgentResponseProvenance、citations、evidence.locator | [provenance(for:)](/Users/zpc/projects/elsepage/App/Reflection/SessionReflectionSheet.swift:1540) | DisclosureGroup、Label、Button | R05；是详情内状态，不是独立 Evidence 浏览页 |

## 4. 我的、Brain 与习惯

| ID / 名称 / 模块 / 状态 | 入口 → 退出 | 主任务与核心交互 | 依赖业务状态 | 源码 / 符号 | 当前组件 | 重构风险 / 本次证据 |
| --- | --- | --- | --- | --- | --- | --- |
| M01 我的首页 / MyMind / I | 我的 Tab → M02/M03、编辑 Sheet、设置 | 连续阅读/思考、形成中的看法、问题、记忆、成就；默认各3条/展开全部 | MyMindModel、active/retired memories、streaks、achievements | [MyMindView](/Users/zpc/projects/elsepage/App/MyMind/MyMindView.swift:17) | BrainItemRow、MemoryRow、streakBadge、badgeRow | R07/R10；本次未触达 |
| M02 看法详情 / Brain / I | 看法卡 push → 返回 / 删除后返回；编辑另呈Sheet | 当前陈述、状态/时间、我的变化、阅读证据；stable可存为记忆 | Thought快照、evidence、contexts、revisions | [BrainThoughtDetailView](/Users/zpc/projects/elsepage/App/MyMind/MyMindView.swift:740) | BrainRevisionSection、BrainEvidenceSection | R05/R07；继续想想仅按钮，P能力见后表 |
| M03 问题详情 / Brain / I | 问题卡 push → 返回 / 删除；编辑Sheet | 问题/状态/证据；选择非archived看法关联为已解决 | Question快照、answerCandidates、evidence | [BrainQuestionDetailView](/Users/zpc/projects/elsepage/App/MyMind/MyMindView.swift:879) | BrainEvidenceSection、confirmationDialog | R07；无问题历史时间线展示，不能套用M02 |
| M04 看法编辑 Sheet / Brain / I | M02编辑 → 取消/保存后 dismiss | 修改标题/陈述/阶段 | editingThought、selectedStage、非空校验 | [thoughtEditor](/Users/zpc/projects/elsepage/App/MyMind/MyMindView.swift:122)；[BrainItemEditorSheet](/Users/zpc/projects/elsepage/App/MyMind/MyMindView.swift:1088) | Form、TextField、Picker | R07；不是创建入口；异步保存后详情快照待核验 |
| M05 问题编辑 Sheet / Brain / I | M03编辑 → 取消/保存后 dismiss | 修改问题/状态 | editingQuestion、非空校验 | [questionEditor](/Users/zpc/projects/elsepage/App/MyMind/MyMindView.swift:146) | 同BrainItemEditorSheet | R07 |
| M06 记忆展开区 / Brain / I | MemoryRow点击 → 再点折叠 | 看来源原话、准确/不准确/修改/忘记、来源书跳转 | expandedMemoryID、evidenceByMemory、origin/confidence/state | [MemoryRow](/Users/zpc/projects/elsepage/App/MyMind/MyMindView.swift:540)；[memoryEvidenceContext](/Users/zpc/projects/elsepage/App/MyMind/MyMindModel.swift:166) | originBadge、metadata、evidenceBlock、Button | R05/R07；“忘记”硬删除，没有单条确认对话框 |
| M07 修改记忆 Alert / Brain / I | 展开记忆“修改” → 取消/保存 | 修改记忆陈述 | editingMemory、editText；保存改origin为userExplicit | [修改记忆 alert](/Users/zpc/projects/elsepage/App/MyMind/MyMindView.swift:78)；[edit](/Users/zpc/projects/elsepage/App/MyMind/MyMindModel.swift:145) | 系统Alert + TextField | R07 |
| M08 新成就横幅 / Achievement / I | 已挂载overlay收到pendingUnlock → 3秒或手动关闭 | 低打扰反馈与VoiceOver播报 | queue、pendingUnlock、已解锁记录 | [AchievementToast / Overlay](/Users/zpc/projects/elsepage/App/Achievement/AchievementToast.swift:8) | material卡片、图标bounce | R07/R10；只在挂载容器生效，非全局任意页面 |

## 5. 设置与系统分享

| ID / 名称 / 模块 / 状态 | 入口 → 退出 | 主任务与核心交互 | 依赖业务状态 | 源码 / 符号 | 当前组件 | 重构风险 / 本次证据 |
| --- | --- | --- | --- | --- | --- | --- |
| S01 设置根 Sheet / Settings / I | 书架齿轮、想法更多、我的齿轮 → 完成/下滑 | 查看角色配置状态；进入子页；默认保存录音Toggle | SettingsRootModel、AppStorage | [SettingsView](/Users/zpc/projects/elsepage/App/Settings/SettingsView.swift:11) | NavigationStack、List、statusRow | R01/R06；离开清理transient secrets；本次未触达 |
| S02 聊天模型 / Settings / I | S01 push → 系统返回 | 预设、地址、Model、Key；保存、测试、删除配置 | ProviderSettingsModel、isWorking、hasSavedKey | [ChatProviderView](/Users/zpc/projects/elsepage/App/Settings/SettingsView.swift:121) | Form、SecureField、Picker、Alert | R06；删除涉及全部角色Key；本次未触达 |
| S03 Embedding / Settings / I | S01 push → 返回 | 配置独立模型/地址/Key、预设、测试、启停语义检索 | RAGSettingsModel.embedding*、chat共享配置行 | [EmbeddingSettingsView](/Users/zpc/projects/elsepage/App/Settings/SettingsView.swift:190) | Form、Toggle、Picker、SecureField | R06；启用可能触发全库嵌入外发 |
| S04 Reranker / Settings / I | S01 push → 返回 | 独立模型/地址/Key、预设、测试、启停精排 | RAGSettingsModel.reranker* | [RerankerSettingsView](/Users/zpc/projects/elsepage/App/Settings/SettingsView.swift:252) | Form、Toggle、Picker、SecureField | R06；不能假定所有兼容Provider支持/rerank |
| S05 每本书检索进度 / RAG / I | S01条件NavigationLink → 返回 | 查看词法/语义状态、错误；重新嵌入/重建；手动刷新 | statuses、isLoading、BookIndexState、embeddingModel | [RAGManagementView](/Users/zpc/projects/elsepage/App/Settings/RAGManagementView.swift:7) | List、badge、ProgressView、Alert | R08；状态是reload快照，无持续订阅 |
| S06 对话身份 / Settings / I | S01 push → 返回 | 用户/AI名字、SF Symbol头像、即时预览、恢复默认 | 4个profile.* AppStorage键 | [ConversationIdentitySettingsView](/Users/zpc/projects/elsepage/App/Settings/ConversationIdentitySettingsView.swift:6) | AvatarSymbolPicker、Form、inlinePreview | R10；展示名称不是账户/Profile领域实体 |
| S07 路由诊断 / Settings / I | S01 push → 返回 | 看本地路由次数、回退、耗时、tokens、证据数量 | DiagnosticsModel.recentTraces/routingDiagnostics | [DiagnosticsView](/Users/zpc/projects/elsepage/App/Settings/SettingsView.swift:311) | Form、LabeledContent | R06/R08；没有逐项原文Context检查器 |
| S07D 性能诊断区 / DEBUG / I | S07内Perf.isEnabled时出现 → 随父页退出 | 复制/清空/刷新采样；启停USB测试服务 | Perf、cache计数、DebugLoop生命周期 | [PerfDiagnosticsView](/Users/zpc/projects/elsepage/App/Performance/PerfDiagnosticsView.swift:7) | Section、Button、LabeledContent | R08；不是Release独立页 |
| S08 数据与隐私 / Settings / I | S01 push → 返回；全清后重装配 | 导出、分享、录音占用/清理、删书与索引、两阶段全清 | DataSettingsModel、exportedDataURL、busy flags、wipe list state | [DataSettingsView](/Users/zpc/projects/elsepage/App/Settings/SettingsView.swift:434)；[exportMyData](/Users/zpc/projects/elsepage/App/Settings/DataSettingsModel.swift:71) | Form、ShareLink、Alert、scope清单 | R02/R08；无备份导入/恢复页 |
| S09 系统分享 / iOS / I | S08生成JSON后ShareLink → 完成/取消 | 导出文件到用户选定目标 | exportedDataURL | [ShareLink](/Users/zpc/projects/elsepage/App/Settings/SettingsView.swift:448) | iOS系统分享面板 | R08；分享的JSON包含个人内容与音频，非密钥 |

## 6. Menu、Context Menu、确认与错误表面

这些表面与所属页面共享状态/Model；不能以“不是页面”为由漏掉其删除、取消和恢复语义。

| ID / 类型 | 入口与退出 | 操作/状态依赖 | 源码、复用与风险 |
| --- | --- | --- | --- |
| U01 书架排序 Menu | L01左上排序 → 选项/点外 | 最近阅读/书名/作者，sortOrder | [Menu+Picker](/Users/zpc/projects/elsepage/App/Library/LibraryView.swift:44)；原生Menu；R02 |
| U02 书籍 Context Menu | L01长按封面 → 移除/取消 | 设置deletingBook，随后确认 | [contextMenu](/Users/zpc/projects/elsepage/App/Library/LibraryGridView.swift:93)；R02；删书范围包含反思会话 |
| U03 想法更多 Menu | T01右上更多 → 选分组/设置 | grouping、showsSettings | [Menu](/Users/zpc/projects/elsepage/App/Thoughts/ThoughtsView.swift:38)；R07 |
| U04 整条消息 Context Menu | F02原文/消息长按 → 复制整条、允许时删除 | 作者/时间；只有根可删或最新用户轮可删 | [copyMessageContextMenu](/Users/zpc/projects/elsepage/App/DesignSystem/SelectableText.swift:798)；[userTurn](/Users/zpc/projects/elsepage/App/Reflection/SessionReflectionSheet.swift:1524)；R05/R07/R09 |
| U05 草稿更多 Menu | F02非空且未录音时更多 → 清空/关闭 | draft快照、撤销清空条 | [草稿Menu](/Users/zpc/projects/elsepage/App/Reflection/SessionReflectionSheet.swift:1737)；R09 |
| U06 录音附件 Menu | F01/F02附件更多 → 删除录音 | saved/draft file、audioFileName | [附件Menu](/Users/zpc/projects/elsepage/App/Reflection/VoiceReflectionRecorder.swift:641)；R09 |
| U07 同范围笔记 Menu | R09多条笔记“第N条” → 切条/取消 | relatedNotes、activeTarget | [Note选择Menu](/Users/zpc/projects/elsepage/App/Reader/AnnotationUI.swift:494)；R04；切条前待写文本需专测 |
| U08 Provider/角色预设 Picker | O02/S02/S03/S04 → 选中/取消 | selectedPreset、role preset/model/endpoint | [预设Picker](/Users/zpc/projects/elsepage/App/Onboarding/OnboardingView.swift:145)；[Provider Picker](/Users/zpc/projects/elsepage/App/Settings/SettingsView.swift:129)；R06 |
| U09 全清记忆 confirmationDialog | M01垃圾桶 → 确认删除/取消 | showsClearAll、model.memories | [清除全部记忆](/Users/zpc/projects/elsepage/App/MyMind/MyMindView.swift:85)；仅memory，不清thought/question；R07 |
| U10 看法/问题删除 confirmationDialog | M02/M03垃圾桶 → 删除/取消 | selectedThought/selectedQuestion、showsDelete | [看法删除](/Users/zpc/projects/elsepage/App/MyMind/MyMindView.swift:821)；[问题删除](/Users/zpc/projects/elsepage/App/MyMind/MyMindView.swift:953)；R07 |
| U11 问题回答看法选择 confirmationDialog | M03标记已解决 → 选看法/取消 | 非archived answerCandidates；未resolved时 | [showsResolvePicker](/Users/zpc/projects/elsepage/App/MyMind/MyMindView.swift:959)；R07 |
| U12 导入/重复/删书 Alert | L01失败、重复、U02 → 好/取消/移除 | errorMessage、duplicateTitle、deletingBook | [alerts](/Users/zpc/projects/elsepage/App/Library/LibraryView.swift:118)；R02 |
| U13 阅读操作错误 Alert | R01操作失败 → 好 | model.errorMessage | [alert](/Users/zpc/projects/elsepage/App/Reader/ReaderScreen.swift:111)；R03/R04 |
| U14 反思保存/对话错误 Alert | F01/F02错误 → 好 | Model.errorMessage；AI失败常为inline agentNotice | [保存alert](/Users/zpc/projects/elsepage/App/Reflection/SessionReflectionSheet.swift:1146)；[对话alert](/Users/zpc/projects/elsepage/App/Reflection/SessionReflectionSheet.swift:1518)；R07 |
| U15 删除记录 Alert | F02 context menu → 删除/取消 | canDeleteRoot、isResponding、isDeleted | [记录删除](/Users/zpc/projects/elsepage/App/Reflection/SessionReflectionSheet.swift:1506)；根与最后轮删除语义不同；R07 |
| U16 我的/想法/RAG错误 Alert | M01/T01/S05读取或操作失败 → 好 | 各model.errorMessage | [我的错误](/Users/zpc/projects/elsepage/App/MyMind/MyMindView.swift:73)；[想法错误](/Users/zpc/projects/elsepage/App/Thoughts/ThoughtsView.swift:69)；[RAG错误](/Users/zpc/projects/elsepage/App/Settings/RAGManagementView.swift:31)；R07/R08 |
| U17 删除配置 Alert | S02删除 → 确认/取消 | showsDeleteConfirmation、chat delete | [删除配置](/Users/zpc/projects/elsepage/App/Settings/SettingsView.swift:177)；R06 |
| U18 设置操作错误 Alert | S02/S03/S04/S08失败 → 好 | 对应errorMessage | [聊天错误](/Users/zpc/projects/elsepage/App/Settings/SettingsView.swift:173)；同文件240/302/481；R06/R08 |
| U19 录音/全书/全数据清除 Alert | S08危险操作 → 确认/取消 | 清理录音、删全部书籍、全清各自busy状态；全清需先展开范围清单 | [三类确认](/Users/zpc/projects/elsepage/App/Settings/SettingsView.swift:485)；R08/R09；不可合成同一个“删除” |
| U20 系统文本选中菜单 | 阅读桥anchor转换失败时系统兜底；UITextView原生选择 → 复制等 | selection / first responder / OS版本 | [系统菜单fallback](/Users/zpc/projects/elsepage/App/Reader/ReadiumReaderView.swift:208)；[SelectionKeeper](/Users/zpc/projects/elsepage/App/DesignSystem/SelectableText.swift:620)；R03/R09 |
| U21 系统语音权限提示 | 首次主动录音 → 允许/拒绝 | 麦克风/Speech权限 | [权限请求](/Users/zpc/projects/elsepage/Sources/SpeechCore/SystemSpeechTranscriptionProvider.swift:35)；不是App Sheet；R09；本次未请求 |

全量检索没有发现 App 直接调用 `.popover`。浮动工具是自定义 overlay；iOS AX 出现 `PopoverDismissRegion` 是系统 Sheet 的辅助区域，不能据此新建一个“Popover页面”。

## 7. 主要界面状态矩阵

| 所属ID | 必须保留/调查的状态 | 代码状态入口 | 本次覆盖 |
| --- | --- | --- | --- |
| A00/O01 | 启动中/启动失败；导入中/成功/失败/重复/用户取消 | startupError、isImporting、errorMessage、duplicateTitle | 成功启动、导入成功 |
| L01 | 无书/有书/无搜索结果/封面缺失/统计缺失/补写想法/删除失败 | books、visibleBooks、covers、TodayProductState | 有书、缺封面占位 |
| R01 | 加载占位/正文/控制栏开关/打开失败/旋转/后台/返回跳前位置 | isPrepared、showsControls、canNavigateBack、scenePhase | 正文与控制栏 |
| R02/R03/R04 | 目录无/有；空查询/搜索中/无/有结果；标注无/有/独立笔记/多笔记 | chapters、searchState、highlights、notes | 单章目录；其余仅源码 |
| R06/R07/R08 | 新选区/高亮/冲突菜单互斥、坐标缺失、边缘clamp、交叉拒绝、删除撤销 | ReaderAnnotationMenu enum、notice | 选区、创建高亮 |
| R09 | 空预览/非空Markdown/编辑/自动保存中/多条切换/清空后删除 | mode、text、activeTarget、finished、saveTask | 空预览、空编辑、下划线；非空保存未验证 |
| R10 | idle/preparing/streaming/completed/cancelled/failed；重试、保存中/成功/失败；截断提示、引用缩面板 | ReaderHelpModel.State、isSavingNote、isSaved、contextDisclosure | idle、未配置Provider失败 |
| F01 | editing/saving/saved；空白禁存、录音中禁存；原话/润色；音频提升失败但文字保留 | SubmissionState、ReflectionTextDraft、audioNotice | 仅隔离save脚本，不是当前UI |
| F02 | 消息加载、回应准备/文本、无AI、网络/认证/限流/超时、未完成首回、pending发送/失败/重发、删除完毕 | isResponding、agentNotice、pendingUserMessage、hasLoadedMessages、isDeleted | 仅包级测试证据 |
| F03 | 权限中/拒绝/录音/停止/可编辑转写/识别失败/模型缺失/不可用麦克风替代提示；播放加载/失败/暂停/seek | VoiceReflectionState、SpeechRecognitionAvailability、audio player | 未运行；端上可用性必须真机复核 |
| T01/T02 | 加载/空档案/无搜索结果/按月/按书；固定概要/回退；条件Journal/依据无/有 | isLoading、entries、summary、journal | 仅源码 |
| M01–M07 | 全空/只有streak/各分区空或多条/needsReview/active/retired；来源缺失/有；修订空/有 | MyMindModel、origin/state/confidence、contexts | 仅源码；需要真实派生样本 |
| S01–S08 | 未配置/已配置未测/连接成功或错误/角色停用或工作中/索引六态/无trace/无书/导出就绪/危险操作忙或失败 | 各settings Model flags、BookIndexState | 仅源码；最小书后台lexicalReady经DB读取 |

## 8. 不得当作可达页面的对象

| 对象 | 状态 | 原因与源码 |
| --- | --- | --- |
| BrainDiscussionSheet / 继续想想 | Partial | [Sheet定义](/Users/zpc/projects/elsepage/App/MyMind/MyMindView.swift:1170)、`discussingItem`/`discussingBinding`、MyMindModel.continueThinking 均存在；没有任何 `.sheet` 使用这些值，按钮只改状态 |
| 选句 Reflection / “聊聊这句” | Partial | [reflectOnSelection](/Users/zpc/projects/elsepage/App/Reader/ReaderModel.swift:415) 与 contextReflection Sheet 存在，但当前 SelectionToolbar 只接 `onAsk`，没有用户动作调用 reflectOnSelection |
| Journal 编辑器 | Partial | [applyThoughtEdit](/Users/zpc/projects/elsepage/App/Thoughts/ThoughtsModel.swift:161) 与服务在，当前 ThoughtRecordExtras 只展示，没有编辑回调 |
| 独立 Today / Journal / Reader Profile 页 | Planned（旧IA已被替代） | 当前AppShell无注册；部分内容合入其他页，不能据旧PRD恢复旧入口 |
| 思想图谱、iCloud同步、备份还原页、全库正文搜索页 | Planned / 无当前入口 | 根导航、所有presentation扫描无对应页面；不代表可因名字相似的领域对象推断存在 |
| docs/prototypes HTML | Planned / 历史探索 | [原型说明](/Users/zpc/projects/elsepage/docs/prototypes/README.md)明确不参与构建；不是App截图或当前设计规格 |

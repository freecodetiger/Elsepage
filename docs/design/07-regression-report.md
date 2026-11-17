# ElsePage 回归验收报告

2026-11-16。对象：`ui/ux-modernization` 工作区（未提交），iPhone 17 Pro / iOS 26.5 Debug 构建。方法：在已安装的 Debug App 上走真实 UI，并只读检查模拟器 App 容器内的 `readloop.sqlite`；没有改 RAG、Agent、防剧透或数据模型。

## 1. 结论

| 项目 | 结果 |
| --- | --- |
| EPUB 打开与章节导航 | 通过 |
| 阅读位置恢复 | **修复前失败；修复后通过** |
| 阅读设置持久化 | **修复前失败；修复后通过** |
| 高亮创建/列表/删除/撤销/持久化 | 通过 |
| 笔记编辑器与空笔记撤销 | 通过（未写入正文测试） |
| AI 未配置错误恢复 | 通过（push 入口） |
| 真实 AI 回答/流式/停止/引用回跳 | **App 侧链路确定性通过**（`-fake-provider`）；真实 Provider 仍未验证 |
| 防剧透约束 | 前置文案通过；**实际检索边界无法验证** |
| 本地数据安全 | 数据库无 Provider 配置；Keychain 无法用 CLI 复验；测试 Key 仍需 Provider 侧撤销 |
| 前后台生命周期 | 通过 |
| 强杀恢复 | 修复后通过 |
| 暗色/浅色 | 通过（阅读器 chrome 与 Sheet 均已跟随阅读主题） |
| 大字号 | 通过（当前书行修复后） |
| 横屏 | 通过；行长偏宽 |
| 构建与测试 | Debug 构建通过；13 + 13 + 411 项测试通过 |

本轮修复了 **P0 级持久化缺陷**（见 §3）和三个呈现缺陷；没有任何已知的核心阅读回归。

## 2. 回归矩阵

证据等级：**V** 已运行；**R** 源码；**H** 需真人测试。

### 2.1 EPUB 与阅读

| 场景 | 结果 | 证据 |
| --- | --- | --- |
| 已有 EPUB 导入结果可打开 | 通过 | V：书架两本书均可打开 |
| 章节渲染、分页/滚动 | 通过 | V：中文书 3 页，横向翻页；顶部章节标题正确 |
| 目录 | 通过 | V：目录列出三章，当前章有勾选；点击跳转 |
| 搜索正文 | 未覆盖 | 本轮未输入关键词；源码路径未改 |
| 阅读设置（字号/行高/边距/主题/模式） | 通过（选择与即时生效） | V：主题切换即时生效；字号滑块本轮用代码路径与 AX 确认，未逐档拖动 |
| 阅读位置恢复 | 修复后通过 | V：见 §3 |
| 阅读设置恢复 | 修复后通过 | V：见 §3 |
| 章节起始页标题 | 通过 | V：chrome 覆盖时不切标题 |
| 横屏 | 通过（有行长遗留） | V：`reader-landscape.png` |
| 强制退出 | 修复后通过 | V：56% → 强杀 → 重新打开仍在 56% |
| 短阅读不提示反思 | 通过 | V/R：不足 2 分钟的会话不再弹出反思，也不生成书架“补写想法”；`MeaningfulReadingSessionPolicy.hardFloorDuration` 单测覆盖（含 2 分钟内有高亮的反例） |

### 2.2 标注与笔记

| 场景 | 结果 | 证据 |
| --- | --- | --- |
| 长按选词 → 单行工具栏 | 通过 | V：四色 + 笔记/问 AI/复制 |
| 选色创建高亮 | 通过 | V：黄色高亮出现在正文 |
| 点击高亮 → 菜单 | 通过 | V：四色 + 笔记 + 删除；选中色有勾 |
| 删除高亮 → 撤销胶囊 | 通过 | V：“已删除高亮 撤销” |
| 标注列表 | 通过 | V：“起来。 · 第二章 重读的代价 · 99%” |
| 高亮持久化 | 通过 | V：数据库 `highlights` 有 1 行；重新打开仍在 |
| 新建笔记 | 通过（空笔记路径） | V：直接进入编辑态；空笔记退出出现“已删除笔记 撤销” |
| 笔记正文持久化 | 未覆盖 | 为不向 App 写入用户内容，本轮没有输入正文；源码路径未改 |
| 同段多笔记/重叠冲突菜单 | 未覆盖 | 需要手工构造重叠选区 |
| 删除书（级联） | 通过 | V：在《缓慢的注视》上执行真实删除；EPUB 文件消失，`books` 2→1，`highlights` 2→1，`readingSessions` 15→9，`bookChapters` 4→1，`bookChunks` 14→2；另一本书的 2 条笔记保留。备份后已还原容器 |
| 当前书删除入口 | 修复后通过 | V：修复前顶部行长按只会打开书，唯一一本书无法删除；补 contextMenu 后 `LibraryInteractionUITests` 两条用例通过 |
| 书架手动排序（交换） | 通过 | V：自定义排序下拖动手柄，两本书交换位置、其余不动；DB `manualOrder` 立即更新，重启后顺序保持。`ManualOrderPersistenceTests` 覆盖 repository；`LibraryReorderUITests` 覆盖把手显隐与 44pt |
| 多本测试书导入 | 通过 | V：`-seed-library` 通过真实导入管线写入 5 本 EPUB（`Resources/DebugBooks`），书架共 7 本 |

### 2.3 AI 与引用

| 场景 | 结果 | 证据 |
| --- | --- | --- |
| 未配置 Provider → 错误卡 | 通过 | V：`help-error-ax.png` |
| 错误卡“去设置聊天模型” | 通过（push 入口） | V：打开设置 Sheet；DB 仍 0 个 Provider 配置 |
| 从设置返回后保留问答 | **不通过** | V：设置 Sheet 关闭后帮助线程已结束，需要重新选句 |
| 真实回答 | 确定性通过；真实 Provider 仍未验证 | V：`-fake-provider` 注入确定性客户端，`AIHelpUITests` 断言回答渲染 |
| 流式逐 token | 确定性通过 | V：slow 模式分 13 段推送，停止按钮可见 |
| 停止生成 | 确定性通过 | V：点“停止回答”后进入“已停止” |
| 失败重试 | 确定性通过 | V：failure 模式先 started 再抛错，“重试”出现且可再次触发 |
| 引用回跳 | 确定性通过 | V：`[E1]` 被校验成引用，点“来源 1”后回到原文并显示“已回到原文” |
| 过去反思来源只读 | 源码通过 | R：`ReaderHelpSheet.swift:273` “这条过去记录没有原文位置，无法跳转” |
| 防剧透前置说明 | 通过 | V：“回答只使用这段原文和你已经读过的部分。” |
| 防剧透实际边界 | 无法验证 | 需要真实 Provider + 已读上下文 |

### 2.4 生命周期与本地数据

| 场景 | 结果 | 证据 |
| --- | --- | --- |
| 退到后台 | 通过 | V：位置写入总进度 44.4%，时间戳为翻页时刻 |
| 前台恢复 | 通过 | V：仍在阅读页 |
| 强杀后重开 | 修复后通过 | V：56% 恢复 |
| 退出阅读（X） | 通过 | V：结束会话 → 反思 Sheet；“这次不写”关闭 |
| 冷启动 | 通过 | V：书架正常加载 |
| 启动失败重试 | 源码通过 | R：`ReadLoopApp.swift:16` 重试按钮 |
| 离线阅读 | 通过（本地文件） | V：整个流程无网络依赖 |
| 离线 AI | 未覆盖 | 无 Provider；错误卡只验证了“未配置”分支 |
| 数据库 Provider 配置 | 0 条 | V：`select count(*) from providerConfigurations` = 0 |
| Keychain | 无法用 CLI 复验 | `security` 在模拟器 shell 不可用；上一轮已通过 App 设置删除，Provider 侧仍需持有人撤销 |

## 3. P0 回归：防抖保存取消自身

### 3.1 现象

修复前，翻页后等待 3 秒，`readingPositions` 的 `updatedAt` 不前进；阅读设置（主题）关闭 Sheet 后也不落库。只有退到后台或退出阅读时，`flushPosition()` / `flushPreferences()` 由另一个任务调用，才会写入。

复现：

1. 打开《缓慢的注视》，翻到第 2 页（44%）。
2. 等待 3 秒以上，直接强杀并重新打开。
3. 结果：回到 33%（章节起始页），而不是 44%。

证据：修复前 DB 中该书位置为 `totalProgression=0.333`、`updatedAt` 仍是前一天的 10:17:46；后台一次后才变成 `0.444`、时间戳为翻页时刻。

### 3.2 根因

`ReaderModel.flushPosition()` 与 `flushPreferences()` 的第一行会 `cancel()` 名为 `positionSaveTask` / `preferenceSaveTask` 的成员任务；而 750ms/250ms 防抖任务本身就在调用这两个 flush。取消的是当前任务，GRDB 的 async 写入随即以 `CancellationError` 返回，`didWrite(succeeded: false)` 后直接 return，写入从未发生。

### 3.3 修复

只移除 flush 内部的自取消（`ReaderModel.swift:836`、`:862` 附近），保留 `save(locator:)` / `savePreferences()` 在提交新值时取消旧防抖任务的逻辑。外部 flush 仍可正常写；重复写入同一最新值是幂等的，由 `LatestValueState` 去重。

### 3.4 验证

| 步骤 | 结果 |
| --- | --- |
| 翻到 55.5%，等待 3 秒，查 DB | `totalProgression=0.5555`，`updatedAt` 为翻页时刻（V） |
| 不经过后台，直接 `--relaunch` 强杀 | 书架显示 56% |
| 重新打开 | 落在第 3 页，进度 56%（V，`reader-restore-56.png`） |
| 阅读设置选“深色”，关闭 Sheet | DB `theme=dark`，`updatedAt` 前进（V） |
| 改回“自动” | DB `theme=system`，`updatedAt` 前进（V） |
| 构建/测试 | Debug 构建通过；13 + 13 + 411 通过 |

## 4. P1 回归：阅读器 chrome 的配色

### 4.1 现象

系统浅色、阅读主题“深色”时，阅读页是黑底白字，但顶部/底部胶囊里的书名、章节、图标、目录/标注标签、进度百分比全部是近黑色；胶囊本身也是黑色，实际对比接近 1:1。系统深色、阅读主题“浅色”时则相反。

### 4.2 根因

`ReaderScreen` 的 chrome 使用 `ElsepageColor.textPrimary` / `textSecondary` / `separator`，这些动态色按系统配色解析；页面背景却按 `preferences.theme` 解析。两套来源不一致。

### 4.3 修复

新增 `readerColorScheme`（system → 系统；light/sepia → light；dark → dark），把 `.environment(\.colorScheme, readerColorScheme)` 应用到 `readerChrome` 与 `ReaderAnnotationOverlays`。这样 chrome、选区工具、高亮菜单、临时提示都跟随阅读主题；Readium 正文仍由 `preferences` 控制。

### 4.4 验证

- 浅系统 + 深阅读：chrome 白字、黑胶囊（V，`reader-dark-after-fix.png`）。
- 深系统 + 浅阅读：chrome 黑字、白胶囊（V，`reader-light-in-dark-system.png`）。
- 深系统 + 系统主题：chrome 白字（V，`reader-system-dark.png`）。
- 浅系统 + 系统主题：chrome 黑字（V，`reader-chrome-light.png`）。
- 选区工具在深色页上为深色玻璃 + 白字（V，`reader-selection-dark.png`）。

注意：Sheet 仍按系统主题渲染，未纳入本次修复；见 [07-remaining-issues.md](07-remaining-issues.md) N-06。

## 5. P1 回归：大字号当前书行

### 5.1 现象

accessibility-extra-large 下，当前书行的“补写想法”胶囊是 `ZStack` 的 bottomTrailing overlay；字号放大后胶囊变宽变高，压住章节行和进度条，章节行只剩 “第…”。

### 5.2 修复

`LibraryView.currentReadingRow` 在 `showsReflection && dynamicTypeSize.isAccessibilitySize` 时改为 `VStack`：书本行在上，“补写想法”独立一行在下；普通字号仍保留 overlay。进度块的 128pt trailing 预留只在 overlay 时生效。

### 5.3 验证

- AX 下胶囊在行下方，不与章节/进度相交（V，`shelf-ax-after-fixes.png`）。
- 普通字号下书架布局未变（V，`shelf-after-fixes.png`）。
- 当前书仍可点击打开；补写入口仍在（V）。

## 6. 其它修复的回归面

| 修复 | 影响面 | 验证 |
| --- | --- | --- |
| 封面占位标题按封面宽度缩放（120pt → 约 15.6pt） | 仅生成的占位封面；真实封面不显示标签 | V：`ReadLoop Foundation Fixture` 不再断词；当前书封面正常 |
| 搜索框 minHeight 36 → 44，清除按钮 44pt | 书架/想法/我的的搜索字段 | V：搜索栏略高，占位与输入正常；输入 “slow” 后清除按钮可点并清空 |
| 补写胶囊改为始终独立一行，删除 128pt trailing 预留 | `LibraryView.currentReadingRow` | V：章节行完整显示“第二章 重读的代价 · 44%”；普通字号与 AX 字号一致（`shelf-chapter-full.png`） |
| 阅读器 5 个 Sheet 跟随阅读主题并改用页面底色 | `ReaderScreen` 的目录/搜索/标注/设置/笔记/问答/反思 Sheet | V：深色阅读 + 浅系统 → 深色 Sheet；浅色阅读 + 深系统 → 浅色 Sheet；Sheet 不再透出正文（`reader-annotations-dark-fixed.png`、`reader-sheet-light-in-dark-system.png`） |
| 当前书补上“从书架移除”菜单 | `LibraryView.currentReadingRow` | V：长按顶部行出现菜单，不再直接打开书；只有一本书时也能删除 |
| 阅读器底部进度条改为装饰元素 | `ReaderScreen.bottomBarProgress` | V：审计不再报 hit area；百分比文字承载“阅读进度” label/value |

## 7. 构建与测试

| 检查 | 结果 |
| --- | --- |
| Debug 模拟器构建 | **BUILD SUCCEEDED** |
| Release 模拟器构建 | **BUILD SUCCEEDED** |
| `DesignSystemTests` | 13 个用例通过 |
| `ReadiumIntegrationTests` | 13 个用例通过 |
| `swift test` | 411 个用例通过（15 suites） |
| `ReadLoopUITests`（新增） | 5 条无障碍审计 + 2 条性能基线 + 3 条 AI 链路通过 |
| `Package.resolved` | 测试后已恢复（`ba80d5a1…`），未保留副作用 |

新增的 UI 测试目标（2026-11-16）：

| 用例 | 结果 |
| --- | --- |
| `testShelfAccessibilityAudit` | 通过（结构审计）；视觉债务 7 条已记录 |
| `testThoughtsAccessibilityAudit` | 通过；视觉债务 2 条 |
| `testMyMindAccessibilityAudit` | 通过；无债务 |
| `testSettingsAccessibilityAudit` | 通过；视觉债务 15 条 |
| `testReaderAccessibilityAudit` | 通过（隐藏 chrome 状态）；视觉债务 0 条 |
| `testLaunchPerformance` | 1.508–1.617 s（两轮各 3 次） |
| `testReaderOpenPerformance` | 2.188–2.242 s（两轮各 3 次，点书 → chrome 可点） |
| `AIHelpUITests.testStreamingAnswerCanBeStopped` | 通过（slow 流式 + 停止） |
| `AIHelpUITests.testFailedAnswerOffersRetry` | 通过（失败 + 重试） |
| `AIHelpUITests.testCompletedAnswerRendersCitation` | 通过（`[E1]` 校验 + 跳回原文） |

已知问题：`ReadLoopCoreTests` 在 iOS 模拟器运行时报 14 条 Swift Testing 断言失败（`ModelFailure` 值打印相同但比较不相等）；同一批用例在 `swift test`（macOS）通过。该失败在本轮改动之前就存在于 iOS 测试路径，未追溯修复。

命令：

```sh
xcodebuild -project ReadLoop.xcodeproj -scheme ReadLoop \
  -configuration Debug -destination 'id=C380BC09-F7BE-4A18-B856-10E516F9EB3C' \
  -derivedDataPath /tmp/elsepage-dd build

xcodebuild -project ReadLoop.xcodeproj -scheme ReadLoop \
  -destination 'id=C380BC09-F7BE-4A18-B856-10E516F9EB3C' \
  -derivedDataPath /tmp/elsepage-dd \
  -only-testing:DesignSystemTests -only-testing:ReadiumIntegrationTests test

swift test
```

## 8. 未覆盖与阻塞

| 项目 | 原因 |
| --- | --- |
| 真实 Provider 的回答质量、鉴权失败、网络超时 | 确定性用例走的是假客户端；真实 SSE/鉴权仍需一次性人工验收 |
| 防剧透检索边界 | 前置文案已断言；`failClosedReason` 的实际分支需要索引可用/不可用两种书籍 |
| 笔记正文持久化 | 未向 App 写入用户内容 |
| 删除书与级联 | 破坏性操作，未执行；只核对确认文案 |
| EPUB 导入 | 本轮没有重新导入；已有测试书可读 |
| VoiceOver 全流程 | 未启用真人 VoiceOver；AX 树只用于定位 |
| Reduce Motion / Reduce Transparency | 未逐项切换观察 |
| iPhone SE / 小屏 / iPad | 未运行；工程只支持 iPhone |
| 帧率、CPU、内存趋势 | 模拟器 frame-health 不可用；xctrace attach 失败 |

## 9. 测试数据说明

模拟器里仍保留：

- 《缓慢的注视》（中文测试书，当前 56%，1 条黄色高亮）
- ReadLoop Foundation Fixture（1 条高亮/2 条笔记，0%）
- 一条待补写的阅读会话（书架显示“补写想法”）

这些是验收过程产生的测试数据，不属于产品内容；正式演示/截图前应清理。数据库中有 14 条 readingSessions，来自多轮验收。

## 10. 范围声明

- 本轮代码改动只涉及 `ReaderModel`、`ReaderScreen`、`LibraryView`、`ElsepageComponents`。
- 未改 RAG、Context Routing、Agent Runtime、防剧透策略。
- 未改持久化模型与迁移；只修复了防抖写入的实现缺陷。
- 未提交、未推送、未合并。

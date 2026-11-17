# ElsePage 剩余问题清单（最终验收）

2026-11-16。状态口径：**Resolved**（当前构建验证通过）、**Partially Resolved**（主要路径成立，仍有明确缺口）、**Unresolved**（未处理）、**Unable to Verify**（源码/环境不足，不能下结论）。

证据：V 已运行；R 源码；H 需真人测试。对应审计见 [01-ux-audit.md](01-ux-audit.md)，原始优先级见 [01-prioritized-issues.md](01-prioritized-issues.md)。

## 1. 原始高优先级问题逐条状态

| ID | 状态 | 证据与说明 |
| --- | --- | --- |
| **UX-001** 阅读器里的 App 底栏 | **Resolved** | V：阅读器 AX 树无 tab bar；底部目录/标注/进度完整可点。push 入口实测；fullScreenCover 入口本轮无数据未走。 |
| **UX-002** “今天先不了”永久放弃、草稿丢失 | **Partially Resolved** | V/R：按钮改为“这次不写”；有非空草稿时先确认“放弃并关闭”；空笔记可撤销。“这次不写”不再写永久标记，只跳过本次运行（`LibraryNextActionModel.dismissedThisRun`）。草稿仍不跨启动；跨书收件箱未做。 |
| **UX-003** 删书确认漏掉会话/反思 | **Resolved** | V/R：`LibraryView.swift:131` 明确列出“阅读会话、反思与 AI 对话”。未执行真实删除。 |
| **UX-004** “继续想想”死按钮 | **Partially Resolved** | R：`.sheet(isPresented: discussingBinding)` 已挂 `BrainDiscussionSheet`（`MyMindView.swift:104`）。当前 0 条 Brain 内容，无法实际点通，端到端仍待数据验证。 |
| **UX-005** 大字号破版 | **Resolved** | V：accessibility-extra-large 下搜索框可增长、标题/作者换行、补写胶囊独立一行；见 `shelf-ax-after-fixes.png`。网格封面装饰标题在 AX 下隐藏，标题在封面下方完整可读。 |
| **UX-006** 书架无法判断读过/读到哪 | **Partially Resolved** | V/R：排序菜单恢复；网格封面下有 2pt 进度线（`LibraryGridView.swift:79`）。仍没有“读到 X% / 最近读过”的可见文字，10+ 本书的找回任务未测试。 |
| **UX-007** AI 未配置是死路 | **Partially Resolved** | V：push 入口的错误卡有“重试 / 去设置聊天模型”，可打开设置。`AppShell` 的 fullScreenCover 入口仍未传 `onOpenSettings`；从设置返回后本次问答线程已丢弃，需要重新选句。 |
| **UX-008** “忘记”记忆硬删除 | **Resolved** | R：`MyMindView.swift:117` 有“忘记这条记忆？”确认对话框。当前无记忆数据，未实际点。 |
| **UX-009** 返回同时是结束会话 | **Resolved** | V：顶部只有 X，label “结束阅读并返回书架”；底部重复的“读到这里”已移除。 |
| **UX-010** 删除聊天配置连带 Embedding/Reranker | **Resolved** | R：按钮改为“删除所有 AI 配置和 API Key”（`SettingsView.swift:169`）。 |
| **UX-011** chrome 覆盖章节标题 | **Resolved（按新方向）** | V：正文不预留边距、页面填满；chrome 为浮层。章节起始页标题完整；半行由页色渐隐收边。深色主题下的 chrome 配色缺陷另见 N-02，已修复。 |
| **UX-012** 当前书标题截断/行内空白/胶囊重叠 | **Resolved** | V：补写胶囊改为始终独立一行，128pt trailing 预留已删除，章节行完整显示“第二章 重读的代价 · 44%”；见 `shelf-chapter-full.png`。 |
| **UX-013** 过去反思是假链接 | **Resolved** | R：`ReaderHelpSheet.swift:273` 改为只读“这条过去记录没有原文位置，无法跳转”。无真实回答数据，未实际点。 |
| **UX-014** 提问前无防剧透说明 | **Resolved** | V：原文卡下有“回答只使用这段原文和你已经读过的部分。” |
| **UX-015** RAG 行错误使用成功绿 | **Resolved** | V：设置页该行说明为中性灰。 |
| **UX-016** 空表单可测试/保存；模型名空 | **Partially Resolved** | R：模型或 Key 为空时保存/测试禁用；补了“测试使用当前填写内容”。预设默认模型与逐字段错误未验证。 |
| **UX-017** “已发送”早报、无 Stop | **Partially Resolved** | R：`.sending` 显示“发送中…”（`SessionReflectionSheet.swift:1437`）。反思回应仍无 Stop。 |
| **UX-018** Help Sheet 手势矛盾 | **Resolved** | V：无拖拽指示条；有内容时关闭先确认“丢弃这次问答？”。 |
| **UX-019** 反思 Sheet 主次不清 | **Partially Resolved** | V：保存禁用时显示“写一点内容即可保存”；有内容时关闭确认。顶部“这次不写”仍是与“保存”同级的大胶囊，且比禁用态更显眼；编辑区空白仍大。 |
| **UX-020** 我的详情页四按钮/旧视觉 | **Partially Resolved** | R：工具栏收敛为“继续想想 + 更多”。详情页正文已使用 `.body` 与 `pageInset`，未再发现审计所述的 19pt/20pt 旧容器残留；当前 0 条 Brain 内容，无法实拍，视觉一致性仍 **Unable to Verify**。 |
| **UX-021** “想法/看法”术语 | **Unresolved** | 未改；需要命名测试。 |
| **UX-022** 待补写只对当前书 | **Unresolved** | 仍只解析 `currentBook`；跨书收件箱未做。 |
| **UX-023** 启动失败无重试 | **Resolved** | R：`ReadLoopApp.swift:16` 重试按钮 + `AppModel.retryStartup()`。 |
| **UX-024** 记录删除藏在长按 | **Unresolved** | 详情页仍无可见“更多/删除”。 |
| **UX-025** 图标 Tab 无文字 | **Unresolved** | V：仍是书架/灯泡/人像三图标，无可见标签。 |
| **UX-026** 成就页视觉不一致 | **Partially Resolved** | V：背景已与根页面一致，返回按钮为同一套玻璃圆形；底部自定义栏仍在，导航标题仍居中。 |
| **UX-027** 触控目标不足 | **Resolved** | V：阅读器图标/底栏 44pt；补写胶囊 44pt；本轮把搜索框提升到 44pt、清除按钮从 16pt 提升到 44pt 命中。 |
| **UX-028** 新导入占据当前书 | **Resolved** | R：未打开的新书显示“新导入 · 还没开始读”。 |

## 2. 本轮新发现

| 编号 | 级别 | 状态 | 问题 | 证据 |
| --- | --- | --- | --- | --- |
| **N-01** | **P0** | **已修复** | 750ms 防抖保存取消自身，阅读位置/阅读设置只在后台或退出时落库；强杀丢最后一页与设置 | DB `updatedAt` 不前进；修复后 55.5% 强杀恢复 56%（`reader-restore-56.png`），详见 [回归报告 §3](07-regression-report.md#3-p0-回归防抖保存取消自身) |
| **N-02** | **P1** | **已修复** | 阅读主题与系统配色相反时，chrome 仍按系统取色；深色页 + 浅系统出现黑字黑胶囊 | `reader-dark-before-fix.png` / `reader-dark-after-fix.png`；修复后双向验证 |
| **N-03** | **P1** | **已修复** | AX 大字号下“补写想法”胶囊压住章节行与进度 | `shelf-ax-after-fixes.png`；改为独立一行 |
| **N-04** | P2 | **已修复** | 120pt 网格封面把 “Foundation” 断成 “Foundatio / n” | `shelf-after-fixes.png`；占位标题按封面宽度缩放 |
| **N-05** | P2 | **已修复** | 搜索框 36pt、清除按钮约 16pt 命中 | 搜索框 44pt、清除按钮 44pt；输入/清除实测 |
| **N-06** | P2 | **已修复** | 阅读器 Sheet 跟随系统主题，不跟随阅读主题；深色页 + 浅系统时标注/设置/目录是浅色 Sheet，反之为深色 | 5 个 Sheet 均套 `readerColorScheme`；深色阅读 + 浅系统实测 `reader-annotations-dark-fixed.png`，反向 `reader-sheet-light-in-dark-system.png` |
| **N-07** | P2 | **已修复** | 阅读设置/笔记/目录的玻璃背景透出正文，表单与正文叠字 | `.presentationBackground` 改为阅读页底色，Sheet 不再透字（`reader-appearance-dark-fixed.png`） |
| **N-08** | P2 | **未修复** | 反思 Sheet 的“这次不写”仍是强主操作；草稿不跨启动；待补写只对当前书 | `reflection-ax.png`，UX-002/019/022 |
| **N-09** | P2 | **已修复** | 当前书行有补写胶囊时，章节行被 128pt 预留截断 | 胶囊改为独立一行；`shelf-chapter-full.png` |
| **N-10** | P2 | **已关闭（实测不成立）** | 审计时横屏一行约 75 个汉字；当前排版默认值（字号 1.2 / 行高 1.6 / 页边 1.2）下实测约 34 个汉字，已在舒适区间。双栏在大屏 iPhone 横屏不可用：Readium 的用户列数只在 576–752pt 横屏生效，阅读器级列数只能在创建 navigator 时设置。决定保持单栏 | 2026-11-17 横屏实测；Readium `ReadiumCSS-after.css` 媒体查询 |
| **N-11** | P3 | **未修复** | 阅读器胶囊左右 12pt，根页面 16pt；右上“大小”是本地化符号，读起来像一个词；深色页黄色高亮偏暗 | V |
| **N-12** | P3 | **待验证** | AX 树重复项：阅读设置每个滑杆 3 个同名元素；设置页无名 switch “1”；阅读设置/反思 Sheet 导航栏 label 变成第一个按钮（“恢复默认”“这次不写”） | V（AX 树）；未做 VoiceOver 真人复验，可能是系统伪影 |
| **N-13** | P3 | **未修复** | 打开阅读器 1796ms（解析 24.3ms，Navigator→首帧 1654ms）；只有 1 次 Debug 模拟器采样 | `perf-diagnostics.png` |
| **N-14** | P3 | **未修复** | 选区/高亮菜单仍用 `.ultraThinMaterial`，未处理 Reduce Transparency；AX 下工具图标仍为 15pt | V/R |
| **N-15** | P2 | **已量化** | 视觉审计债务：封面占位标题对比度不足/大字号可能裁切；根页面与设置的次级文字多处“接近通过”；设置分组标题与页脚的 Dynamic Type 告警属 SwiftUI 误报 | V：`Tests/ReadLoopUITests` 的 `reportVisualDebt`，详见 [最终验收 §12](07-final-uiux-review.md#12-工具链升级2026-11-16) |
| **N-16** | P1 | **已修复** | 当前书（顶部行）没有删除入口；只有一本书时网格为空，整库唯一一本书无法删除 | V：长按顶部行只打开书；已补同一个 contextMenu，`LibraryInteractionUITests` 两条用例覆盖 |
| **N-17** | P2 | **已实现** | 书架没有手动排序：不支持拖拽调整顺序，只有“最近阅读/书名/作者”三种自动排序 | 新增「自定义」排序：长按整张封面抬起后拖到另一本书上即交换两者，其余书不动；`manualOrder` 走 v30 迁移，重启保持。拖拽删除：拖到右下角按钮（拖拽时变成垃圾桶）打开原有移除确认弹窗。手势由挂在 ScrollView 上的 `UILongPressGestureRecognizer` 驱动而非 SwiftUI `DragGesture`——后者要么吃掉滚动、要么被滚动抢走触摸。XCUITest 覆盖长按不再弹旧菜单、长按不打开书、轻点仍打开书；交换与拖拽删除由 agent-device 真实手势验证（测试进程无法合成该长按） |
| **N-18** | P2 | **已修复** | 阅读器底部进度条只有 4pt 高，却作为可交互 AX 元素暴露，点击区域远小于 44pt | V：无障碍审计报 “Hit area is too small”；改为装饰元素隐藏，由百分比文字承载 label/value |

## 3. 产品决策记录

2026-11-17 逐条确认。标记「无动作」的是维持现状，不作为遗留项。

| 议题 | 决策 | 后续动作 |
| --- | --- | --- |
| 反思提示「这次不写」（UX-002/019，N-08） | 改为**只关闭本次**：跳过这次，但不写进永久 dismissal 列表，下次读完（≥2 分钟）仍会提示 | 已完成：跳过只存在内存，重启后卡片回来；旧版本的永久标记仍会读取 |
| 反思草稿是否跨启动（UX-002） | 仍未定 | 需要先看「只关闭本次」上线后的实际补写率；草稿当前不落盘 |
| 横屏行长（N-10） | 最终**保持单栏** | 已复核：当前排版下一行约 34 字，75 字的前提已不成立；Readium 的双栏设置在大屏 iPhone 横屏被 CSS 媒体查询挡掉，强推需重建 navigator，不值得 |
| 拖拽排序语义（N-17） | 保留**交换**，不做插入顺位 | 无动作 |
| 书架顺序是否跨设备同步（N-17） | **不同步**，顺序是本地偏好 | 无动作 |
| 图标 Tab 是否加文字（UX-025） | **保持纯图标** | 无动作 |
| 详情页视觉（UX-020） | 收敛到根页面的系统语义字级与 16/12pt 容器 | 待实现：19pt 标题与胶囊容器改回系统字级 |
| 产品显示名（PRD 命名待定） | **继续用「页外」** | 无动作；`CFBundleDisplayName` 不变 |
| 「想法 / 看法」用词（UX-021） | **统一为「想法」** | 已完成 |
| N-11 三处 P3 细节 | 只做**胶囊 12pt → 16pt** 对齐 | 已完成；「大小」图标与深色黄高亮维持现状 |

早先已决策并实现的：阅读器 Sheet 跟书主题而非系统主题（N-06/N-07）；书架支持「自定义」排序（N-17）。

仍需人工验证、未作为决策项：N-12 的 AX 树重复项要 VoiceOver 真人复验，才能判断是系统伪影还是实现缺陷。

## 4. 发布前必须完成

### 4.1 阻断项

- [ ] 用真实 Provider 跑通：连接测试、解释这段、追问、停止、失败重试、引用回跳、过去反思只读、防剧透边界。
- [ ] 验收结束后撤销 Provider 侧测试 Key，确认 App 内无残留配置。
- [ ] 真机 Release 验证 N-01：翻页/改设置后直接强杀，位置与设置仍能恢复。
- [ ] VoiceOver 走查：书架、阅读器 chrome、选区工具、高亮菜单、问答、反思。
- [ ] 小屏（iPhone SE 尺寸）与横屏：键盘、Sheet、当前书行、阅读行长。

### 4.2 发布前应完成

- [x] 决定并实现阅读器 Sheet 的主题归属（N-06/N-07）。
- [ ] 反思 Sheet 主次：保存为主、跳过为次；明确“这次不写”的后果（N-08）。
- [x] 当前书章节行完整显示（N-09）。
- [ ] 清理模拟器测试数据（《缓慢的注视》、Fixture、测试高亮、待补写会话）。
- [ ] 给 N-01/N-03 补最小回归测试：当前行在 AX 下的几何断言、保存防抖的写入断言（可抽纯逻辑或 repository 测试）。
- [ ] 打开阅读器的真机基线（N-13）；若仍 >1s，再查 navigator 首帧。
- [x] 快照迁移到 `swift-snapshot-testing`（8 张基准，`SNAPSHOT_RECORD=1` 重录）。
- [x] XCUITest 无障碍结构审计 + 冷启动/开书性能基线（`Tests/ReadLoopUITests`）。
- [x] 假 Provider 覆盖 App 侧 AI 链路：流式/停止、失败/重试、引用校验与跳回原文（`-fake-provider`）。
- [x] `swift-format` / `swiftlint` / `Scripts/lint.sh` 接入；CI 用 `LINT_STRICT=1`。
- [ ] 给存量代码做一次 `xcrun swift-format format -i`，让严格门禁能覆盖全部文件。
- [ ] 排查 `ReadLoopCoreTests` 在 iOS 模拟器上的 14 条 Swift Testing 断言失败（`swift test` 通过，疑似平台/运行时差异，与本轮改动无关）。

### 4.3 可以后续做

- [ ] 阅读器 Sheet 的实色/降透明材质（N-07）。
- [ ] 横屏最大行宽（N-10）。
- [ ] 高亮色的深色主题提亮（N-11）。
- [ ] Reduce Transparency 下的菜单兜底（N-14）。
- [ ] 标注列表按章节索引而不是逐行线性查找（性能，当前样本不足以量化）。

## 5. 证据索引

- [最终 UI/UX 验收](07-final-uiux-review.md)
- [回归验收](07-regression-report.md)
- 截图目录：[assets/final-review](assets/final-review/)

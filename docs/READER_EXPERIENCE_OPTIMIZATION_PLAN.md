# Reader 阅读高亮与批注体验优化执行方案

> 状态：阶段 0–3 已完成代码落地；阶段 4 的人工 iPhone 验收待执行
> 更新日期：2026-08-28
> 适用范围：iPhone Reader；高亮创建、颜色选择、既有高亮查看、笔记编辑
> 当前实现基线：`40295f4 feat(reader): add contextual annotation drawer and highlight colors`

## 1. 文档用途

本文是后续 Agent 的执行依据。开始任一阶段前，先阅读本文、`ReadLoop_PRD.md`、`docs/READER_FOUNDATION_XCODE_GATE.md`，再检查当前代码和工作区状态。实现应按阶段形成可独立验证、可独立提交的增量；不得把尚未验证的后续阶段顺手混入当前阶段。

本文的产品结论优先于基线提交中的批注 Sheet 方案：阅读内容是屏幕上的永久主体；高亮与批注交互是短暂、就地、按需展开的上下文工具。

## 2. 目标与成功定义

### 2.1 核心目标

建立一套“零布局位移”的 iPhone 阅读标注体验：

1. 用户选中文字后，先明确选择本次高亮颜色，再创建高亮。
2. 用户点击已有高亮后，只出现紧凑信息卡，立即看见笔记状态和必要操作。
3. 用户主动要求时才进入完整详情或编辑状态。
4. 上述交互不改变 Readium 阅读器的尺寸、排版、页码、滚动位置或当前 Locator。

### 2.2 最高级验收门槛：零布局位移

任何高亮相关 UI 出现、展开、收起时，均须满足：

- `ReadiumReaderView` 的 frame 不发生变化；
- 不通过 `VStack`、`safeAreaInset` 或动态 content inset 为工具 UI 腾出空间；
- 不因工具 UI 出现而重新分页、改变行宽或推动正文；
- 当前被选择或被点击的原文仍保持在原位置；
- UI 消失后不需要跳转或“恢复阅读位置”来掩盖布局变化。

若某个方案无法满足该门槛，应停止实现并记录原因，不得用重新跳转 Locator 作为常规补偿。

### 2.3 可观测结果

- 每次创建高亮前，用户都能看见并选择四种颜色；系统可以预选上次使用色，但不得跳过本次选择机会。
- 点击已有高亮后，一次动作即可看见笔记预览；无笔记时清楚显示“添加笔记”。
- 紧凑信息卡不重复展示大段原文，只提供最多两行的定位摘录。
- 仅在点击“展开”或“编辑”后显示完整内容、键盘和危险操作。
- 点击正文空白处、轻扫翻页、开始滚动或执行关闭动作时，紧凑 UI 可预测地消失。

## 3. 产品原则

### 3.1 阅读优先

正文始终保持视觉主导。标注 UI 使用内容覆盖层，而不是并列工作区。覆盖层保持短促、可逆，且不承担长时间管理笔记的职责。

### 3.2 渐进披露

信息分为三级：

| 层级 | 触发方式 | 显示内容 | 退出方式 |
| --- | --- | --- | --- |
| 创建色板 | 选中文字后点击“高亮” | 四种颜色、取消 | 选色完成、取消、点外部 |
| 紧凑信息卡 | 点击已有高亮 | 两行内摘录、笔记预览或添加入口、颜色、展开 | 点外部、阅读移动、再次点击 |
| 完整详情 | 主动点击展开或编辑 | 完整原文、完整笔记、编辑、颜色、位置、删除 | 完成、下拉/关闭 |

低层级不得提前装入高层级内容。紧凑卡中不直接显示多行编辑器、删除确认、Reflection 操作或完整元数据。

### 3.3 颜色无预设语义

黄色、绿色、蓝色、粉色是用户自己的视觉分类，不在产品文案中绑定“重点”“疑问”等固定含义。可记住最近一次颜色以减少动作，但颜色选择仍发生在每次创建之前。

### 3.4 上下文稳定

工具 UI 应尽量靠近用户刚刚操作的内容，同时保持原文可见。无法取得可靠锚点时，使用屏幕内的浮动位置作为降级，不改动阅读器布局。

## 4. 交互规格

### 4.1 创建高亮

标准路径：

```text
长按并选择文字 → 点击“高亮” → 显示临时色板 → 点击颜色 → 持久化高亮 → 色板与选区消失
```

规则：

- 点击“高亮”时只捕获待创建的 `BookLocator`，不得立即保存默认色高亮。
- 色板默认选中 `lastUsedHighlightColor`，但保存必须由本次颜色点击触发。
- 色板包含黄色、绿色、蓝色、粉色四个至少 44×44 pt 的可点击目标，并提供 VoiceOver 名称和选中状态。
- 创建成功后再清除 Readium selection；失败时保留或可恢复本次选择上下文，并显示现有错误反馈。
- 点击取消或色板外部不创建数据，并清除临时状态。
- 同一 Locator 已有高亮时，不创建重复记录；进入该高亮的紧凑信息卡。
- “笔记”动作可复用同一待提交选择：先选择颜色并创建高亮，再进入笔记编辑；不可暗中创建默认黄色。

### 4.2 点击已有高亮

标准路径：

```text
点击高亮 → 紧凑信息卡 → 查看后关闭
                         ↘ 编辑笔记
                         ↘ 展开详情
```

紧凑信息卡第一屏只包含：

- 最多两行高亮摘录，用于确认当前上下文；
- 有笔记时显示最多三行笔记预览，无笔记时显示“添加笔记”；
- 当前颜色指示及颜色修改入口；
- “编辑”与“展开”操作。

展示规则：

- 卡片是 overlay，不参与 Reader 的布局计算。
- 优先显示在被点击高亮的上方或下方，选择不遮住高亮且可完整容纳卡片的一侧。
- 卡片与高亮至少保持 8 pt 间距，距屏幕可交互边缘至少 12 pt。
- 若 Readium 交互事件无法提供可靠 rect，降级为 safe-area 内的底部悬浮卡；它覆盖少量内容但不推动正文。
- 卡片最大宽度取 `min(屏幕宽度 - 24 pt, 420 pt)`；iPhone 竖屏通常左右各 12 pt。
- 卡片高度由紧凑内容决定，设置合理上限；笔记过长时截断，不扩大成半屏面板。
- 再次点击同一高亮关闭卡片；点击另一高亮原地切换内容。

### 4.3 修改颜色

- 紧凑卡中的颜色入口展开轻量色板，不进入完整详情。
- 点击颜色后乐观更新 decoration 和数据；持久化失败沿用现有回滚语义。
- 修改颜色不关闭紧凑卡，便于用户确认结果。

### 4.4 添加或编辑笔记

- “添加笔记”或“编辑”是显式进入编辑态的动作。
- 编辑态可以使用覆盖式 Sheet，因为用户已主动离开纯阅读态；Sheet 不得改变底层 Reader frame。
- 编辑器打开时直接聚焦输入框；保存后返回紧凑卡，并立即显示最新预览。
- 交互式关闭时，未保存文本应有明确策略：自动保存草稿，或阻止丢失并提示。实现前先检查现有产品约定，保持单一策略。
- 键盘出现和消失不得触发 Readium 重新排版；验证当前 Locator 与可视位置稳定。

### 4.5 完整详情

完整详情只在用户点击“展开”后出现，可包含：

- 完整高亮原文；
- 完整笔记及编辑入口；
- 章节或位置；
- 四种颜色；
- 删除笔记或删除高亮；
- 后续经 PRD 确认的 Reflection 入口。

完整详情不是点击高亮的默认结果。危险操作放在详情层，并保留确认或可恢复语义。

### 4.6 与阅读手势的关系

- 出现文本 selection 时，正文单击不得切换 Reader chrome；沿用现有保护。
- 紧凑卡显示时，点击卡片内不会切换 chrome。
- 点击正文空白处先关闭紧凑卡；同一次点击不再切换 chrome，避免一次点击产生两个视觉变化。
- 翻页、明显滚动、目录/搜索跳转、切换书籍、进入后台时关闭所有临时标注 UI。
- 旋转设备时关闭临时卡片；Reader 按已有 Locator 恢复，不保留过期屏幕坐标。

## 5. 状态模型

临时 UI 使用显式单一状态源，避免 `selectedHighlightID`、多个 Sheet 布尔值和 UIKit overlay 各自竞争。

建议状态：

```swift
enum ReaderAnnotationPresentation: Equatable {
    case hidden
    case choosingColor(PendingSelection)
    case compact(highlightID: UUID, anchor: AnnotationAnchor?)
    case editingNote(highlightID: UUID)
    case detail(highlightID: UUID)
}

struct PendingSelection: Equatable {
    let locator: BookLocator
    let intent: SelectionIntent   // highlight 或 note
    let anchor: AnnotationAnchor?
}

enum AnnotationAnchor: Equatable {
    case rect(CGRect)
    case point(CGPoint)
    case bottomFallback
}
```

实现时可按项目约定调整命名，但须维持以下不变量：

- 任一时刻只有一种 annotation presentation；
- 待选色 Locator 与已持久化 Highlight 明确区分；
- 屏幕坐标只属于当前布局周期，不进入数据库；
- `Highlight.color` 仍是持久化颜色的唯一来源；
- note 仍通过 `Note.highlightID` 关联高亮；
- 关闭临时 UI 不改变阅读 Locator。

## 6. 技术方案与边界

### 6.1 当前实现事实（2026-08-28）

- `ReaderScreen` 使用全屏 `ZStack`，在 Reader 之上呈现临时色板和紧凑批注卡；二者均不参与 Reader 的布局计算。
- `ReadiumReaderView` 全屏并 `.ignoresSafeArea()`；这一点应保持，以确保 Reader frame 稳定。
- `ReaderHostViewController.highlightSelection()` 与 `noteSelection()` 已先保存待选 Locator，用户点选颜色后才持久化。
- Readium 3.3.0 的 `OnDecorationActivatedEvent` 已确认提供 `rect` 和 `point`，且坐标属于 navigator view；紧凑卡优先使用 `rect` 锚定。
- `ReaderModel.update(highlight:color:)` 已具备乐观更新和失败回滚能力，应复用。

### 6.2 呈现层建议

优先在 SwiftUI `ReaderScreen` 的现有 `ZStack` 顶层放置：

- `HighlightColorPaletteOverlay`；
- `AnnotationCompactCard`。

由 `ReaderModel` 或专用轻量 presentation state 提供数据，由 `ReadiumReaderView.Coordinator` 把 Readium 事件转换成语义事件。UIViewController bridge 不负责业务持久化和多层 UI 状态。

如果 SwiftUI 无法可靠取得 WKWebView 内选区锚点，可在 `ReaderHostViewController` 内取得 UIKit 坐标后回传。坐标转换必须以 host view 为基准，并在旋转、trait 变化和页面移动后失效。

### 6.3 锚点能力探针

在正式实现定位前完成一个小型技术探针：

1. 检查 Readium 3.3.0 的 decoration interaction event 字段和坐标空间。
2. 检查 `navigator.currentSelection` 是否暴露 selection rect；若没有，确认 WKWebView/Readium 是否提供受支持的脚本或 API。
3. 在分页与垂直滚动模式分别记录点击高亮和选择文字时可获得的信息。
4. 选择定位策略：可靠 rect → 就近卡片；仅 point → 以点击点为锚；无可靠几何 → 底部悬浮 fallback。

探针完成标准：在文档或代码注释中记录真实 API 能力，不以私有 API 或脆弱 DOM 查询作为默认生产路径。

### 6.4 数据层调整

建议最小调整：

- `saveHighlight(locator:color:)` 要求调用方显式传色；不再依赖构造器默认色完成用户动作。
- 增加仅用于 UI 偏好的 `lastUsedHighlightColor`；优先放入现有 Reader preferences 持久化体系。
- 保持 Locator JSON、href、progression、text before/highlight/after 的现有无损存储。
- 不改变 Highlight/Note 的删除语义，不迁移已有数据。

## 7. 分阶段执行计划

### 阶段 0：建立基线与能力探针（完成）

任务：

1. 确认工作区状态，不覆盖用户未提交修改。
2. 运行当前单元测试和 iOS 构建，记录基线结果。
3. 检查 Readium 3.3.0 的 selection/decorations API，完成第 6.3 节探针。
4. 给零布局位移建立可检查的调试证据：记录 Reader frame、当前 Locator，以及分页/滚动位置变化。

完成结果：Readium 3.3.0 的公开 `OnDecorationActivatedEvent` 提供 navigator view 坐标系中的 `rect` 与 `point`；实现采用 `rect` 就近锚定、无 rect 时底部悬浮 fallback。核心测试与 iPhone 17 Pro 模拟器构建通过。

### 阶段 1：颜色前置与待提交选择（完成）

任务：

1. 引入 `PendingSelection` 和 annotation presentation 状态。
2. 修改“高亮”与“笔记” editing actions：先捕获 Locator，再显示色板。
3. 实现四颜色临时色板和取消路径。
4. 将模型接口改为显式 `saveHighlight(locator:color:)`。
5. 保存并恢复最近使用色，但每次都展示色板。
6. 补充模型与持久化测试。

完成标准：任一新高亮都由本次选色动作产生；取消不写数据库；重复 Locator 不新增记录；四种颜色重启后正确恢复。

完成提交：`43d5259 feat(reader): choose color before creating highlights`

### 阶段 2：紧凑信息卡替代默认详情 Sheet（完成）

任务：

1. 点击 decoration 后进入 `.compact`，不再直接设置 `.annotationDetail` Sheet。
2. 实现紧凑卡的信息层级、截断、颜色指示和添加/编辑/展开入口。
3. 实现 anchor 定位及 bottom fallback。
4. 实现点外部、翻页/滚动、跳转、旋转和后台时的关闭规则。
5. 保留标注列表；从列表跳转后，待 Locator 到达再显示紧凑卡，且不得挤压 Reader。

完成标准：点击高亮只出现紧凑卡；Reader frame 与位置不变；长笔记不会把卡片扩展为大面板；卡片不会遮住被点击高亮（fallback 场景除外，但仍保持原文位置）。

完成提交：`bf51f4d feat(reader): show compact contextual annotation cards`

### 阶段 3：编辑与完整详情渐进披露（完成）

任务：

1. 从紧凑卡进入现有或重构后的笔记编辑器。
2. 把完整原文、位置和删除操作保留在主动展开的详情层。
3. 保存后回到紧凑卡并刷新预览。
4. 验证键盘、交互式关闭、后台和错误回滚。
5. 移除已被替代的自动详情 Sheet 触发链和孤立状态。

完成标准：普通点击不打开键盘或大 Sheet；编辑与详情均由明确动作触发；保存、取消、删除后状态一致且无孤立 UI。

完成结果：紧凑卡只提供笔记预览、颜色、编辑和展开；完整原文、完整笔记、位置和删除继续在用户主动展开的详情 Sheet 中呈现。笔记创建入口会在选色完成后直接进入编辑。

### 阶段 4：iPhone 体验与无障碍验证

至少覆盖：

- 当前最小与最大支持 iPhone 尺寸；
- 竖屏和横屏；
- 分页与垂直滚动；
- 中文、英文、混合文本和屏幕边缘选区；
- system/light/dark/sepia 四种主题；
- Dynamic Type 默认、最大无障碍字号；
- VoiceOver 对颜色、选中态、添加笔记、编辑和展开的朗读顺序；
- 键盘出现、收起、后台、前台、旋转、强退和重启；
- 标注列表跳转及返回历史。

完成标准：`docs/READER_FOUNDATION_XCODE_GATE.md` 中相关 Reader 条目有真实设备或模拟器记录；已知限制被明确记录，不以代码检查代替视觉和手势验证。

建议独立提交：`test(reader): verify contextual annotation interactions`

## 8. 测试要求

### 8.1 自动化测试

必须新增或调整：

- `saveHighlight(locator:color:)` 保存指定颜色；
- 取消 pending selection 不产生 Highlight/Note；
- 重复 Locator 返回已有高亮且不覆盖其颜色；
- 最近使用色偏好持久化；
- presentation 状态转换：hidden → choosingColor → compact；
- note intent 选色后进入 editing；
- 颜色更新失败恢复原颜色；
- 删除当前高亮后 presentation 回到 hidden；
- 切换书籍、跳转和后台清理临时状态。

若坐标定位逻辑被提取为纯函数，应为上方、下方、左右边缘、键盘/安全区和 fallback 编写确定性测试。

### 8.2 手工验收脚本

每种阅读模式至少执行一次：

1. 记住当前页码/段落和高亮原文屏幕位置。
2. 选择文字，打开色板，依次用四种颜色创建高亮。
3. 在色板显示和关闭前后截图，确认正文行宽、分页和位置完全一致。
4. 点击已有高亮，确认紧凑卡首屏能看见笔记预览或添加入口。
5. 点击外部，确认只关闭卡片，不误切换 chrome。
6. 点击编辑，输入长笔记，保存后确认紧凑卡只显示截断预览。
7. 展开详情并删除高亮，确认关联笔记遵循既有保留语义。
8. 在顶部、底部、左右边缘的高亮重复点击，确认卡片在屏幕内且尽量不遮挡原文。
9. 打开卡片后翻页、滚动、旋转和进入后台，确认临时 UI 清理且阅读位置稳定。
10. 强退重启，确认颜色、高亮、笔记和最后阅读位置恢复。

### 8.3 回归命令

Agent 应从仓库配置读取准确命令，至少完成：

- `swift test`；
- 当前项目可用的 iOS simulator build/test；
- 至少一次模拟器可视运行。

注意：`swift test` 可能改变 `Package.resolved` 的 `originHash`。测试结束后检查 diff；若只有工具产生的无关 hash 漂移，恢复到工作区原值，不把该噪声混入功能提交。

## 9. 视觉与动效约束

- 视觉气质保持安静、温暖、轻量，沿用 Elsepage 现有色彩、圆角、材质和排版 token。
- 紧凑卡使用一个清晰层级，不做“迷你详情页”。
- 出现和消失使用短动画，建议 150–220 ms；锚点移动时避免夸张弹簧。
- 色板和卡片均尊重 Reduce Motion、Reduce Transparency 和 Increase Contrast。
- 高亮颜色在四种 Reader 主题下都需保持可见，同时避免影响正文可读性。
- 触控目标最小 44×44 pt；颜色不能作为唯一状态表达，选中色同时提供描边、对勾或无障碍值。

## 10. 明确不在本轮范围

- 为颜色定义固定语义或标签体系；
- 多级文件夹、标签、批注搜索等知识管理功能；
- iPad、macOS 或桌面侧边栏布局；
- 同屏常驻批注栏或推动 Reader 的底部工具箱；
- 自动生成 Reflection 或改变 Agent 对话流程；
- 重构与本体验无直接关系的 Reader、Journal、Voice、Reflection 代码；
- 使用私有 API 或无法稳定维护的 WKWebView DOM 假设换取像素级锚定。

## 11. Agent 工作守则

1. 每阶段开始前列出假设、目标文件和可验证完成标准。
2. 先检查当前实现，不把本文中的建议类型名当成必须照抄的架构。
3. 每条改动都应能追溯到本方案的目标；相邻清理另行记录，不顺手修改。
4. 优先复用现有 `HighlightColor`、Locator、repository 和颜色回滚能力。
5. 涉及 Readium 能力时，以当前锁定版本的源码/API 和真机行为为证据。
6. 当前阶段测试失败时继续诊断，不用降低断言或删除覆盖来获得绿灯。
7. 保留用户工作区中的无关修改；提交前只暂存本阶段文件。
8. 每个提交结束时报告：实现内容、未实现内容、自动测试、手工验证、已知限制和工作区状态。

## 12. 最终完成定义

只有同时满足以下条件，阅读高亮与批注优化才可标记完成：

- 四阶段功能和验证均完成；
- 创建高亮前始终有本次颜色选择机会；
- 点击高亮默认只出现紧凑信息卡；
- 完整详情和编辑均由用户主动触发；
- 分页与滚动模式下均证明 Reader frame、排版和可视位置没有因标注 UI 改变；
- 颜色、高亮、笔记及 Locator 经强退和重启后正确恢复；
- VoiceOver、Dynamic Type、四种主题及边缘选区通过验收；
- 自动测试和 iOS 构建通过；
- `docs/READER_FOUNDATION_XCODE_GATE.md` 已同步真实验证结果；
- 工作区不包含无关格式化、依赖 hash 漂移或其他噪声修改。

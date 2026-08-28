# Reader 阅读高亮与批注体验优化执行方案

> 状态：交互已完全重做（v2「就地标注」）；代码、包级测试与 iOS 模拟器构建已通过；**真机人工验收待执行**
> 更新日期：2026-08-28
> 适用范围：iPhone Reader；高亮创建、颜色选择、既有高亮查看、笔记编辑
> 前一版基线：`89ed369`（色板 → 紧凑卡 → 详情 Sheet 方案，已废弃）

## 0. v2 重做决定（2026-08-28）

用户结论：v1 的高亮与笔记体验不可用，授权完全重做客户端交互。v1 的根本问题：

1. 创建一个高亮需要「点高亮 → 点颜色」两步，最高频动作被加了一道工序；
2. 创建完成后还会弹出紧凑信息卡，用户必须再把它关掉——标注行为以浮层骚扰收尾；
3. 色板出现在屏幕底部，远离选区，视线被迫离开刚选中的文字；
4. 笔记路径（选中 → 笔记 → 选色 → 详情 Sheet → 键盘）链路过长；
5. 紧凑卡/详情 Sheet 是三套并存的临时 UI，状态多、心智负担重。

v2 核心原则：**一切标注交互锚定在内容现场，一步直达，动作结束即收场，永不弹“确认你刚才做了什么”的浮层。** 零布局位移门槛（原第 2.2 节）继续有效：任何标注 UI 的出现与消失不得改变 Readium 阅读器的 frame、排版、分页或当前 Locator。

v1 方案中「创建前必须先选色」的产品结论自 v2 起废除：创建动作使用最近使用色即时完成，调整颜色的机会转移到了选区工具条（创建时直接点色点）与高亮菜单（事后改色），两者都比「先选色再创建」更少一步。

## 1. 交互规格（v2）

### 1.1 选区工具条（新建标注）

```text
长按选择文字 → 自建工具条出现在选区上方（下方放不下时在下方）
工具条 = [黄 绿 蓝 粉] | 笔记 · 聊聊 · 复制
点色点   → 立即用该色创建高亮，选区清除，工具条消失（一步完成）
点笔记   → 按最近使用色创建高亮，打开笔记编辑器
点聊聊   → 清除选区，进入既有 Reflection 流程
点复制   → 写入剪贴板，显示「已复制」胶囊
```

- 系统文本菜单（UIMenuController/UIEditMenu）被完全抑制：`SelectableNavigatorDelegate.shouldShowMenuForSelection` 恒返回 `false`，Readium `Selection.frame`（navigator 视图坐标，即全屏坐标）作为工具条锚点。
- 不变式：**选区存在 ⇔ 工具条可见**。选区每次变化（包括拖动选择手柄）都会重新回调并重新锚定。
- 工具条出现时，全屏 tap 捕获层（挖去选择手柄两个区域的偶奇路径）拦截一切点击：点正文任意处 = 关闭工具条并清除选区，同一次点击不切换 chrome。
- 若 locator 转换失败（理论边界），回调返回 `true` 回退到系统菜单。

### 1.2 高亮菜单（查看/修改既有标注）

```text
点击已有高亮 → [黄 绿 蓝 粉] | 笔记 · 删除（锚定在高亮的上方/下方）
点色点       → 乐观换色，菜单保持打开便于比较
点笔记       → 打开笔记编辑器（有笔记时按钮带圆点指示）
点删除       → 立即删除 + 底部「已删除高亮 · 撤销」胶囊（5 秒）
再次点同一高亮 → 关闭菜单；点另一高亮 → 原地切换
```

- 锚点来自 `OnDecorationActivatedEvent.rect`（navigator 坐标系）。装饰点击不会触发 tap 事件，因此菜单打开与 chrome 切换互不干扰。
- 点正文空白 → `didTapAt` 关闭菜单，不切换 chrome；翻页、滚动、目录/搜索跳转、旋转、进入后台 → 菜单消失。
- 删除语义：高亮删除后其笔记**持久化解绑**为独立笔记（修复 v1 只改内存、重启后悬挂的缺陷）；5 秒内点撤销则恢复高亮并重新关联笔记。撤销窗口过期后笔记保留为独立笔记。

### 1.3 笔记编辑器

- 底部 Sheet（340pt/large 两档 detent），内容 = 摘录（衬线，滚动区）+ 自动聚焦的编辑器 + 「完成」。
- **实时保存**：输入防抖 400ms 落库，dismiss 时 flush。没有保存/取消按钮——笔记永远等于编辑器内容（PRD P2：用户原始表达不可丢失）。
- 首次输入才创建笔记；整篇清空 → 删除笔记并出现「已删除笔记 · 撤销」。编辑 Sheet 不改变底层 Reader frame。

### 1.4 定位规则

`Sources/ReaderCore/AnnotationMenuPlacer.swift`（纯几何，CoreGraphics，12 个单元测试）：

- 优先贴锚点上方（间距 10pt）；上方放不下放下方；两侧都放不下贴顶。
- 水平以锚点中心对齐，钳制在安全区内 12pt。
- 无锚点（如标注列表跳转到达）时停靠屏幕底部。
- `selectionHandleZones` 给出选择手柄穿透区域（起点上、终点下），供捕获层挖孔。

坐标系规则（真机验收修正，2026-08-28）：覆盖容器必须 `.ignoresSafeArea()`，使其局部坐标与 Readium navigator 的全屏 frame **1:1** 对齐；安全区数值从 key window（UIKit）读取——GeometryReader 在安全区内报告的 insets 为零，直接使用会把所有锚点下移一个状态栏高度、让菜单压住高亮。

### 1.5 状态模型

```swift
enum ReaderAnnotationMenu: Equatable {
    case selection(ReaderSelectionContext)        // locator + text + frame
    case highlight(id: UUID, anchor: CGRect?)     // anchor nil → 底部停靠
}
var noteEditorRequest: ReaderNoteEditorRequest?   // 每次呈现携带新 UUID（同一条笔记二次打开也必然重新呈现）；onDismiss 显式复位
var transientNotice: ReaderTransientNotice?       // copied / deletedHighlight(+undo 数据) / deletedNote
```

不变量：任一时刻至多一种菜单（selection 与 highlight 互斥）；锚点坐标只存在于当前布局周期，不进数据库；`Highlight.color` 仍是持久化颜色唯一来源；note 通过 `Note.highlightID` 关联；关闭任何标注 UI 不改变阅读 Locator。

## 2. 实现位置

| 文件 | 职责 |
| --- | --- |
| `Sources/ReaderCore/AnnotationMenuPlacer.swift` | 锚定/挖孔纯几何 + 测试 |
| `App/Reader/ReaderModel.swift` | 标注状态机：selection/highlight 菜单、创建（含同锚点改色）、删除+撤销、实时笔记保存、notice 定时器 |
| `App/Reader/ReadiumReaderView.swift` | `shouldShowMenuForSelection`（恒 false + 上报选区）、装饰点击 → 高亮菜单、`didTapAt` 关闭菜单不切 chrome、旋转清场 |
| `App/Reader/AnnotationUI.swift` | 全屏覆盖容器（与 navigator 坐标 1:1）、选区工具条、高亮菜单、tap 捕获层、撤销胶囊、笔记编辑器 |
| `App/Reader/ReaderScreen.swift` | 覆盖层挂载、note editor sheet、标注列表跳转（高亮行 → 到位后弹菜单；独立笔记行 → 跳转后开编辑器） |

## 3. 真机人工验收清单（待用户执行）

基础：任一 EPUB。每种阅读方式（分页/滚动）至少完整执行一次。

1. 长按选择文字 → 自建工具条出现在选区正上方；系统菜单不出现。
2. 分别点四种色点 → 高亮即时出现、颜色正确、工具条消失，全程无第二步骤。
3. 拖动选择手柄扩大/缩小选区 → 工具条跟随重新锚定（手柄区域未被捕获层挡住）。
4. 点「笔记」→ 按最近色创建高亮并弹出编辑器，自动聚焦；输入长文本，中途返回阅读再进入 → 内容完整（实时保存）。
5. 清空一篇已有笔记 → 笔记被删并出现「已删除笔记 · 撤销」；点撤销恢复。
6. 点击已有高亮 → 菜单锚定其上/下方；当前色有对勾；换色立即生效且菜单不关。
7. 点「删除」→ 高亮消失 + 撤销胶囊；5 秒内撤销 → 高亮与关联笔记完整恢复；不撤销 → 笔记在「标注」列表中保留为独立笔记。
8. 再次点同一高亮 → 菜单关闭；点正文空白 → 菜单关闭且 chrome 不切换。
9. 菜单/工具条打开时翻页、滚动、目录跳转、旋转、进入后台 → 临时 UI 消失，阅读位置与排版无任何变化（零布局位移）。
10. 「聊聊」→ Reflection 流程；「复制」→ 剪贴板内容正确。
11. 标注列表：点高亮行 → 跳转到位后高亮菜单自动出现；点独立笔记行 → 跳转后直接进入笔记编辑。
12. 强退重启 → 高亮、颜色、笔记、最近使用色、阅读位置全部恢复。
13. VoiceOver：色点（含选中态）、笔记、删除、撤销可正确朗读；Dynamic Type 最大字号下按钮不裁切。
14. system/light/dark/sepia 四主题下高亮与工具条可见性正常。

## 4. 已知限制（有意取舍，待记录反馈）

- 系统菜单的「查询 / 翻译 / 分享」未迁移到自建工具条（当前保留复制）。如真机验收反馈需要，优先用 `UIReferenceLibraryViewController` 加回「查询」。
- 工具条依赖 DOM `selectionchange`（Readium 官方 JS 管线，非脆弱 DOM 假设）；VoiceOver 文本选择的路径未真机验证。
- 高亮 Locator 精度与 v1 完全一致（`currentLocation + text` 锚定），无回归、无增强。
- 错误处理沿用乐观更新 + 失败回滚 + 全局 alert；创建失败时选区已清除（与 v1 相同）。
- 未做 iPad / 横屏特殊布局（横屏按同一规则钳制）。

## 5. 机器验证记录（2026-08-28）

- `swift test`：215 tests passed（含新增 `AnnotationMenuPlacerTests` 12 项：上方/下方/贴顶、水平钳制、无锚点停靠、手柄区域边界）。
- `xcodebuild -project ReadLoop.xcodeproj -scheme ReadLoop -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build`：BUILD SUCCEEDED。
- 真机验收未执行；`docs/READER_FOUNDATION_XCODE_GATE.md` 的 Reader 条目待真实设备记录。

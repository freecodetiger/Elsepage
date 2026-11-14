# 书架：方案 1 的原生收敛

2026-11-14。用户在三个版式中认为方案 1 更接近目标，但仍有“demo 味”，要求以 iOS 原生 / SwiftUI 最佳实践和奥卡姆剃刀重做。本轮只重做书架首屏的版式、组件和字级。2026-11-14 更新：书架已落到 App；阅读器未改。

[打开静态样张](../prototypes/elsepage-native-refinement.html)。单文件、无 JavaScript、无网络请求；393×852 两帧只区分“默认”和“有未写想法”，不是可交互演示。书名、作者、进度和封面均为演示数据。

结论不是把方案 1 继续放大，而是把自绘的 Web 组件换成系统组件，并把可省的交互删掉；阅读顺序保持不变：继续阅读在上，全部书籍在下。

## 删掉了什么

| 方案 1 | 原生收敛 | 原因 |
| --- | --- | --- |
| 两枚 52pt 大按钮（继续阅读 / 补写想法） | 当前书整行可点；“补写想法”只在有未写想法时出现，并叠在当前行右下角 | 行本身就是继续阅读，第二个大按钮重复同一动作；没有上下文的补写不该常驻，也不该把下面的网格推下去 |
| 自绘状态栏、标签栏、搜索框、手机外框 | 系统状态栏、`TabView`、`.searchable` | 自绘 chrome 是 demo 味的主要来源；系统组件自带材质、滚动边缘行为、Dynamic Type 和 VoiceOver |
| 36 / 26 / 20 / 16 / 15 / 14 六档混合字号，负字距 | 34 / 22 / 20 / 17 / 15 / 13 系统文本样式，无字距 | 36、26、14 不在 Apple 文本样式表上；负字距是网页排版习惯，中文不需要 |
| 24pt 页边距，15 / 13 / 30 等混排间距 | 16pt 页边距，4 / 8 / 12 / 16 / 24 / 32 的 8pt 网格 | iOS 内容默认 16；随意值让版面显得“摆”出来而不是长出来 |
| 双列封面，30pt 行间距 | 三列 112pt 封面，12 / 24 间距 | 与 iOS 图书和当前 App 的密度一致；当前书用 120×180 的更大封面建立层级，不靠两列大图 |
| 绿色主按钮、wash 底、彩色胶囊 | 现有 `ElsepagePalette` 单色 UI，封面承担颜色 | 界面只保留一套语义色；绿色方案 1 的颜色并不在 App 的调色板里 |
| 自绘手机框、方案切换器、spec 侧栏、入场动画 | 静态两帧，无切换器 | 评审工具混进画面会像 demo；静态样张只回答版式问题 |
| 搜索图标展开自绘输入框 | `.searchable` | 系统搜索栏自带取消、键盘避让、无障碍 |
| 内容区的“最近 / 书名”排序文字 | 工具栏 `Menu` | 排序是低频全局动作，不占内容区 |
| 网格里的进度条与第三行状态文字 | 网格只保留书名、作者；进度只出现在当前阅读行 | 单格三行小字过密；单本书的章节与统计在阅读器和当前行里 |

## 版式与字级

| 用途 | 样张 | SwiftUI | 说明 |
| --- | --- | --- | --- |
| 页面标题 | 34 / Bold | `.largeTitle`（`navigationTitle` 自动） | 不再手写 36 |
| 区块标题 | 20 / Semibold | `.title3.weight(.semibold)` | “继续阅读”“全部书籍” |
| 当前书名 | 22 / Semibold | `.title2.weight(.semibold)` | |
| 正文 / 操作 | 17 / Regular | `.body` | 搜索栏由系统提供 |
| 作者、次要信息 | 15 / Regular | `.subheadline` | |
| 进度、网格作者 | 13 / Regular | `.footnote` | |
| Tab 标签 | 10 / Medium | 系统 `TabView` | 不自绘标签栏 |
| 封面题字 | 22 / 宋体 | 封面图像，不是 UI 字体 | 生产中为真实 EPUB 封面 |

- 页边距 16，标题、搜索栏、内容与工具栏共用同一条左侧基线。
- 纵向节奏：标题到内容 12，区块之间 32，当前行内 16，网格列 12、行 24。
- 封面 2:3、圆角 4；当前书 120×180，网格 112×168。
- 触达：当前行整行可点；工具栏按钮 44；补写胶囊高 30，左缘对齐正文栏（距右 128），方便左手单手够到。
- 颜色只使用现有语义 token：背景 `#F2F2F2`、主文字 `#111`、次要 `#666`、分隔 `#D4D4D4`、强调 `#111`。封面本身承担颜色，不新增 UI 色板。

## SwiftUI 结构

```swift
NavigationStack {
    ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
            sectionHeader("继续阅读")
            ZStack(alignment: .bottomTrailing) {
                Button { open(book) } label: {
                    CurrentReadingContent(book: book, progress: progress)
                }
                .buttonStyle(.plain)

                if pendingReflection != nil {
                    WriteReflectionChip()                        // 兄弟节点，不嵌在行按钮里
                        .padding(.trailing, 16)
                }
            }
            .frame(height: 180)                                  // 行高由封面固定，胶囊不参与
            sectionHeader("全部书籍").padding(.top, 32)
            LazyVGrid(columns: columns, spacing: 24) { /* 三列封面 */ }
        }
        .padding(.horizontal, 16)
    }
    .navigationTitle("书架")
    .searchable(text: $model.searchQuery, prompt: "搜索书名或作者")
    .toolbar { sortMenu; importButton; settingsButton }
}
```

- 三列用 `GridItem(.flexible(), spacing: 12)`；Accessibility 字号退化为一列，保留现有逻辑。
- 所有文字使用语义字体，不写 `.system(size:)` 和 `.tracking`。
- 封面是图片，不参与 UI 字体；封面阴影沿用现有 `ElsepageBookCoverMetrics`。
- 补写入口复用现有 `pendingReflection` 数据，只改变位置：从网格格子内移到当前阅读行右下角，作为 `ZStack` 里的兄弟 overlay。行高固定 180，胶囊出现或消失都不改变行高、网格位置和内容高度。现有代码已经把它做成行按钮的兄弟节点，这条约束继续保留。

## 状态

- 默认：当前阅读行 + 全部书籍网格。
- 有未写想法：当前行左下、左缘对齐正文栏多一枚 `.bordered` 小胶囊；行高固定，全部书籍与内容高度不变。
- 空书架、搜索无结果、导入中：沿用现有 `ContentUnavailableView`、`ContentUnavailableView.search` 和底部导入状态。
- 排序：工具栏 `Menu`，与现有实现一致。
- 本轮不覆盖阅读器、想法、我的和设置页。

## 与现有实现的差异（已落地）

- `LibraryView`：大标题、搜索和工具栏已经符合原生结构；新增“继续阅读”行与两个区块标题，当前书从网格移出。
- `LibraryGridView`：页边距 20 → 16；书名从 `.title3` 衬线改为 `.subheadline.semibold`；作者从 `.caption` 改为 `.footnote`；移除每格状态行和进度条；三列保留。
- `ElsepageTheme.Spacing`：本轮不改全局 6 / 10 / 20 / 28，书架局部使用 16 / 12 / 24 / 32，避免连带其它页面。
- 待写想法入口：位置改为当前行右下的 overlay，不参与布局；数据与保存路径不变。

## 验证

- 单文件：0 个 `<script>`，0 个外部 `href` / `src`。
- Chrome 实际渲染（393×852，2x）：大标题 34/700 无字距；区块标题 20/600；当前书名 22/600；作者 15；进度 13；页边距 16；网格三列 112.33，列距 12、行距 24；封面 2:3、圆角 4；标签栏 83；Home Indicator 134×5；内容无横向溢出；内容按系统行为延伸到标签栏下方。
- 两帧的当前行高均为 180，`.section-title--grid` 顶部均为 460，内容滚动高度均为 856；胶囊为 `position: absolute`，出现时不改变任何一项。
- 对比度：主文字 16.87:1，次要文字 5.13:1，未选中 Tab 4.84:1，六张封面 5.5:1 以上，均达到 WCAG AA。
- 限制：静态样张不是 App 截图；未在 SwiftUI 或真机验证 Dynamic Type、VoiceOver、滚动边缘材质；封面是演示排版，不是真实书封；本轮没有 Swift 改动，未运行 `swift test`。

已落到 `LibraryView` / `LibraryGridView`；阅读器未改。

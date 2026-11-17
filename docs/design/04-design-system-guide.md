# ElsePage Design System Guide

2026-11-15。范围：首批 tokens、通用组件、组件目录与测试。**本阶段不批量改写业务页面**；现有页面继续工作，新页面/迁移中的页面逐步使用。

## 1. 架构决定

### 1.1 不新建 SPM 模块

设计系统放在现有的 `App/DesignSystem/`，原因：

- App 目前不是 Swift Package target；`DesignSystem` 是 App 目录，不是独立模块。
- 组件依赖 `ElsepagePalette`（`Sources/AppInfrastructure`）和 App 的 `Color.elsepage*` 语义色；把它抽成新 package 会额外引入一层模块边界，并把 SwiftUI 组件与 App 主题拆开。
- 本阶段的目标是建立可复用层，不是重画工程依赖图。

因此**没有新增第三方依赖，没有改 Package.swift，没有改现有模块依赖**。

### 1.2 与旧 `ElsepageTheme` 的关系

`ElsepageTheme` 保留为兼容层，已有页面继续使用。新代码使用：

- `ElsepageColor`
- `ElsepageFont`
- `ElsepageSpacing`
- `ElsepageRadius`
- `ElsepageBorder` / `ElsepageElevation`
- `ElsepageMotion`
- `ElsepageState`

两者最终都走 `ElsepagePalette` 与系统字体/动态类型，所以可以在同一屏共存，逐步迁移。**不要为了统一一次性改掉旧页面的排版数值**；旧页面有 20pt 页边距、6/10/28 间距等历史值，迁移时按设计规范逐屏收敛。

### 1.3 文件

| 文件 | 职责 |
| --- | --- |
| [ElsepageDesignTokens.swift](../../App/DesignSystem/ElsepageDesignTokens.swift) | 语义色、字体、间距、圆角、边框、阴影、动效、状态 token |
| [ElsepageDesignComponents.swift](../../App/DesignSystem/ElsepageDesignComponents.swift) | Button / IconButton 状态、List Row、Section Header、Input、Card、Empty / Loading / Error、Banner / Toast |
| [ComponentCatalogView.swift](../../App/DesignSystem/ComponentCatalogView.swift) | DEBUG-only 组件目录与 Light / Dark / Accessibility 预览 |
| [ElsepageComponents.swift](../../App/DesignSystem/ElsepageComponents.swift) | 既有 `ElsepageIconButton`、`ElsepageBookCover`、`ElsepageRootHeader`、`ElsepageSearchField`；本轮把 IconButton 扩展为多角色 |
| [ElsepageTheme.swift](../../App/DesignSystem/ElsepageTheme.swift) | 旧 token 兼容层 |
| [Tests/DesignSystemTests](../../Tests/DesignSystemTests) | token 单测 + 8 张组件快照 |

## 2. Tokens

### 2.1 Semantic colors

所有颜色来自 `ElsepagePalette`，随系统 Light/Dark 自动切换；不要在页面写 `.black`、`.gray`、RGB。

| Token | 用途 |
| --- | --- |
| `ElsepageColor.canvas` | 页面底色 |
| `ElsepageColor.surface` | 卡片、表单、导航表面 |
| `ElsepageColor.surfaceSecondary` | 嵌套表面、次级容器 |
| `ElsepageColor.border` / `.separator` | 描边、分隔线 |
| `ElsepageColor.textPrimary` | 标题与正文 |
| `ElsepageColor.textSecondary` | 辅助说明 |
| `ElsepageColor.textTertiary` | 元信息、占位符 |
| `ElsepageColor.accent` / `.onAccent` | 交互色与交互色上的内容 |
| `ElsepageColor.success` / `.warning` / `.danger` | 状态色 |
| `ElsepageColor.pressedOverlay` | 按下态覆盖层 |
| `ElsepageColor.disabledContent` | 禁用内容 |
| `ElsepageColor.scrim` | 遮罩 |

规则：

- 状态色只表达状态，不用来装饰。
- 不要在浅色/深色里分别判断颜色；如果必须判断，说明 token 不够语义化。
- 新增颜色先加到 `ElsepagePalette`，不要在组件里写死。

### 2.2 Typography

全部使用 `Font.TextStyle`，Dynamic Type 自动生效。

| Token | 规格 |
| --- | --- |
| `ElsepageFont.display` | `.largeTitle` bold |
| `ElsepageFont.title1` | `.title` semibold |
| `ElsepageFont.title2` | `.title2` semibold |
| `ElsepageFont.title3` | `.title3` semibold |
| `ElsepageFont.headline` | `.headline` |
| `ElsepageFont.body` | `.body` |
| `ElsepageFont.callout` | `.callout` |
| `ElsepageFont.subheadline` | `.subheadline` |
| `ElsepageFont.footnote` | `.footnote` |
| `ElsepageFont.caption` / `.caption2` | `.caption` / `.caption2` |
| `ElsepageFont.bookTitle` | `.title2` serif semibold |
| `ElsepageFont.serifBody` | `.body` serif |
| `ElsepageFont.mono` | `.footnote` monospaced |

不要用 `.system(size:)` 写固定字号；只有封面艺术字等非 UI 文本可以例外（且必须自行处理大字号）。

### 2.3 Spacing

4pt 网格；2pt 只用于光学微调或细线。

```text
xxs 2 · xs 4 · sm 8 · md 12 · lg 16 · xl 20 · xxl 24 · xxxl 32 · huge 40
page 16 · touchTarget 44 · controlHeight 44 · fieldMinHeight 44
buttonHeight 48 · compactButtonHeight 44
```

`ElsepageSpacing.page` 是三个根页面/Sheet 的页边距。旧页面的 `ElsepageTheme.Spacing.page` 仍是 20；迁移时按屏幕规范决定，不要机械替换。

### 2.4 Radius / Border / Elevation

| Token | 值 | 用途 |
| --- | --- | --- |
| `ElsepageRadius.xs` | 4 | 小标签 |
| `.sm` | 8 | 小控件 |
| `.md` / `.card` | 12 | 卡片、行容器 |
| `.lg` | 16 | 较大容器 |
| `.xl` | 24 | Sheet 级容器 |
| `.field` | 10 | 输入框 |
| `.button` | 12 | 按钮 |
| `ElsepageBorder.hairline` | 0.5 | 分隔/描边 |
| `.regular` | 1 | 常规描边 |
| `.strong` | 1.5 | 聚焦/错误描边 |

阴影：

- `ElsepageElevation.none`：默认。
- `.card`：轻量卡片。
- `.floating`：浮层/胶囊。
- `.cover`：书封。

**默认不要给每一行加卡片**。行属于容器，卡片属于成组内容。

### 2.5 Motion

| Token | 用途 |
| --- | --- |
| `ElsepageMotion.quick` | 按下、显隐 |
| `.standard` | 状态切换、Toast |
| `.slow` | 较大的转场 |
| `interactive(reduceMotion:)` | 按键/行的按下动画；Reduce Motion 返回 nil |
| `standard(reduceMotion:)` | 状态动画；Reduce Motion 返回 nil |

### 2.6 Component states

| 状态 | 约定 |
| --- | --- |
| Normal | 默认 appearance |
| Pressed | 0.86 opacity + `pressedOverlay`；可加 0.98 scale |
| Disabled | 0.38 opacity；`.disabled(true)` |
| Loading | 0.72 opacity；显示 `ProgressView`；`.disabled(true)` |
| Error | 输入框 `danger` 描边 + inline error；页面级用 `ElsepageErrorState` |

`ElsepageControlState` 是目录/快照用的展示枚举，不进入业务模型。

## 3. Components

完整 API 与状态见 [组件目录](04-component-catalog.md)。以下是使用规则。

### 3.1 Button

```swift
ElsepageButton(
    title: "继续阅读",
    systemImage: "bookmark",
    role: .primary
) {
    openBook()
}
```

- role：`.primary` / `.secondary` / `.destructive` / `.quiet`。
- size：`.regular` / `.compact`。
- `isLoading` 显示 spinner 并禁用；`isEnabled` 控制禁用。
- 全宽默认；行内动作传 `isFullWidth: false`。
- 仍然使用原生 `Button`，没有重写点击/无障碍。

### 3.2 Icon Button

既有 `ElsepageIconButton` 已扩展：

```swift
ElsepageIconButton(
    systemName: "gearshape",
    accessibilityLabel: "设置",
    role: .surface
) { openSettings() }
```

role：`.surface` / `.plain` / `.filled` / `.destructive`；支持 `isEnabled` / `isLoading`。默认 role 保持旧调用点不变。

### 3.3 List Row

```swift
ElsepageCard(padding: 0) {
    ElsepageListRow(
        title: book.title,
        subtitle: book.author,
        metadata: "读到 42% · 12 分钟",
        systemImage: "book.closed",
        showsChevron: true,
        action: open
    )
}
```

- 行本身透明；容器用 `ElsepageCard` 或系统 `List`。
- `action == nil` 时是静态行。
- 支持 title 2 行、subtitle 2 行、metadata 1 行；长文本不会撑破布局。
- `isEnabled` 控制禁用样式。

### 3.4 Section Header

```swift
ElsepageSectionHeader(
    title: "全部书籍",
    count: 12,
    actionTitle: "排序",
    action: showSort
)
```

- `title` 20/600 + header trait；count 13pt tertiary；action 右侧。
- 不包含外部 padding；由调用方用 `ElsepageSpacing` 排版。

### 3.5 Input

```swift
ElsepageInput(
    title: "模型名称",
    text: $modelID,
    prompt: "按服务商填写",
    helper: "测试连接会使用当前填写内容。",
    error: modelID.isEmpty ? "模型名称不能为空。" : nil
)
```

- 使用原生 `TextField` / `SecureField`；支持 `textContentType`、键盘类型、submit label。
- 错误优先于 helper；聚焦/错误描边使用 accent/danger。
- 不内置表单验证逻辑，只展示传入的状态。

### 3.6 Card

```swift
ElsepageCard(style: .surface) { ... }
```

- `.surface` / `.secondary` / `.elevated` / `.plain`。
- 默认 16pt 内边距、12pt 圆角、hairline 描边。
- 适合成组内容，不适合每个列表行。

### 3.7 Empty / Loading / Error

```swift
ElsepageEmptyState(title: "还没有留下记录", message: "…", systemImage: "quote.bubble")
ElsepageLoadingState(message: "正在整理你的记录…")
ElsepageErrorState(title: "无法打开本地书库", message: "…", retry: retry)
```

- Empty/Error 薄封装系统 `ContentUnavailableView`，保留系统排版与无障碍。
- Loading 使用 `ProgressView` + 文案；`isFullScreen` 控制是否占满。
- 表单内联错误用 `ElsepageInlineError`。

### 3.8 Banner / Toast

```swift
ElsepageBanner(style: .success, title: "已保存到本机", message: "…")

content.elsepageToast(
    isPresented: $showsToast,
    style: .error,
    message: "网络不可用",
    actionTitle: "重试",
    action: retry
)
```

- Banner 是布局内提示；Toast 是贴底浮层。
- 不自动消失；显隐由调用方控制（避免业务状态被隐藏的 timer 抢走）。
- Reduce Motion 下 Toast 不动画。

## 4. Light / Dark / Dynamic Type

- 颜色全部来自动态 `ElsepagePalette`；组件不做 `colorScheme` 分支。
- 字体全部使用 `Font.TextStyle`；组件使用 `minHeight`/多行文本，不写固定高度掩盖大字号问题。
- Icon Button 的触达尺寸用 `@ScaledMetric`；`ElsepageSpacing.touchTarget` 是最小值。
- 大字号下：
  - Button 标题可换行；不要用 `lineLimit(1)` 压死。
  - List Row title/subtitle 2 行；metadata 1 行。
  - 输入框随字体增长最小高度。
- 目录提供 `Catalog — Accessibility XL` 预览。

## 5. 工程质量

- 没有新增第三方依赖。
- 组件不持有业务状态；loading/error 由调用方传入。
- 不重写 `NavigationStack` / `TabView` / `Sheet` / `Button` / `TextField` 的交互语义。
- 设计系统单测：`Tests/DesignSystemTests`（12 个用例，8 张快照）。
- 快照使用 `ImageRenderer` + PNG 参考图，不引入 snapshot-testing 依赖。
- 工程由 `xcodegen generate` 注册新文件与 `DesignSystemTests` target；`ReadLoop.app` 产物名保持 `ReadLoop.app`。

### 5.1 测试命令

```sh
xcodebuild -project ReadLoop.xcodeproj -scheme ReadLoop \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -derivedDataPath /tmp/elsepage-native-build \
  -only-testing:DesignSystemTests test
```

快照有意变更时，把 `Tests/DesignSystemTests/SnapshotSupport.swift` 的 `recordMode` 改为 `true`，运行一次，改回 `false`，再运行确认；参考图在 `Tests/DesignSystemTests/__Snapshots__/`。

## 6. 限制

- 快照是 **iOS 模拟器 + 当前系统** 的参考图；换 OS/字体/设备可能产生像素差异，需要在目标环境重录，不能把它当跨平台视觉真理。
- 目录是 `#if DEBUG`，不进入 Release 界面；没有业务路由。
- 只覆盖本轮列出的组件；表单、Toast 自动消失、复杂菜单等仍由业务/系统组件负责。
- `ElsepageTheme` 旧 token 与新 token 并存；迁移完成前会有一段双轨期。
- 未做 VoiceOver 全流程、iPad、横屏、Reduce Motion 全界面验收；组件层有无障碍标签，但不等于产品级验收。
- 组件尚未批量替换现有页面；下一阶段按 [迁移指南](04-migration-guidelines.md) 逐屏进行。

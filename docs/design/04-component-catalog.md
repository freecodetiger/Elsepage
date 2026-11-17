# ElsePage Component Catalog

2026-11-15。目录的源码：[ComponentCatalogView.swift](../../App/DesignSystem/ComponentCatalogView.swift)。组件实现：[ElsepageDesignComponents.swift](../../App/DesignSystem/ElsepageDesignComponents.swift)。所有预览均为 DEBUG。

## 1. 如何查看

1. 用 Xcode 打开 `ReadLoop.xcodeproj`。
2. 打开 `App/DesignSystem/ComponentCatalogView.swift`。
3. 在 Canvas 选择：
   - `Catalog — Light`
   - `Catalog — Dark`
   - `Catalog — Accessibility XL`
4. 目录没有接入 Tab 或 Settings；它是开发/评审页面，不是产品入口。

## 2. 组件与状态覆盖

| 组件 | Normal | Pressed | Disabled | Loading | Error | Light / Dark |
| --- | --- | --- | --- | --- | --- | --- |
| Button | 是 | 是（用 `ButtonChrome` 展示按下态） | 是 | 是 | — | 是 |
| Icon Button | 是 | 系统按下态 | 是 | 是 | — | 是 |
| List Row | 是 | 是（ButtonStyle） | 是 | — | — | 是 |
| Section Header | 是 | — | — | — | — | 是 |
| Input | 是 | 聚焦描边 | 是 | — | 是 | 是 |
| Card | surface / secondary / elevated / plain | — | — | — | — | 是 |
| Empty State | 是 | — | — | — | — | 是 |
| Loading State | 是 | — | — | 是（本身就是 loading） | — | 是 |
| Error State | 是 | — | — | — | 是 | 是 |
| Banner | info / success / warning / error | — | — | — | 是 | 是 |
| Toast | info / success / warning / error | — | — | — | 是 | 是 |

`Button` 的 Pressed 预览使用 `ElsepageButtonChrome` 直接渲染；实际 `Button` 的按下态由 `ButtonStyle` 在运行时提供，二者共享同一套 chrome。

## 3. 快照

参考图位于 [Tests/DesignSystemTests/__Snapshots__](../../Tests/DesignSystemTests/__Snapshots__)。快照测试使用 `ImageRenderer`（无第三方依赖）。

### Buttons

| Light | Dark |
| --- | --- |
| ![Buttons light](../../Tests/DesignSystemTests/__Snapshots__/buttons-light.png) | ![Buttons dark](../../Tests/DesignSystemTests/__Snapshots__/buttons-dark.png) |

### List Row

| Light | Dark |
| --- | --- |
| ![List row light](../../Tests/DesignSystemTests/__Snapshots__/list-row-light.png) | ![List row dark](../../Tests/DesignSystemTests/__Snapshots__/list-row-dark.png) |

### Section Header

| Light | Dark |
| --- | --- |
| ![Section header light](../../Tests/DesignSystemTests/__Snapshots__/section-header-light.png) | ![Section header dark](../../Tests/DesignSystemTests/__Snapshots__/section-header-dark.png) |

### Banner

| Light | Dark |
| --- | --- |
| ![Banner light](../../Tests/DesignSystemTests/__Snapshots__/banner-light.png) | ![Banner dark](../../Tests/DesignSystemTests/__Snapshots__/banner-dark.png) |

## 4. API 速查

### Button

```swift
ElsepageButton(
    title: String,
    systemImage: String? = nil,
    role: .primary | .secondary | .destructive | .quiet,
    size: .regular | .compact,
    isLoading: Bool = false,
    isEnabled: Bool = true,
    isFullWidth: Bool = true,
    action: () -> Void
)
```

### Icon Button

```swift
ElsepageIconButton(
    systemName: String,
    accessibilityLabel: String,
    role: .surface | .plain | .filled | .destructive,
    isEnabled: Bool = true,
    isLoading: Bool = false,
    action: () -> Void
)
```

### List Row

```swift
ElsepageListRow(
    title: String,
    subtitle: String? = nil,
    metadata: String? = nil,
    systemImage: String? = nil,
    trailingText: String? = nil,
    showsChevron: Bool = false,
    isEnabled: Bool = true,
    action: (() -> Void)? = nil
)
```

### Section Header

```swift
ElsepageSectionHeader(
    title: String,
    count: Int? = nil,
    actionTitle: String? = nil,
    action: (() -> Void)? = nil
)
```

### Input

```swift
ElsepageInput(
    title: String,
    text: Binding<String>,
    prompt: String? = nil,
    helper: String? = nil,
    error: String? = nil,
    isSecure: Bool = false,
    isEnabled: Bool = true,
    textContentType: UITextContentType? = nil,
    keyboardType: UIKeyboardType = .default,
    autocapitalization: TextInputAutocapitalization = .sentences,
    disablesAutocorrection: Bool = false,
    submitLabel: SubmitLabel = .done,
    onSubmit: (() -> Void)? = nil
)
```

### Card

```swift
ElsepageCard(style: .surface | .secondary | .elevated | .plain, padding: CGFloat = 16) {
    content
}
```

### Empty / Loading / Error

```swift
ElsepageEmptyState(title:message:systemImage:actionTitle:action:)
ElsepageLoadingState(message:isFullScreen:)
ElsepageErrorState(title:message:retryTitle:retry:)
ElsepageInlineError(message:)
```

### Banner / Toast

```swift
ElsepageBanner(style:title:message:actionTitle:action:onDismiss:)
ElsepageToast(style:message:actionTitle:action:onDismiss:)
view.elsepageToast(isPresented:style:message:actionTitle:action:)
```

## 5. 状态约定

| 状态 | 视觉/行为 | 实现 |
| --- | --- | --- |
| Normal | 默认背景/前景 | token |
| Pressed | 0.86 opacity + 覆盖层 + 0.98 scale；Reduce Motion 取消 scale | `ButtonStyle` |
| Disabled | 0.38 opacity；禁用点击 | `.disabled` |
| Loading | 0.72 opacity；`ProgressView`；禁用点击 | `isLoading` |
| Error | danger 描边 + inline 文案；页面级 Error State | `error` / `ElsepageErrorState` |
| Focused | accent 1.5pt 描边 | `@FocusState` |
| Light/Dark | 由 `ElsepagePalette` 自动解析 | 动态 UIColor |

## 6. 文本长度与字体尺寸

- Button 标题可换行；目录包含长标题示例。
- List Row title/subtitle 各 2 行，metadata 1 行；目录包含长标题示例。
- Section Header 标题单行；count/action 保持尾部。
- Input 的 helper/error 使用 `fixedSize(horizontal: false, vertical: true)`，不会截断。
- 目录有 `Accessibility XL` 预览；组件本身不固定字号。
- 快照当前覆盖 Light/Dark；未逐一快照 AX 尺寸，AX 由预览人工验收。

## 7. 测试与参考图

| 测试 | 数量 | 内容 |
| --- | --- | --- |
| Token tests | 4 | 间距网格、触达尺寸、圆角单调、角色/状态枚举、阴影 alias |
| Snapshot tests | 8 | Buttons / List Row / Section Header / Banner × Light/Dark |

运行：

```sh
xcodebuild -project ReadLoop.xcodeproj -scheme ReadLoop \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -derivedDataPath /tmp/elsepage-native-build \
  -only-testing:DesignSystemTests test
```

快照更新流程见 [Design System Guide §5.1](04-design-system-guide.md)。

## 8. 不在目录内

- `NavigationStack`、`TabView`、`Sheet`、`Menu`、`NavigationLink`：使用系统组件，不重造。
- `SelectableText`、`AgentMarkdownText`、阅读器桥、语音组件：属于业务/平台组件，保持原实现。
- 现有页面的 `ElsepageRootHeader`、`ElsepageSearchField`、`ElsepageBookCover`：本轮不迁到新目录；后续按迁移指南评估。
- 成就 Toast、阅读器瞬时胶囊：有业务状态与撤销语义，暂不替换为通用 Toast。

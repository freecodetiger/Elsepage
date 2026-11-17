# ElsePage Design System Migration Guidelines

2026-11-15。本阶段**不批量重写业务页面**。这份指南定义下一阶段如何逐屏迁移，保证业务逻辑、导航、数据流不变。

## 1. 迁移原则

1. **一次一个屏幕**，一次一个 surface。
2. **只换表现，不换业务**：不碰 Model、Repository、ReaderAgent、Session、导航容器。
3. **系统组件优先**：`NavigationStack`、`TabView`、`Sheet`、`Menu`、`Button`、`TextField`、`List`、`ContentUnavailableView` 不重造。
4. **旧 token 可以共存**：`ElsepageTheme` 不删除；迁移完成前双轨运行。
5. **每次迁移有构建 + 预览 + 快照/截图**；不要一次提交多屏大改。

## 2. 迁移顺序建议

从低风险、可回滚的表面开始：

1. **按钮与图标按钮**：把 `buttonStyle(.borderedProminent)` / `.bordered` / 纯文字动作换成 `ElsepageButton` / `ElsepageIconButton` role。
2. **Section Header**：把页面里手写的 `Text(...).font(.title3.weight(.semibold))` 换成 `ElsepageSectionHeader`。
3. **List Row**：把重复的 HStack 行结构换成 `ElsepageListRow`，容器保留原 `ElsepageCard` / `List`。
4. **Input**：设置页/引导页的单个字段；保留 Form 的 Section 结构与保存流程。
5. **Empty / Loading / Error**：替换页面内重复的 `ContentUnavailableView` / `ProgressView` 组合。
6. **Banner / Toast**：只替换新的提示；阅读器瞬时胶囊、成就 Toast 保留业务实现。
7. **Tokens 收口**：最后清理页面里的字号/间距/颜色 magic numbers。

先从「我的」「想法」这类静态内容页开始；阅读器、设置、导入/语音等有 UIKit/业务状态的页面最后做。

## 3. 旧 token → 新 token 映射

| 旧 | 新 | 注意 |
| --- | --- | --- |
| `ElsepageTheme.Spacing.small` (10) | `ElsepageSpacing.sm` (8) | 数值会变；按新网格重新排版，不要机械替换 |
| `ElsepageTheme.Spacing.medium` (16) | `ElsepageSpacing.lg` (16) | 基本等价 |
| `ElsepageTheme.Spacing.large` (20) | `ElsepageSpacing.xl` (20) | 基本等价 |
| `ElsepageTheme.Spacing.xLarge` (28) | `ElsepageSpacing.xxxl` (32) | 建议按 8pt 网格取 32 |
| `ElsepageTheme.Spacing.page` (20) | `ElsepageSpacing.page` (16) | 三个根页面已经是 16；其它页面先确认设计规范 |
| `ElsepageTheme.Radius.small` (12) | `ElsepageRadius.md` / `.card` (12) | 等价 |
| `ElsepageTheme.Radius.large` (24) | `ElsepageRadius.xl` (24) | 等价 |
| `Color.elsepageTextPrimary` | `ElsepageColor.textPrimary` | 语义相同；新代码用新名 |
| `Color.elsepageSurface` | `ElsepageColor.surface` | 同上 |
| `ElsepageTheme.Typography.bookTitle` | `ElsepageFont.bookTitle` | 旧值是 `.title3` 22；新值 `.title2` 22 |
| `.buttonStyle(.borderedProminent)` | `ElsepageButton(role: .primary)` | 保留原 action / disabled / loading |
| `.buttonStyle(.bordered)` | `ElsepageButton(role: .secondary)` | 行内小按钮可用 `.compact` |
| 纯文字动作 | `ElsepageButton(role: .quiet, isFullWidth: false)` | 保留 44pt 触达 |
| 手写 section title | `ElsepageSectionHeader` | 保留 count/action |
| 手写 HStack 行 | `ElsepageListRow` | 不要给每行加 Card |
| 页面内 `ContentUnavailableView` | `ElsepageEmptyState` / `ElsepageErrorState` | 系统组件仍是底层；有统一 action 时再换 |

## 4. 单屏迁移步骤

以「想法」列表为例：

1. 只改 `ThoughtsView` 的表现层；不碰 `ThoughtsModel`、`ThoughtsArchiveProjection`、导航。
2. 顶部标题行保持现有 `ElsepageRootHeader`；不重做标题/胶囊。
3. 月份标题从 `archiveSection` 的 HStack 换成 `ElsepageSectionHeader(title:count:)`。
4. 记录行从手写 `VStack` 换成 `ElsepageListRow`：
   - title = summary（2 行）
   - subtitle = book/date（如果当前是 metadata，可放 metadata）
   - 不加 chevron 如果整行点击已有明确 affordance；需要时打开。
5. 空态换成 `ElsepageEmptyState`；保留现有文案。
6. 构建；在 Light/Dark/AX 预览检查；截图对比。
7. 再决定是否迁移下一屏。

### 示例：一个安全的行迁移

迁移前：

```swift
VStack(alignment: .leading, spacing: 4) {
    Text(book.title).font(.footnote.weight(.semibold))
    Text(date).font(.footnote)
    Text(summary).font(.headline).lineLimit(2)
}
.padding(.vertical, 16)
```

迁移后：

```swift
ElsepageListRow(
    title: summary,
    subtitle: book.title,
    metadata: date,
    action: open
)
```

业务 `entry`、`selectedEntry`、搜索/分组逻辑不变。

## 5. 不要做的事

- **不要**把 `NavigationStack` / `TabView` / `Sheet` 包成设计系统组件。
- **不要**为了“统一”给每一行加 `ElsepageCard`；卡片是成组容器。
- **不要**把系统 `List` 全部换成自绘 `ScrollView`；`List` 的分隔、滑动、无障碍是资产。
- **不要**用固定 `.system(size:)` 替换语义字体；Dynamic Type 会破。
- **不要**在组件内部读业务 Model 或执行网络/数据库。
- **不要**把 `SelectableText`、`AgentMarkdownText`、`ReadiumReaderView` 等平台桥接层改成设计系统组件。
- **不要**一次迁移多个根页面；难以定位回归。
- **不要**在迁移中改文案/信息架构；文案变更应单独评审。

## 6. 每屏验收清单

- [ ] 业务行为与迁移前一致：点击、返回、搜索、排序、删除、Sheet。
- [ ] Light / Dark 预览正常。
- [ ] Dynamic Type 至少检查 `.large` 与 `.accessibility3`。
- [ ] 触达 ≥44pt；无被遮挡的底部动作。
- [ ] 无新增 magic number（颜色/字号/间距/圆角）。
- [ ] 长标题、长书名、空内容、错误/加载状态都看过。
- [ ] 构建通过；相关测试通过。
- [ ] 截图/预览留档；提交信息只描述本屏迁移。

## 7. 依赖边界

```text
App/DesignSystem (tokens + components)
        ↓
App 页面 / Sheets
        ↓
App Models / Repositories / ReaderAgent / Readium / GRDB
```

- DesignSystem **不反向依赖**页面、Model、Repository。
- DesignSystem 只依赖 SwiftUI/UIKit 和 `Sources/AppInfrastructure` 的 `ElsepagePalette`（通过现有 `Color.elsepage*`）。
- 不新增第三方依赖；快照使用系统 `ImageRenderer`。
- 新测试 target `DesignSystemTests` 是 App-hosted unit test，不改变 App 依赖图。

## 8. 下一阶段建议

1. **样板屏**：选「我的」或「想法」做完整迁移，验证 tokens + row + header + empty/error 的组合。
2. **按钮收口**：把根页面/详情页的高频按钮统一到 role；保留业务 action。
3. **表单**：设置/引导的输入字段迁移到 `ElsepageInput`，但保留保存/测试/Keychain 流程。
4. **状态页**：把重复的 loading/error/empty 组合替换；启动错误页优先。
5. **设计系统版本化**：只加 token/组件，不轻易改既有 role 的视觉语义；变更走快照 + 记录。

迁移过程中如果发现业务页面需要新 token/组件，先加到设计系统并补目录/快照，再在页面使用；不要在页面里临时写死。

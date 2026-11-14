# 底部玻璃分体菜单

2026-11-14。用户要求把底部导航做成 T3 Code iOS 客户端那种“左边三 Tab 胶囊 + 右边圆形加号”的玻璃分体菜单，并做好兜底。本轮已落到 App；阅读器未改。

## 结构

- `TabView` 继续管三个页面的内容和选中状态；系统 tab bar 在三个 tab 根视图上隐藏。
- `safeAreaInset(edge: .bottom)` 放自定义底栏：左侧是 56pt 高的玻璃胶囊，三个图标按钮等分；右侧是 56pt 玻璃圆形加号；水平边距 16，底栏距安全区底部 8。
- 图标只显示图形（书架 / 灯泡 / 人像），不显示文字；名称保留在无障碍标签里。选中项有一枚 52×36 的胶囊底色，图标从次要色变为主要色。
- 加号是全局“导入 EPUB”：从任意 tab 点击会切到书架并打开文件选择器。`LibraryView` 增加 `importRequest` 绑定，复用现有导入流程。
- 内容通过 `safeAreaInset` 预留底栏高度，不被遮挡；底栏在 home indicator 之上。

## 兜底

| 条件 | 处理 |
| --- | --- |
| iOS 26 | `GlassEffectContainer` + `.glassEffect(.regular, in:)`；加号用 `.regular.interactive()` |
| iOS 18 | `.ultraThinMaterial` + 0.5pt 描边 + 柔和投影，同样 56pt 几何 |
| 减弱透明度 | 纯色 `elsepageSurface` + 描边，不再使用玻璃/材质 |
| 键盘 | `keyboardWillShow/Hide` 通知控制显隐；软键盘出现时底栏收起，与系统 tab bar 一致 |
| Dynamic Type / 无障碍 | 图标按钮带 `accessibilityLabel` 与 `.isSelected`；触达高度 56；不依赖文字缩放 |
| 深色模式 | 使用语义色、系统玻璃/材质；不写死颜色 |
| 阅读器 / 首启 / Sheet | 均为 fullScreenCover 或 sheet，根底栏不露出 |

## 与 T3 源码的关系 / 取舍

T3 Code 的 compact 底栏是原生 `UITabBar` + 一个 `UIButton.Configuration.glass()`；它在 `layoutSubviews` 里测量真实 tab 按钮的 union frame，过滤 iOS 26 玻璃放大镜的副本，再把 compose 放在右侧。我们采用同一种“左胶囊 + 右玻璃圆钮”的布局和同一套 iOS 26 glass API，但没有复制它对 `UITabBar` 私有子视图的测量：三个固定 tab 不需要这种脆弱的内省，SwiftUI 组合在 OS 更新时更稳。

代价是失去系统 tab bar 的选中玻璃透镜、滚动收起和双击回顶等行为。若必须与 T3 完全一致，可以再单独移植原生 `UITabBar` 版本。

## 验证

- `xcodebuild` Debug **BUILD SUCCEEDED**；安装到 iPhone 17 Pro（iOS 26.5）模拟器。
- 实际点过：三个 tab 切换、加号从“想法”切到书架并打开文件选择器、搜索框聚焦（模拟器使用硬件键盘，未出现软键盘）。
- 软键盘收起路径由键盘通知控制；未在真机软件键盘下复验。
- 当前没有 iOS 18 运行时，material 兜底只做了编译检查，未在 iOS 18 模拟器运行。
- 阅读器未改。

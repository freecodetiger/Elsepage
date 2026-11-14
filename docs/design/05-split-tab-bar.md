# 底部玻璃分体菜单

2026-11-14。用户要求把底部导航做成 T3 Code iOS 客户端那种“左边三 Tab 胶囊 + 右边圆形加号”的玻璃分体菜单，并做好兜底。本轮已落到 App；阅读器未改。

## 结构

- iOS 26 使用**原生 `UITabBar`**（系统玻璃 + 选中透镜）加一个 **`UIButton.Configuration.glass()`** 的圆形加号，和 T3 Code 的 compact 底栏同一套实现。系统 tab bar 在三个 tab 根视图上隐藏。
- `safeAreaInset(edge: .bottom)` 放这条原生分体栏；胶囊与加号在安全区之上。
- tab 项只有图标（书架 / 灯泡 / 人像），不显示文字；名称在无障碍标签里。选中态由系统 UITabBar 自己画。
- 加号只在**书架**（第一个 tab）出现；在想法/我的隐藏。加号隐藏时，tab bar 的 trailing 预留与位置不变，所以玻璃胶囊的 frame 不移动。
- 加号是全局“导入 EPUB”：点击打开现有文件选择器。入口只在书架，和 T3 的 compose 只在 threads 一致。

## 兜底

| 条件 | 处理 |
| --- | --- |
| iOS 26 | 原生 UITabBar 玻璃 + `UIButton.Configuration.glass()` 加号 |
| iOS 18 | 同几何的 SwiftUI 材质胶囊 + 材质圆形加号；加号隐藏时用等宽透明占位，胶囊不移动 |
| 减弱透明度 | 材质版改为纯色 surface + 描边；原生玻璃由系统处理 |
| 键盘 | `keyboardWillShow/Hide` 通知控制显隐；软键盘出现时底栏收起 |
| 无障碍 | tab 项带名称；加号有 `accessibilityLabel` 并覆写 `accessibilityActivate`；触达 44pt 以上 |
| 深色模式 | 原生 UITabBar/glass 与语义色；不写死颜色 |
| 阅读器 / 首启 / Sheet | fullScreenCover 或 sheet，根底栏不露出 |

## 与 T3 源码的关系

T3 Code 的 compact 底栏在 `T3SidebarTabBarView.swift` 里用 `UITabBar` + `UIButton`；`WorkspaceTabBar.layoutSubviews` 找出真实 tab 按钮的 union frame（过滤 iOS 26 玻璃放大镜副本），把 compose 放到 `row.maxX + 16`，大小 `row.height + 8`；tab bar 的 trailing 留出 64pt。Elsepage 采用了同一套布局和测量方式。

代价：依赖 UIKit 私有子视图结构来定位加号，OS 更新可能改变；iOS 18 没有系统玻璃，改用同几何的材质版本。原生 tab bar 的滚动收起、双击回顶等系统行为保留；自绘材质版本不具备。

## 验证

- `xcodebuild` Debug **BUILD SUCCEEDED**；安装到 iPhone 17 Pro（iOS 26.5）模拟器。
- 系统 tab bar 已隐藏；原生分体栏显示玻璃胶囊 + 玻璃加号。
- 实测 tab bar frame 在书架与想法上完全一致：`x=8, y=749, width=318, height=83`；加号只在书架存在，切到想法/我的后消失，玻璃位置不变。
- 加号点击实测打开文件选择器（未被导入文件）。
- 软键盘收起路径由键盘通知控制；模拟器使用硬件键盘，未在软件键盘下复验。
- 当前没有 iOS 18 运行时，材质兜底只做了编译检查，未在 iOS 18 模拟器运行。
- 阅读器未改。

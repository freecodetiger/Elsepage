# 界面原型与视觉探索

这里的 HTML 用于设计探索，不参与 Swift 或 Xcode 构建，也不是当前产品规格。可以直接用浏览器打开。

## 当前探索

- [书架原生收敛](elsepage-native-refinement.html)：方案 1 的系统组件版。系统 Large Title、`.searchable`、三列网格、16pt 页边距；两帧只区分默认与有未写想法，补写胶囊用 overlay 不参与布局，静态无 JS。取舍与 SwiftUI 映射见 [原生收敛说明](../design/03-native-refinement.md)。尚未实现。

- [其他页面原生收敛](elsepage-native-screens.html)：想法 / 我的 / 阅读三页；抽出一套 8 个组件的小组件库，我的改为分区表面容器，阅读页放大正文并加入引文与高亮组件。取舍与 SwiftUI 映射见 [原生组件与密度](../design/04-native-screens.md)。尚未实现。

- [字号与版式三方案](elsepage-layout-studies.html)：用户对 A 的字号与空间比例提出反馈后的新探索；1原生大字/2编辑目录/3封面主导，同一组内容、完整手机尺寸对比。重点重建字级、对齐、间距和封面占比。[方案取舍](../design/02-typography-layout-options.md)。用户已选择方案 1，收敛结果见 [书架原生收敛](elsepage-native-refinement.html)。

- [现代 UI 原型 v0](elsepage-modern-prototype.html)：2026-11-14 用户授权制作；A纸间/B清晰/C夜航三种结构可切换，覆盖书架、阅读、批注、Reflection、想法和我的演示路径。单文件、离线、仅内存演示数据。设计取舍与验证范围见 [原型说明](../design/01-visual-prototype.md)。尚未选定方向，不能当成已实现App截图或正式规格。

## 历史探索

- [Calm iOS v3](elsepage-calm-ios-v3.html)：早期整体界面原型，原位于仓库根目录 `elsepage_calm_ios_v3.html`。
- [Thoughts editorial](thoughts-editorial.html)：Thoughts 界面探索。
- [Thoughts redesign](thoughts-redesign.html)：Thoughts 界面探索。

开发时以 [PRD](../../ReadLoop_PRD.md)、对应 Feature Spec 和当前代码为依据。原型与实现不一致时，不据此恢复旧功能。

# Quick Task 260914-x0a: 修复 Reader 返回书架封面闪烁

## 症状

从 Reader 返回书架时，桌面上的当前书会短暂改变尺寸，并在动画尾部突然出现阴影。

## 诊断

- 当前书架源视图使用 `ElsepageBookCover`，其真实 frame 为 `100 × 150pt`。
- `ElsepageBookCover` 默认在 view bounds 之外绘制阴影。
- `matchedTransitionSource` 默认按 view bounds 截取 zoom snapshot，因此返回动画的 snapshot 与实际源视图不一致：阴影可能在 transition 结束后才出现，视觉上像书籍尺寸突然变化。
- Reader 准备态使用 `156 × 234pt` 且带阴影的封面，放大了两端不一致。

## 修复

1. 为 `ElsepageBookCover` 增加可控 `showsShadow`，默认保持当前行为。
2. 书架桌面封面关闭组件阴影，使匹配源严格等于 `100 × 150pt` 封面 frame。
3. Reader 准备态使用相同封面尺寸并关闭阴影，保证两端对象一致。
4. 为 transition source 明确裁切为与封面一致的圆角矩形。
5. 保留其他封面模式与应用位置的阴影行为。

## 验证

- Swift parse、diff check、swift test。
- 由于这是 SwiftUI/UIKit 转场渲染问题，包测试无法捕获实际动画；需要用户完成 Xcode 真机返回动画验收。

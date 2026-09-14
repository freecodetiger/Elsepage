# Quick Task 260914-x2m: 恢复封面层次并稳定返回阴影

## 目标

恢复封面阴影带来的层次感，同时避免 Reader 返回书架时阴影在动画尾部才出现。

## 根因

前一版通过关闭真实视图阴影来消除返回闪烁，但 zoom 的 matched source snapshot 与实际源视图都失去了阴影，导致封面显得扁平和悬浮，缺少层次。

## 修复

1. 将封面尺寸、圆角和阴影参数集中到 `ElsepageBookCoverMetrics`。
2. 桌面封面恢复真实阴影，并把完全相同参数写入 `matchedTransitionSource` configuration。
3. Reader 准备态沿用同一封面几何和阴影参数。
4. 书脊模式、封面模式同步把各自真实阴影写入 transition configuration。
5. 保持 transition snapshot 与真实视图的 clip shape、阴影色、半径和偏移一致。

## 验证

- Swift parse、diff check、swift test。
- SwiftUI zoom 阴影属于真机渲染行为，需要 Xcode 构建后验证打开与返回两个方向。

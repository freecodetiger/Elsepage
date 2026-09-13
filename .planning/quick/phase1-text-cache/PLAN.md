# Phase 1 A：文本测量与富文本缓存

目标：在会话/档案正文的现有 UIKit 选区桥上加入统一 `MessageText` 门面、`RichTextBuilder` 解析/样式缓存和 `TextMeasureCache` 宽度桶 LRU。

约束：保持文本、citation 点击、Dynamic Type 和选区行为；不改键盘、长按手势、流式节流或阅读器打开管线。缓存只在主 actor 使用，容量有界；编辑框与普通短文继续走原路径。

验收：`swift test` 全绿；用户 Xcode 构建；真机通过 `/perf` 比较 `textMeasureCache` 命中/未命中与 `textMeasure` 次数，确认缓存命中不改变最终文本和高度。

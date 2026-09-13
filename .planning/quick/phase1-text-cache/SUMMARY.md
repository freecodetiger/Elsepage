# Phase 1 A：文本测量与富文本缓存

已完成代码：新增统一 `MessageText` 门面；`RichTextBuilder` 缓存 Markdown 结构解析和样式落字；`TextMeasureCache` 使用富文本指纹 + 8pt 宽度桶的 200 项主 actor LRU；`FitTextView` 只在缓存未命中时执行 boundingRect，并保留实例 memo 与选区行为；旧 `AgentMarkdownText`/`SelectableTextBody` 保留为薄壳。

已验证：`swift test` 349 个 Swift 测试通过，26 个 XCTest 通过；`git diff --check` 通过。

待验证：App target 的 Xcode 编译、真机视觉等价和 `/perf` 命中率/测量次数对照。用户按项目约定执行构建与真机验收后，才能把 Phase 1 标为完成。

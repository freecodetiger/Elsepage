# Agent Markdown v3 渲染完成

## 已完成

- `makeSelectableMarkdown` 支持 Foundation block intent：
  - 标题
  - 无序列表
  - 有序列表
  - 引用块
  - 分隔线
  - 代码块
  - 段落间距与行距
- Citation 在 Reader Help 中改为上标 `¹²`。
- Reader Help 底部按实际使用顺序生成来源列表。
- 来源标签点击后保持 thread，并跳回原文。
- 回答卡片去掉厚重背景，复制/保存按钮降为低权重操作。
- Reader Help Prompt 升级为 `reader-help-v3`：
  - 结论先行
  - 复杂问题允许更长回答
  - 支持结构化 Markdown
  - 禁止表格、HTML 和装饰性代码围栏
- Reader Help 输出预算提升到 1,200 tokens / 45 秒。

## 验证

- iOS SDK `typecheck`：`SelectableText.swift` 通过。
- App Markdown 文件纯语法解析通过。
- `swift test`：383 tests 全绿。
- `Package.resolved` 已恢复。

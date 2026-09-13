# Note 重叠命中与预览/编辑双态完成

## 已完成

- 独立 Note 与 Highlight 重叠时统一显示“笔记 / 高亮”二次选择器。
- 选择后分别打开 Note editor 或 Highlight menu。
- Note underline 的非重叠区域仍直接打开对应 Note。
- Note editor 默认进入 Markdown 预览态，不自动弹出键盘。
- 增加“预览 / 编辑”分段控件。
- 预览使用 `AgentMarkdownText`，支持已有块级 Markdown 渲染。
- 编辑态继续使用原有 TextEditor、自动保存和空内容删除逻辑。
- Reader Help 保存为 Note 时移除内部 citation marker。

## 验证

- App Reader 文件纯语法解析通过。
- `swift test`：383 tests 全绿。
- 真机需验证重叠区域先出现 Highlight 菜单、菜单中的“笔记”可打开重叠 Note，以及非重叠 underline 直接打开 Note。

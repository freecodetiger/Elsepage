# Note 重叠命中与预览/编辑双态完成

## 已完成

- 调整 Readium decoration group 创建顺序，notes 优先于 highlights。
- 当 Note underline 与 Highlight 重叠时，点击优先打开对应的 Note。
- Note editor 默认进入 Markdown 预览态，不自动弹出键盘。
- 增加“预览 / 编辑”分段控件。
- 预览使用 `AgentMarkdownText`，支持已有块级 Markdown 渲染。
- 编辑态继续使用原有 TextEditor、自动保存和空内容删除逻辑。
- Reader Help 保存为 Note 时移除内部 citation marker。

## 验证

- App Reader 文件纯语法解析通过。
- `swift test`：383 tests 全绿。
- 真机需验证重叠点击优先 Note、默认预览、切换编辑和保存。

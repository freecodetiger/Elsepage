# Quick Task: Note 重叠命中与预览编辑双态

## Goal

解决 Note underline 与 Highlight 重叠时无法优先打开笔记的问题，并让 Note editor 默认显示 Markdown 预览，按需进入编辑态。

## Scope

- notes decoration 优先于 highlights 参与命中。
- Note editor 默认 preview，不自动弹出键盘。
- 增加预览/编辑分段控件。
- 预览使用 AgentMarkdownText 渲染。
- 编辑态保留原 TextEditor 与 live-save。
- 保存 Reader Help 回答为 Note 时移除内部 citation marker。
- 不改变 Note 持久化模型。

## Verification

- App Reader 文件语法解析通过。
- `swift test` 全绿。
- 真机验证重叠点击进入 Note、默认预览、切换编辑、保存和退出。

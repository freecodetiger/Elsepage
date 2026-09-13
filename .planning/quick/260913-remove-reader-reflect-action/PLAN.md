# Quick Task: 删除选区工具栏“聊聊”

## Goal

删除 EPUB 选区工具栏中的“聊聊”按钮，减少与“问 Agent”重复的入口，不改变其他标注和会话结束后的 Reflection 流程。

## Scope

- 从 SelectionToolbar 删除 onReflect 参数和按钮。
- 从 ReaderAnnotationOverlays 移除对应回调。
- 不改 Highlight 菜单、Note、Copy、问 Agent。
- 不改 Reflection 数据模型和 Session Ending UI。

## Verification

- App Reader 文件语法解析通过。
- `swift test` 全绿。

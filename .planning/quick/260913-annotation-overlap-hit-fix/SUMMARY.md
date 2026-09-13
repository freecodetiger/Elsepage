# 跨 Range Note / Highlight 命中修复完成

## 根因

`handleHighlightActivation` 只检查了同一个 TextAnnotation 上的 Note，没有扫描其他 TextAnnotation 中与该 Highlight 重叠的 Note。

因此当下划线完整包含高亮时：

- 点击下划线：Note 路径发现重叠 Highlight，显示选择器。
- 点击高亮：Highlight 路径没有发现不同 Range 的 Note，直接显示高亮菜单。

## 修复

- Highlight activation 增加跨 Annotation Note overlap 扫描。
- 命中最新的重叠 Note 并显示“高亮 / 笔记”选择器。
- 保留无冲突时直接打开高亮菜单。
- 增加诊断日志：
  - `highlight.activate ... ownNotes ... conflictNote`
  - `note.activate ... conflictHighlight`
- 增加精确 Range containment 测试。

## 验证

- `swift test`：388 tests 全绿。
- App Reader 文件纯语法解析通过。

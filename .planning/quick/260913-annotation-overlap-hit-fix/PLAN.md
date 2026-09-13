# Quick Task: 修复跨 Range Note 与 Highlight 命中

## Goal

当 Note 下划线完整包含另一个 Highlight 时，点击高亮区域也必须进入“高亮 / 笔记”选择器，而不是直接打开高亮菜单。

## Scope

- Highlight activation 扫描所有跨 Annotation 的 Note 重叠。
- Note activation 保持现有跨 Annotation Highlight 扫描。
- 冲突 candidate 增加 AnnotationLog 诊断。
- 无重叠时保持直接打开行为。
- 不改变持久化模型。

## Verification

- 增加 AnnotationRange containment 测试。
- `swift test` 全绿。
- App 文件语法解析通过。

# Quick Task: Note / Highlight 重叠二次选择器

## Goal

当独立 Note 与 Highlight 在文本范围上重叠时，不依赖 Readium decoration group 顺序，而是统一显示“笔记 / 高亮”选择器；无冲突时保持原有直接交互。

## Scope

- 新增 annotation conflict menu 状态。
- Highlight 或 Note decoration 被点击时检测另一方是否重叠。
- 冲突时显示二次选择器。
- 选择“笔记”打开 Note editor。
- 选择“高亮”打开 Highlight menu。
- 无冲突时保持 Note 直接打开、Highlight 直接打开。
- 复用现有保守 locator overlap 判断。

## Verification

- Locator overlap 测试保持通过。
- App Reader 文件语法解析通过。
- `swift test` 全绿。
- 真机验证只在一方真正重叠时出现选择器。

# Note / Highlight 重叠二次选择器完成

## 已完成

- 新增 `ReaderAnnotationConflict` 和 conflict menu 状态。
- Highlight 或 Note 被点击时都会检查是否存在独立的另一方重叠。
- 只有真实冲突时显示“笔记 / 高亮”二次选择器。
- 选择“笔记”打开对应 Note editor。
- 选择“高亮”打开对应 Highlight menu。
- 无冲突时保持原有直接行为。
- 保留保守 locator overlap 判断，避免误触发选择器。

## 验证

- App Reader 文件纯语法解析通过。
- `swift test`：384 tests 全绿。
- 真机需验证重叠点击出现选择器、两个选项均打开对应对象。

# Reader Help 保存笔记的正文视觉反馈完成

## 已完成

- Readium 增加独立 `notes` decoration group。
- 无 Highlight 的 Note 使用轻量 underline decoration。
- 已有 Highlight 的 Note 不重复添加下划线。
- 点击正文中的 note underline 可打开对应 Note editor。
- `ReaderScreen` 将 notes snapshot 传入 Readium view，保存后立即重放 decoration。

## 验证

- App Reader 文件纯语法解析通过。
- `swift test`：383 tests 全绿。
- 真机需验证下划线颜色、点击打开和 dark/sepia 主题可读性。

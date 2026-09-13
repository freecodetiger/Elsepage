# Annotation 点击坐标冲突消歧完成

## 根因

之前只要 Note 的整个 Range 与 Highlight 重叠，点击 Note 的任何位置都会进入选择器；点击 Highlight 也只检查同一 Annotation。

实际命中必须基于用户点击的 DOM 坐标，而不是整个 Range 是否有任意交集。

## 修复

- 在 Readium webview 中缓存最近一次 click/pointerup 的 client coordinate。
- decoration 激活时使用 `clickableElements` 的真实 hit rect 查询同一点实际命中的 notes/highlights。
- 回传并记录点击坐标、命中 group 和 decoration IDs。
- 冲突菜单锚点从整条 decoration 的 bounding rect 改为实际点击 point。
- Note 点击：
  - 只有该点同时命中 Highlight 时才显示选择器。
  - 未命中 Highlight 时直接打开 Note。
- Highlight 点击：
  - 只有该点同时命中 Note 时才显示选择器。
  - 未命中 Note 时直接显示高亮菜单。
- JS 查询失败时回退到保守 Range 判断。
- 增加诊断日志：
  - `highlight.hit ... overlapNotes`
  - `note.hit ... overlapHighlights`

## 验证

- App Reader 文件纯语法解析通过。
- `swift test`：388 tests 全绿。

# Annotation Model Refactor 落地完成

## 已完成

- 新增 AnnotationRange、TextAnnotation、HighlightLayer、NoteEntry。
- 新增 v28 迁移和 TextAnnotationRepository。
- Highlight 和 Note 彻底解耦，高亮不再拥有笔记附属语义。
- 同一 Range 聚合为 TextAnnotation，不同 Range 保持不同对象。
- NoteEntry 支持数组追加和单条编辑/删除。
- 高亮交叉创建被拒绝并显示温柔提示。
- 历史交叉高亮按较新者保留。
- 新写入镜像旧表，保证现有 Session / Journal / Export / Stats 兼容。
- Readium 每个 Note Range 只渲染一次 underline。
- 同 Range Highlight + Note 点击时显示“高亮 / 笔记”选择器。

## 验证

- `swift test`：387 tests 全绿。
- TextAnnotation roundtrip、迁移和交叉高亮测试通过。
- App Reader 文件纯语法解析通过。
- Package.resolved 已恢复。

## 待用户验收

- App target xcodebuild。
- `docs/testing/annotations/2026-09-13-annotation-model-refactor-checklist.md`。

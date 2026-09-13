# Annotation Model Refactor Spec 完成

## 已完成

- 新增 `docs/ANNOTATION_MODEL_SPEC.md`。
- 明确 Range 是唯一身份，HighlightLayer 与 NoteLayer 是同一 TextAnnotation 的独立层。
- 定义同 Range 合并、不同 Range 分对象、高亮禁止交叉等规则。
- 给出 `textAnnotations` 聚合表、兼容迁移和旧数据保护方案。
- 定义创建、编辑、删除、点击和冲突处理规则。
- 列出 5 个需要用户拍板的关键决策。

## 未包含

- 未修改 Swift 源码。
- 未新增数据库迁移。
- 未执行真机验收。

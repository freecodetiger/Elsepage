# Annotation Model Refactor Spec 完成

## 已完成

- 新增 `docs/ANNOTATION_MODEL_SPEC.md`。
- 明确 Range 是唯一身份，HighlightLayer 与 NoteLayer 是同一 TextAnnotation 的独立层。
- 定义同 Range 合并、不同 Range 分对象、高亮禁止交叉等规则。
- 给出 `textAnnotations` 聚合表、兼容迁移和旧数据保护方案。
- 定义创建、编辑、删除、点击和冲突处理规则。
- 已锁定 5 个关键决策：
  - Note 允许交叉；
  - 高亮不再拥有笔记附属语义；
  - 交叉高亮拒绝并温柔提示；
  - 同一 Range 使用 NoteEntry 数组；
  - 旧交叉高亮保留较新者。

## 未包含

- 未修改 Swift 源码。
- 未新增数据库迁移。
- 未执行真机验收。

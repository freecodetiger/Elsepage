# Quick Task: Annotation Model Refactor Spec

## Goal

制定中文规格，重构高亮与笔记的领域语义：以文本 Range 为唯一身份，高亮和笔记成为同一标注对象上的独立视觉层，并约束高亮不能交叉。

## Deliverables

- `docs/ANNOTATION_MODEL_SPEC.md`
- 当前模型问题与目标语义
- Range / TextAnnotation / HighlightLayer / NoteLayer 领域模型
- 创建、编辑、删除、命中和冲突规则
- 数据库迁移策略
- 测试与实施阶段
- 明确列出待用户决策的问题

## Constraints

- 本轮只写 spec，不改代码。
- 不删除或破坏历史高亮/笔记数据。
- 保留 Reader Help、Reflection、Export 和 Wipe 的兼容性。
- 高亮禁止交叉；笔记是否允许交叉列为待决问题。

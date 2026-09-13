# Quick Task: Reader Help 保存笔记反馈

## Goal

让“存为笔记”在保存中、保存成功和失败时都有明确可见的反馈，避免用户误以为没有反应。

## Scope

- 增加保存中状态。
- 保存成功后显示“已保存为笔记”确认。
- 保留按钮的“已保存”状态。
- 保存失败继续显示错误。
- 不改变 Note 持久化模型和保存内容。

## Verification

- Reader Help App 文件语法解析通过。
- `swift test` 全绿。

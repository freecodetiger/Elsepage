# Quick Task: Reader Help 关闭语义与回答边界修正

## Goal

修复 Reader Help 下滑误关闭导致问答无法找回的问题，并解除“本地 RAG 没有证据就不能回答现实背景”的过度约束。

## Scope

- Sheet 禁止交互式下滑关闭。
- 右上角 X 成为唯一取消并完全丢弃当前 help thread 的入口。
- Citation 跳转等程序化 dismiss 不丢弃 thread。
- Reader Help Prompt 区分书内证据、现实背景和通识解释。
- 用户明确询问现实事实时，允许提供简洁外部背景，不要求本地 RAG 存在。
- 保留反剧透边界和书内原文引用约束。
- 不引入 WebSearch。

## Verification

- Reader Help Prompt / policy 测试更新。
- `swift test` 全绿。
- App 文件语法解析通过。
- 真机验证下滑不能关闭、X 可完全丢弃、现实背景问题不再机械拒答。

# Quick Task: Reader Help Citation 返回体验

## Goal

修复点击 Reader Help 的 citation 后面板关闭、用户无法找回 Agent 回答的问题，并把内部 evidence marker 转成用户可理解的来源标签。

## Scope

- 点击 citation 不 dismiss help sheet。
- citation 跳回原文时，将 sheet 收起到 compact detent，保留 thread 和回答。
- 可见 citation 标签从 `E1/E2` 改为“原文”“书中”“过去”。
- 内部 evidence 标记和引用校验协议保持不变。
- 不改变 Reflection Agent 的持久化或 citation 数据模型。

## Verification

- App 文件语法解析通过。
- `swift test` 全绿，确认底层 citation 合同没有回归。
- 真机验证：点击“原文”后看到原位置，面板仍可重新展开且回答仍在。

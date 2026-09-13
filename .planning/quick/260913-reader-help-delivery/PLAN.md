# Quick Task: Reader Help 可交付实现

## Goal

按照 `docs/READER_HELP_SPEC.md` 落地 Reader Help：选中文字后主动提问，单次模型调用，基于当前书籍 read-so-far 上下文和 CARC 边界流式回答；默认不持久化，可显式保存为 Note。

## Deliverables

- ReaderAgent 新增 Reader Help domain、policy 和 service。
- Service 复用 `AgentExecutor`、`ReaderAgentContextBuilder`、`ContextAssembler`、`AgentCitationValidator`。
- Reader UI 增加“问”入口、轻量 help sheet、流式回答、有限追问、复制和保存 Note。
- 普通问答不创建 Reflection、Brain、Memory、Achievement 或 routing trace。
- 自动化测试覆盖校验、流式事件、运行时错误、取消、空回答、检索与 CARC 接缝。
- Spec 中的 v1 不变量有测试或代码级证据。

## Commit Order

1. `feat(agent): add ephemeral reader help service`
2. `test(agent): cover reader help runtime and boundaries`
3. `feat(reader): add in-reader agent help sheet`
4. `docs(reader-help): record delivery verification`

## Verification

- `swift test` 全绿。
- `git diff --check` 通过。
- App target 构建与真机手势验收由用户执行。
- 若 `swift test` 改写 `Package.resolved`，提交前恢复。

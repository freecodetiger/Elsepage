# Quick Task: Reader Help 临时选句答疑 Spec

## Goal

形成一份可实施的中文规格，定义阅读器内“选中一句话，临时问 Agent”的产品行为、低耦合架构、上下文边界、隐私策略与验收标准，尽量复用现有 Agent Runtime，同时不把临时答疑耦合到 Reflection 持久化流程。

## Deliverables

- `docs/READER_HELP_SPEC.md`
- 明确复用边界：`AgentRuntime`、`ReaderAgentContextBuilder`、`ContextAssembler`、`AgentCitationValidator`
- 明确不复用边界：`ReaderAgent.respond(to:)`、`SessionReflectionSheet`、Reflection/Brain 持久化链路
- 明确 v1 的交互、状态机、上下文预算、错误处理、隐私、观测和测试门禁
- 给出分阶段实施顺序与不变量

## Constraints

- 用户主动触发，不自动解释或弹窗。
- 默认临时，不新增数据库表，不写入 Journal、Memory、Brain、成就。
- 仅使用当前书籍与 read-so-far 上下文；v1 不调用过去 Reflection 或 Brain。
- 严格复用 CARC 防剧透策略。
- 单次回复模型调用；确定性规划，不运行 Reflection 的 LLM routing。
- 首版文本输入，不增加录音和音频生命周期。

## Verification

- `git diff --check` 通过。
- Spec 覆盖产品、架构、数据、隐私、测试和验收。
- 文档中的现有代码引用与仓库实现一致。
- 本次只改文档，不要求运行 `swift test`。

## Commit

- `docs(reader-help): specify in-reader quick answer`

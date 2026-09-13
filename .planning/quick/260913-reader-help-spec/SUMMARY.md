# Reader Help Spec 完成

## 已完成

- 从 `origin/main` 新建分支 `codex/reader-help-spec`。
- 新增中文规格 `docs/READER_HELP_SPEC.md`。
- 定义 Reader Help 与 Reflection Agent 的产品及技术边界。
- 锁定 v1 不变量：显式选句触发、默认临时、每轮一次回复模型、仅书籍已读上下文、CARC 防剧透、显式存 Note 才持久化。
- 明确复用 `AgentRuntime`、`ReaderAgentContextBuilder`、`ContextAssembler`、`AgentCitationValidator`，不复用 Reflection 持久化业务壳。
- 覆盖交互、领域契约、Pipeline、上下文预算、状态机、隐私、观测、测试、真机验收和分阶段实施。

## 未包含

- 未修改 Swift 源码。
- 未新增数据库迁移。
- 未接入 Reader UI。
- 本次只改文档，未运行 `swift test`。

## 验证

- `git diff --check` 通过。
- Spec 核心文件与现有仓库路径一致。
- 关键预算和状态机检查已完成。

## 下一步

1. 评审并确认 Spec。
2. 按 Phase 1–3 实施 service、policy、UI 和测试。
3. 用户执行真机验收清单。

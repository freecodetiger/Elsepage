# Anti-Spoiler CARC 实现完成

## 已完成

- 新增 `ResolvedReadingBoundary`、`ReadAccessDecision` 与 `ReadingBoundary` 兼容别名。
- Repository 解析 active retrieval child，并执行 `start < cursor < end` 规则。
- lexical SQL 粗筛 + Swift 最终 policy 双重过滤。
- semantic、rerank、small-to-big 共享同一 policy。
- active child 完整保留；后续 child 永远拒绝。
- 无 progression / active 解析不确定时 fail-closed。
- `textAfter` 不再进入 Agent nearby context 或 session locator summary。
- citation validation 有本地 index 时强制要求 resolved boundary。
- expander 失败路径仍执行 boundary policy。

## 验证

- `swift test`：373 tests 全部通过。
- 新增：
  - cursor 3.5 放行 active child
  - cursor 精确边界不放行下一 child
  - 缺失 progression fail-closed
  - active child 完整保留、后续 sibling 排除
  - nearby 不携带 `textAfter`
  - expander 对 denied anchor fail-closed

## 文档

- `docs/ANTI_SPOILER_SPEC.md` 已更新为 Implemented。

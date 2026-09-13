# Quick Task: Anti-Spoiler Complete Active Retrieval Chunk

## Goal

把 read-so-far 从“按 progression 精确截断”升级为“允许补全当前位置所在的 retrieval child，但绝不进入后续 child”。

## Scope

- 解析 current Locator 所在的 active retrieval child。
- lexical、semantic、small-to-big、nearby、citation 使用同一读取策略。
- 无 progression、active child 无法解析或路径降级时 fail-closed。
- 不使用不可靠的 `locator.textAfter` 送入模型。
- 新增 active child、精确边界、缺失 progression 和 expander fallback 测试。

## Verification

- `swift test` 全绿。
- `git diff --check` 通过。

# Quick Task: 客户端交互性能闭环验收与提交

## 目标

在真机验收完成后，清理明确无关的本地文件，保留不可再生研究材料但排除出产品提交，并提交客户端交互性能闭环。

## 范围

- 验证 A/C/D/E-P2 的真机结果，记录 B 在当前非流式 Provider 下的边界。
- 保存脱敏性能证据与已解决调试记录。
- 不提交本地 `research/` 草稿。
- 不执行 Xcode 构建、模拟器或 TestFlight。

## 验证

- `swift test`：353 tests 全部通过。
- `python3 -m unittest discover -s Scripts -p 'test_debug_loop.py'`：5 tests 通过。
- `git diff --check` 与新增 JSON 解析通过。

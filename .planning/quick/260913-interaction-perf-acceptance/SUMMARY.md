# 客户端交互性能闭环验收与提交

## 完成

- A：文本测量缓存真机通过；键盘和选区未新增 miss，后续看到 2 次 hit。
- B：确认当前 Provider 按 PRD §21.3 固定非流式，只产生一个完整 `.textDelta`；保留缓冲作为 v2 SSE 防线。
- C：阅读器复开命中 Publication 缓存，`readerOpen` 从 766.4ms 降至 470.4ms。
- D：移除键盘动画结束后晚到的强制滚动，修复会话回落；composer 与两处自动聚焦 sheet 通过。
- E-P2：普通冷启动无白屏或持续冻结，进入主界面可交互。

## 清理与证据

- 删除无关的 `freecodetiger.github.io/` 本地仓库副本。
- 删除空的 `ReadLoop.xcodeproj/project.xcworkspace/xcshareddata` 生成目录。
- `research/` 保留在本地，通过 `.git/info/exclude` 排除出产品提交。
- 脱敏验收记录：`docs/testing/interaction-perf/2026-09-13-interaction-acceptance.json`。
- 已解决调试记录：`.planning/debug/resolved/interaction-latency.md`。

## 验证

- `swift test`：353 tests 全部通过。
- Python DEBUG 执行器测试：5 tests 全部通过。
- `git diff --check`：通过。
- 验收 JSON：解析通过。

## 残余

- F/R3 的定量 CPU 归因尚未闭合，不阻塞当前 A/C/D/E-P2 验收。

# 工作包 C：阅读器打开管线

已完成：

- `ReaderModel.prepare()` 以并行 position/preferences 作为首帧门闩；highlights、notes 查询及 `markOpened` 移到 navigator 挂载后处理。
- `ReadiumServices` 增加 4 项 LRU Publication 缓存，键包含规范化路径、文件大小、修改时间和 `allowUserInteraction`，避免受保护资源的交互权限语义串用。
- Reader 准备阶段提前预热 Publication；同一文件的并发 `open` 会合并到一个进行中的解析任务，避免重复 retrieve/parse。
- `LibraryModel.delete` 在删除文件后主动失效对应 Publication 缓存。
- 诊断时间线记录 Publication 缓存命中与写入。
- `ReadiumPublicationIntegrationTests` 增加未变更文件复用与主动失效回归用例。

验证：

- `swift test`：352 个测试通过。
- `git diff --check`：通过。

待用户验收：

- Xcode Build & Install 真机版本。
- 冷开和复开同一本书，检查首帧、恢复位置、字号/主题、highlights 和 notes。
- 在「路由诊断」比较 `readerParse`、`readerToFirstPage`、`readerOpen`；复开时应看到 `reader.publicationCache.hit`。

已采样（2026-09-12）：复开日志出现 `reader.publicationCache.hit`；`readerOpen` 从 2225.7ms 降至 728.1ms，`readerParse` 从 18.1ms 降至 0.7ms，`Navigator→首帧` 从 2125.9ms 降至 674.5ms。证据见 `docs/testing/interaction-perf/2026-09-12-reader-reopen.json`；视觉语义尚未由日志证明。

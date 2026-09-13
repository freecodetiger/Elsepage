# 工作包 C：阅读器打开管线

目标：缩短点书到首个 `locationDidChange` 的关键路径，保留恢复位置、阅读偏好、章节、标注和现有生命周期语义。

范围：

- 将 `ReaderModel.prepare()` 的独立数据库读取并行化。
- 将 `markOpened` 从首帧门闩移到准备任务末尾，不让书架排序写入阻塞 navigator 挂载。
- 在 `ReadiumServices` 增加受控的进程内 Publication 缓存和并发打开合并，复开同一文件时复用解析结果，Reader 准备阶段提前预热；文件变更时自动失效。
- 保持取消、错误、首次打开和外部跳转行为；不改 Readium navigator 渲染内核。

验证出口：

1. 新增纯包级测试覆盖 Publication 缓存键的文件指纹与并行准备的结果合并规则（若存在可复用 seam）。
2. `swift test` 全绿，`git diff --check` 通过。
3. 用户用 Xcode 真机验证冷开与复开 `/perf` 的 `readerParse`、`readerToFirstPage` 和 `readerOpen`，确认首帧内容、位置、偏好、标注不变。

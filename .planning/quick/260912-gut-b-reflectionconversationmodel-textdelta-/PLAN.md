# 工作包 B：流式输出去抖合并

目标：降低 `ReflectionConversationModel` 在 Agent 文本流期间的主线程整串解析次数，保持可见文本、citation 过滤和完成后的持久化切换语义。

范围：

- 新增可测试的流式文本缓冲，delta 只追加到原始缓冲。
- 会话模型以约 50ms 窗口刷新可见文本；完成、取消和失败路径先刷新挂起内容。
- 保留现有 `withoutCitationBlock` 规则和滚动锚点触发条件。
- 不涉及多选文本、输入法、阅读器打开管线。

验证出口：

1. `StreamingResponseBuffer` 测试确认 delta 未刷新前不改变可见文本，刷新后一次性过滤 citation，完成后清空。
2. `swift test` 全绿，`git diff --check` 通过。
3. 用户重新安装 DEBUG App 后通过 `/perf` 观察 `streamDelta` 次数随去抖窗口下降；真机视觉和掉帧由用户验收。

# 工作包 B：流式输出去抖合并

已完成：

- 新增 `StreamingResponseBuffer`，将 provider delta 的全文累积与当前可见文本分离。
- `ReflectionConversationModel` 以 50ms 窗口调度可见刷新，避免每个 delta 触发 Markdown 解析、富文本构建和布局更新。
- `withoutCitationBlock` 在每次批次刷新时对累计全文执行，保持 citation 隐藏语义。
- `.completed` 先刷新挂起内容再清空流式状态；取消、失败和异常结束会刷新并保留局部回应。
- 新增 3 个 Swift Testing 回归用例，覆盖批次合并、过滤调用次数、完成清理与跨批次累积。

验证：

- `swift test`：352 个测试通过。
- `git diff --check`：通过。

待用户验收：

- Xcode 编译并重新安装 DEBUG App。
- 清空诊断采样，进行一次长回复，在 `/perf` 比较 `streamDelta` 刷新次数与主线程掉帧体感。
- 确认最终消息内容、citation 隐藏、完成后的滚动锚点与此前一致。

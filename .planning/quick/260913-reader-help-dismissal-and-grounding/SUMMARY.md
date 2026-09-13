# Reader Help 关闭语义与回答边界修正完成

## 已完成

- Reader Help sheet 禁止交互式下滑关闭。
- 下滑只允许改变 detent，不再让用户误丢当前问答。
- 右上角 X 改为唯一的取消并完全丢弃入口，调用 `ReaderHelpModel.discard()`。
- Citation 跳转等程序化关闭不丢弃 thread。
- Reader Help Prompt 升级为 `reader-help-v2`。
- 书内事实仍必须依赖本地证据；现实背景和通识问题允许直接回答。
- 不再把“原文没有提及”作为拒绝回答用户实际问题的完整答案。
- 现实背景明确标记为外部背景，不伪装成书中原文。
- 未引入 WebSearch，保留为后续按需共享能力。

## 验证

- `swift test --filter ReaderHelp`：9 tests 全绿。
- Reader Help policy 测试覆盖通识回答策略和 prompt v2 metadata。
- App Reader Help 文件纯语法解析通过。
- `Package.resolved` 已恢复。

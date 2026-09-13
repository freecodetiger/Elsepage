# Reader Help 可交付实现完成

## 已完成

- 新增独立 ephemeral `ReaderHelpService`，不依赖 Reflection、Brain、Memory、session 或 routing trace。
- 复用 `AgentExecutor`、`ReaderAgentContextBuilder`、`ContextAssembler` 与 `AgentCitationValidator`。
- 每轮只运行一次回复模型调用，不执行 Reflection LLM routing。
- 严格使用选段 locator 解析 CARC；`textAfter`、后续 child 与后续 resource 不进入 Prompt。
- 无 progression 或 index 不可用时 fail-closed，仅允许可见选段与 `textBefore`。
- Reader UI 选句工具栏新增“问”，打开独立的轻量底部面板。
- 支持一键解释、文本追问、流式显示、取消、重试、复制和显式存为 Note。
- 临时 thread 在当前 ReaderScreen 内保留，退出 Reader 或未保存即丢弃。
- 普通问答不写数据库；只有“存为笔记”调用现有 Note 仓库。
- `xcodegen generate` 已更新 App 与 Xcode test target 文件引用。

## 新增文件

- `Sources/ReaderAgent/ReaderHelp.swift`
- `Sources/ReaderAgent/ReaderHelpService.swift`
- `App/Reader/ReaderHelpModel.swift`
- `App/Reader/ReaderHelpSheet.swift`
- `Tests/AgentProviderTests/ReaderHelpServiceTests.swift`
- `Tests/ReadLoopCoreTests/ReaderHelpContextTests.swift`
- `docs/testing/reader-help/2026-09-13-delivery-checklist.md`

## 验证

- `swift test`：382 tests 全绿。
- Reader Help 专项测试：8 tests 全绿。
- `git diff --check` 通过。
- App Swift 文件纯语法解析通过。
- `Package.resolved` 已在测试后恢复，无意外依赖变化。

## 待用户验收

- App target `xcodebuild` 编译。
- 真机执行 `docs/testing/reader-help/2026-09-13-delivery-checklist.md`。
- 验证键盘、面板呈现、Provider 流式/非流式、CARC 边界、Note 保存与退出生命周期。

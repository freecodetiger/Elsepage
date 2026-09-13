# E-P2：冷启动数据库迁移移出主线程

## 目标

将 `AppModel.start()` 中的 `AppDatabase` 创建与 GRDB migration 从 `@MainActor` 启动关键路径移到 detached 后台任务，同时保持启动失败显示、local-first 数据和后续对象图组装顺序。

## 步骤

1. 在 `AppDatabase` 提供可测试的后台打开入口，使用 `Task.detached` 执行现有同步初始化；不改变同步初始化 API，避免影响现有调用方。
2. 让 `AppModel.start()` 使用后台入口获取已迁移数据库，再在主 actor 上按现有顺序组装 repositories/models 并加载数据。
3. 添加包级回归测试，验证后台打开会完成完整 schema migration 并保留可读写能力。
4. 更新性能规格、active execution plan、状态和本 quick summary，记录验收边界与用户真机验证步骤；不虚构当前尚未接入的 `launchInteractive` 采样项。
5. 运行 `swift test`、恢复 `Package.resolved`（如被 SwiftPM 改写）并执行 `git diff --check`。

## 验收标准

- 数据库迁移不在 `AppModel.start()` 的主 actor 同步段执行。
- 任一迁移错误仍从 `start()` 传播到既有 `startupError` UI。
- 全部包测试通过；新增测试可独立运行。
- 不运行 Xcode build；真机启动体感由用户安装 DEBUG 构建后验证。

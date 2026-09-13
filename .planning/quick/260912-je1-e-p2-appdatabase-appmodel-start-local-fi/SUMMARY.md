# E-P2：冷启动数据库迁移移出主线程

## 已完成

- 新增 `AppDatabase.openOffMain(path:)`，在 detached executor 中执行同步 `DatabaseQueue` 创建和完整 GRDB migration。
- `AppModel.start()` 改为等待后台数据库准备完成后继续组装 repositories/models；`startupError` 捕获范围、local-first 数据路径和对象图初始化顺序保持不变。
- 新增 `backgroundOpenMigratesFileBackedDatabase` 回归测试，验证数据库迁移到 v26 且 writer 可用。
- 更新 `docs/INTERACTION_PERFORMANCE_SPEC.md`、`docs/exec-plans/active/client-interaction-performance.md` 与 `.planning/STATE.md`。

## 验证

- `swift test`：353 tests 全部通过。
- `git diff --check`：通过。
- 未运行 Xcode build、模拟器或真机测试（遵循项目验证分工）。

## 用户验收

用 Xcode Build & Install 最新 DEBUG App 后，首次冷启动观察启动骨架是否保持响应，并与重装前启动体感对照；当前 `/perf` 尚未单独记录 `launchInteractive`，因此以启动骨架响应和 Today 可交互时刻手测为准。迁移失败路径仍应显示“无法打开本地书库”。

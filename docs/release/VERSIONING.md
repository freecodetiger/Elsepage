# 版本工程约定(VERSIONING)

> 确立于 Phase 10(REL-03)。适用于 v1.0 首发及后续所有 TestFlight / App Store 轮次。

## 1. 结论(当前值)

| 项 | 值 | 定义位置 |
|---|---|---|
| Marketing Version(`CFBundleShortVersionString`) | **1.0.0** | `project.yml` → target `ReadLoop` → settings.base → `MARKETING_VERSION` |
| Build Number(`CFBundleVersion`) | **1**(每次 TestFlight 上传递增) | 同上 → `CURRENT_PROJECT_VERSION` |
| 最低部署目标 | **iOS 18.0**(维持不变,本次未改) | `project.yml` → options.deploymentTarget |
| Bundle ID | `com.readloop.reader`(维持不变) | `project.yml` → settings.base |

单一事实源:`project.yml`。`App/Info.plist` 中的 `CFBundleShortVersionString` / `CFBundleVersion` 为构建变量 `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`,不要在 Info.plist 里直接写死版本号。

## 2. Marketing Version 策略:随发布走

- 格式 `MAJOR.MINOR.PATCH`(semver 风格):
  - `MAJOR`:里程碑(0.1 Reader Foundation → 0.2 Reflection Loop → 0.3 Memory → 0.5 TestFlight → **1.0 App Store 首发**),与 PRD §18 版本路线对齐;
  - `MINOR`:对外功能发布;
  - `PATCH`:修复轮次;
- **一次对外发布(TestFlight 正式轮或 App Store 提交)只对应一个 marketing version**;同一 version 下可有多个 build;
- 与 PRD/ROADMAP 里程碑对齐:v1.0 首发即 1.0.0;v2 特性线(PRD §8)起为 2.x;
- 改动位置:只改 `project.yml` 的 `MARKETING_VERSION`,然后运行 `xcodegen` 重新生成 `ReadLoop.xcodeproj`(由执行构建的用户完成;Agent 只改 yml)。

## 3. Build Number 策略:随 TestFlight 上传走

- `CURRENT_PROJECT_VERSION` 从 1 起,**每上传一次 TestFlight 递增 1,不复用**;
- 同一个 build 号被 App Store Connect 拒收后:若修复后重新 archive 上传,必须递增 build 号(build 号在 ASC 上传即占用,不可覆盖);
- 推荐 Archive 前手动 bump;如后续引入 CI,可改为上传时自动注入(如 `xcodebuild CURRENT_PROJECT_VERSION=$BUILD_NUM`),但日常约定仍是 project.yml 为准;
- 崩溃恢复/验收清单(Phase 11 REL-04/REL-05)记录现象时,请同时记录 marketing version 与 build 号,便于 TestFlight 轮次追溯。

## 4. 操作流程(用户手动执行)

1. 编辑 `project.yml`(或确认无需改动);
2. 运行 `xcodegen` 重新生成工程;
3. Xcode 里 Archive → Organizer 上传;上传前核对 Organizer 显示的 version/build;
4. TestFlight 新轮次:build +1;对外新发布:marketing version 按第 2 节更新。

## 5. 品牌红线

PRD 头部约定:正式产品名待定(候选:余思 / 页外),**正式命名前不要在代码中硬编码品牌名**。当前代码中仅 `project.yml` 与 `App/Info.plist` 的 `CFBundleDisplayName` 使用了显示名「页外」,属于显示层配置;营销文案、元数据见 `APP-STORE-METADATA.md`(其中品牌名决策待定,已标注)。

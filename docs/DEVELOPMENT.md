# 开发与协作入口

本项目是 Swift 6 / iOS 18 的本地优先 EPUB 阅读与思考应用。工程名为 ReadLoop，产品名为 Elsepage / 页外；这些名称并存有历史原因，不应在接手时全局替换。

## 先读什么

1. [ReadLoop_PRD.md](../ReadLoop_PRD.md)：产品约束与优先级。已接受的偏差先按 §0 写回 PRD。
2. [AGENTS.md](../AGENTS.md)：Agent 工作流和开发/验证分工；仓库编辑从 GSD quick、debug 或 phase 入口开始。
3. [ARCHITECTURE.md](../ARCHITECTURE.md)：Agent 链路的历史架构快照；具体行为需对照当前代码。
4. [DEBUG 测试闭环](DEBUG-LOOP.md)：业务改动、交互性能、DEBUG 服务及测试脚本的维护规则与能力边界。
5. [仓库清理报告](maintenance/repository-hygiene-2026-10-22.md)：历史文档、分支差异及仍需团队决定的事项。

## 环境与验证

- Swift 6；iOS App 需要 Xcode 与 iOS 18 SDK。
- XcodeGen：`brew install xcodegen`。
- [Package.swift](../Package.swift) 固定 GRDB 7.11.1；[project.yml](../project.yml) 还固定 Readium 3.11.0。
- 首次解析依赖需要网络；日常包测试不需要真实模型 Key。

在仓库根目录执行：

```sh
git status --short
swift test
git diff -- Package.resolved
```

`swift test` 覆盖 Package.swift 中四个 test target，不编译 `App/` 或 `Tests/ReadiumIntegrationTests/`。不要将包测试通过等同于 iOS App 构建或真机验收通过。`Package.resolved` 同时保留 Xcode 依赖 pins，包测试可能改写它；运行前记录原始状态，仅恢复本次命令造成的非预期变更，保留已有改动。

由开发者本人生成/打开工程，选择自己的签名团队后构建安装：

```sh
xcodegen generate
open ReadLoop.xcodeproj
```

`project.yml` 中的 `DEVELOPMENT_TEAM` 是维护者的签名配置，不是密钥。新成员需要自己的签名权限；不因换电脑直接提交个人签名设置。Agent 只执行约定内的包测试与 DEBUG 闭环，Xcode 构建、模拟器、真机手势和 TestFlight 由用户执行。

真实 Provider 验收由用户提供 Key；App Key 仅保存在 Keychain。Bench CLI 按 [Bench 文档](bench/README.md) 使用本地环境变量，不把真实 Key 或个人阅读数据写入 Git。

## 目录怎么用

| 目录/文件 | 职责 |
| --- | --- |
| `App/` | iOS 界面、依赖组装、Readium 与 DEBUG 性能入口 |
| `Sources/` | Swift 包领域模块、Agent、检索、存储与 Bench CLI |
| `Tests/` | 包测试、专用测试 EPUB、iOS Readium 集成测试 |
| `Fixtures/` | 测试 EPUB 源文件、Bench 样本、ReadProgress 实验语料 |
| `Scripts/` | EPUB 生成、DEBUG 闭环及其脚本测试 |
| `.planning/` | GSD 计划、历史执行证据与进度；不当作临时文件删除 |
| `docs/` | Feature Spec、ADR、验收记录、发布材料 |
| `docs/assets/branding/` | 独立品牌素材；App 正式图标仍在 asset catalog |
| `docs/prototypes/` | 历史 HTML 原型，不参与构建 |
| `ReadLoop.xcodeproj` / `project.yml` | 提交的 Xcode 工程及其 XcodeGen 配置；两者都保留 |

## 协作前先对齐

- 本次审计基于 `main@84d2e09`。当时本地 `main` 领先本地记录的 `origin/main` 18 个提交；没有 fetch，远端实时状态未确认。
- 架构图集提交 `9b13a9a` 和 RAG Bench 后续工作当时仍在 `ragbench`，不在本次 main 基线。由维护者决定集成范围，清理操作不代替合并。
- `.planning/STATE.md` 的顶层进度与后面的完成记录存在滞后；`docs/exec-plans/active/` 也含已完成或已取代的计划。先核对实际代码和验收记录再认领任务。
- `ReadLoop_Technical_Design.md`、`docs/brain.md` 是重要设计资料，但包含早期方案表述；它们不是每项能力都已实现的证明。
- `.planning/WORKTREES.md` 有维护者机器的绝对路径及旧验证约定，不能直接照搬；验证分工以当前 AGENTS.md 为准。
- `CLAUDE.md` 目前指定现维护者的 Git 提交身份；新增协作者的署名策略需要维护者另行调整，不要直接沿用他人的身份。
- 项目采用未经修改的 [GNU GPL version 3](../LICENSE)（`GPL-3.0-only`），未附加例外或限制；单独标注许可证的文件及第三方依赖保留各自许可。提交贡献前应确认有权按项目许可证提供这些代码。

`.agents/`、`.swiftpm/` 和 Xcode `xcuserdata/` 是被忽略的本地工具/偏好目录，不交付给协作者。`.build/`、`DerivedData/` 是可再生成缓存；清除后首次测试/构建会更慢，可能需要重新下载依赖。分享项目优先使用 Git checkout，避免把整个本地目录连缓存和个人设置一起打包。

# 贡献指南 · Contributing

欢迎参与 Elsepage / 页外。你可以提交问题复现、改进文档、完善阅读与反思体验，或帮助检验 Agent 和长期记忆的质量。Issue 和 Pull Request 都可以使用中文或英文。

首次参与请先阅读 [README](README.md)、[开发与协作入口](docs/DEVELOPMENT.md) 和 [PRD](ReadLoop_PRD.md)。无需真实模型 Key，也可以参与文档、代码和包测试工作。

## 从哪里开始

| 方向 | 可以帮助的事情 |
| --- | --- |
| 阅读可靠性 | EPUB 兼容、阅读位置恢复、标注与引用跳转、无障碍、交互性能。 |
| Reflection | 输入与保存、失败恢复、语音体验、Journal 回看。 |
| Agent 与检索 | 证据相关性、已读边界、引用校验、上下文预算和回归评估。 |
| Personal Brain | Thought / Question / Memory 的来源证据、编辑、删除和修订记录。 |
| 文档与验收 | 上手说明、可复现问题、已验证与未验证能力的区分。 |

先查看 [现有 Issues](https://github.com/freecodetiger/Elsepage/issues)，避免重复工作。较大的功能、依赖或架构调整先开 Issue 讨论问题与范围；小型修复和文档改进可以直接提交 PR。

## 提交问题

Bug 报告尽量包含：

- App 构建或源码提交、iOS 版本及设备型号。
- 最短复现步骤、预期行为、实际行为，以及是否稳定复现。
- 与问题有关的截图或经过脱敏的日志；性能问题区分首次打开、冷启动和重复操作。

不要在公开 Issue 中上传 API Key、签名证书、个人数据库、真实阅读感想或未经授权的电子书。EPUB 问题优先提供有权分享的最小样本；测试 EPUB 的约定见 [Fixtures 说明](Tests/ReadLoopCoreTests/Fixtures/README.md)。

## 开发流程

1. 无仓库写权限时先 Fork；有写权限的协作者也请在独立分支工作。
2. 从准备提交到的最新 `main` 建立分支，一次 PR 解决一个明确问题。
3. 沿用 Swift 6 和现有模块结构，避免混入无关重构、格式化或重依赖。
4. 完成相应验证与文档更新后，向上游 `main` 提交 PR；有冲突时保留双方有效改动。

项目使用 XcodeGen。新增 App 文件或调整 target 时，同步维护 [project.yml](project.yml) 和提交的 `ReadLoop.xcodeproj`，并检查生成 diff。不要提交个人签名团队、用户偏好或构建缓存。

使用本仓 Agent 开发时，遵循 [AGENTS.md](AGENTS.md) 的 GSD quick / debug / phase 入口与验证分工。维护者机器的路径、代理和本地 Git 身份配置不应直接复制到协作者环境。

## 产品与数据边界

PRD 的 P1–P9 优先于局部功能目标；已经接受的产品偏差须先按 PRD §0 记录，再改相应代码。资源冲突时遵循：

> Reflection Quality > Memory Quality > Reader Agent Quality > Habit Loop > Reader Feature Breadth

特别注意以下约束：

- 用户原始 Reflection 先保存，AI 输出作为派生内容，不能静默覆盖原文。
- 保持本地优先、用户控制数据和 BYOK；不引入 ReadLoop 自有业务后端。
- App API Key 仅存 Keychain；请求只直连用户配置的 Provider。
- 检索与证据展开都要遵守已读边界；记忆变更需要代码校验和来源证据。

## 如何验证

所有业务流程、交互性能、DEBUG 服务及测试脚本相关变更，先读 [DEBUG 测试闭环](docs/DEBUG-LOOP.md)，按其要求维护场景、能力表和证据。选择与变更有关的验证，不把计划执行的命令写成已经通过。

| 变更范围 | 验证与记录 |
| --- | --- |
| 仅文档 | 检查链接、命令、事实与 `git diff --check`；不要求运行 Swift 测试。 |
| Swift 业务代码 | 运行 `swift test`，要求所有包测试目标通过，按风险补充有意义的回归用例。 |
| iOS App / Readium 集成 | 包测试不编译 `App/`，也不运行 iOS 集成测试；由开发者本人完成 Xcode 构建、安装和所需设备验收，记录具体环境与结果。 |
| DEBUG 服务 / Mac 脚本 | 按闭环文档更新契约与测试；脚本测试命令为 `python3 -m unittest discover -s Scripts -p test_debug_loop.py`。设备协议与网络行为还需相应设备验证。 |
| Agent Prompt / Model / Retrieval | 遵循 [Bench 回归规范](docs/bench/REGRESSION.md)；真实模型评估需要用户提供 Key，未执行时明确列为待验收。 |

常用本地检查：

```sh
git status --short
swift test
git diff -- Package.resolved
git diff --check
```

`swift test` 不需要真实 Provider Key，但首次依赖解析需要网络。它可能改写 `Package.resolved` 中的 Xcode 依赖 pins；开始前记录文件状态，只恢复本次命令造成的非预期变化，保留原有修改。

验证职责以当前 AGENTS.md 为准：Agent 负责开发和包测试；Xcode 构建、安装、模拟器、真机手势与 TestFlight 由用户执行。用户启动 DEBUG App 后，Agent 可以执行文档支持的 HTTP 场景与性能读取。Reflection 保存的设备场景覆盖不能代表 Agent、Journal、Brain 或磁盘重启恢复全部通过。

## Pull Request 内容

标题和提交信息使用 Conventional Commits，例如 `fix: preserve reading position`、`docs: clarify provider setup`。保留实际贡献者的作者信息，不将他人的贡献改署为维护者。

PR 描述请说明：

- **问题与结果**：什么场景有问题，修改后用户看到什么行为。
- **改动范围**：涉及哪些模块，有无数据、协议或兼容性影响。
- **验证证据**：实际命令、结果、设备/构建信息；对 UI 变更附适当截图或操作说明。
- **剩余事项**：未执行的验收、已知限制及需要维护者协助的地方。

提交前检查：

- [ ] 改动范围集中，相关文档、规格与工程成员关系已同步。
- [ ] 与改动有关的检查已执行，或在 PR 中明确说明尚未执行的原因和范围。
- [ ] 没有混入 Key、个人数据、个人签名设置、缓存或无关依赖锁改写。
- [ ] 保留第三方许可证和已有版权声明，新增素材与代码有权贡献。

## 贡献许可

本项目采用未经修改的 [GNU GPL version 3](LICENSE)（`GPL-3.0-only`），未添加例外或额外限制。提交到本项目的贡献应有权按这一许可证提供；贡献者保留各自版权，不要求转让版权。

引入第三方代码或素材时，说明来源与原许可证，确认与其使用方式及项目许可兼容，并保留所需声明。已有单独授权的文件与第三方依赖继续遵循各自许可证。本指南不修改或替代 LICENSE 正文。

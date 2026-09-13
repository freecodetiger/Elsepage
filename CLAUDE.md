# Elsepage（工程代号 ReadLoop）

本地优先的 iOS EPUB 阅读器 + 个人思考循环（读 → 反思 → 有据可依的 AI 回应 → Journal）。Swift 6 / iOS 18 / Readium / GRDB / XcodeGen。

## 提交身份（必须遵守）

- 所有提交以 GitHub 用户 **freecodetiger** 的名义创建。git 已配置 `user.name=freecodetiger`、`user.email=2388387947@qq.com`。
- **不要**在提交信息中添加 `Co-Authored-By: Claude ...` 或其他 AI 工具的尾注 —— Claude Code 等是工具，不被视为贡献者。
- 提交信息用 Conventional Commits 前缀（feat / fix / docs / chore / test / refactor）。

## 工程注意

- 项目开发与验证分工以 [AGENTS.md](AGENTS.md) 为准。开发业务流程、修复性能问题或编写测试时，先读 [DEBUG 测试闭环](docs/DEBUG-LOOP.md)，按其维护流程更新场景与能力清单。
- 生成工程：`xcodegen generate`；便携测试：`swift test`。Xcode 构建安装、模拟器、真机手势操作和 TestFlight 由用户执行；Agent 可在已运行的 DEBUG App 上执行 HTTP 业务场景和读取性能数据。
- `swift test` 可能改写 `Package.resolved`（丢 Readium pins）；运行前记录状态，结束后仅恢复本次测试造成的改写，保留用户已有修改。
- 推送走本地代理（`git config http.proxy http://127.0.0.1:7890`）。

# Elsepage（工程代号 ReadLoop）

本地优先的 iOS EPUB 阅读器 + 个人思考循环（读 → 反思 → 有据可依的 AI 回应 → Journal）。Swift 6 / iOS 18 / Readium / GRDB / XcodeGen。

## 提交身份（必须遵守）

- 所有提交以 GitHub 用户 **freecodetiger** 的名义创建。git 已配置 `user.name=freecodetiger`、`user.email=2388387947@qq.com`。
- **不要**在提交信息中添加 `Co-Authored-By: Claude ...` 或其他 AI 工具的尾注 —— Claude Code 等是工具，不被视为贡献者。
- 提交信息用 Conventional Commits 前缀（feat / fix / docs / chore / test / refactor）。

## 工程注意

- 生成工程：`xcodegen generate`；便携测试：`swift test`（当前 123 个测试）；App 层用 unsigned iOS build 门禁。
- `swift test` 会改写 `Package.resolved`（丢 Readium pins），跑完记得 `git checkout -- Package.resolved`。
- 推送走本地代理（`git config http.proxy http://127.0.0.1:7890`）。

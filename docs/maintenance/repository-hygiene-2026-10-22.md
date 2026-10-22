# 协作前仓库清理报告

审计日期：2026-10-22。起点：`main@84d2e09`，工作区原本干净。

## 结论与实际清理

Git 跟踪的文件总体正常：基线共 465 个文件、约 12.7 MiB。大头是品牌图片，不是构建产物。未发现已跟踪的缓存、数据库、证书、`.env`、备份后缀、冲突残留文件或符号链接。

| 对象 | 证据与处理 |
| --- | --- |
| 根目录 `logo-fullbleed.png` | 与正式 AppIcon 的 1024 市场图标逐字节相同，删除此副本，保留 asset catalog 中的文件。减少工作树内容 28,665 bytes；不改写 Git 历史。 |
| 其余 5 个 Logo 文件 | 内容不同，属于独立素材版本；移动至 [品牌目录](../assets/branding/README.md)，保持字节不变。README 图片和发布素材说明已改为新路径。 |
| 根目录 `elsepage_calm_ios_v3.html` | 独立的历史 UI 原型，没有外部资源依赖；移动至 [原型目录](../prototypes/README.md)，保持字节不变。 |
| 4 个 `.DS_Store` | 根目录、`App/`、`App/Assets.xcassets/`、`docs/` 下的 Finder 元数据，均未跟踪，已删除。 |
| `.build/` | 已忽略、未跟踪的 SwiftPM 构建/依赖缓存，删除前占用 1,875,148 KiB。 |
| `DerivedData/` | 已忽略、未跟踪的 Xcode 输出，删除前占用 3,095,324 KiB。 |

缓存清理前确认没有 `xcodebuild`、`swift-build`、`swift-test` 或 `swift-frontend` 进程。合计清除约 **4.74 GiB** 的缓存分配空间；不代表测量了磁盘实际可用空间增量。后续首次测试或构建会重新解析/下载依赖。

## 看着重复或奇怪，但应保留

| 对象 | 保留依据 |
| --- | --- |
| AppIcon 中若干相同图片 | 同尺寸 slot 的文件内容可相同，但 `Contents.json` 引用不同文件名。18 个 filename 引用全部存在。 |
| `Package.resolved` | 保留 Xcode/Readium 依赖 pins，不是临时文件；`swift test` 可能改写它，见 [开发入口](../DEVELOPMENT.md)。 |
| `ReadLoop.xcodeproj` 和 `project.yml` | 工程与生成配置都已入库；成员关系测试直接读取 pbxproj，不能只保留生成器文件。 |
| `Fixtures/MinimalEPUB` 与测试 `minimal.epub` | 一个是 CC0 源文件，一个是由脚本生成并随测试分发的资源。不是重复垃圾。 |
| `docs/bench/runs/` 的 CSV/JSON | 基线与 judge/smoke 留档；CSV 为查看格式，JSON 为机器输入。回归规范明确要求旧基线不得删除或覆盖。 |
| `Fixtures/ReadProgressCorpus/` | 实验语料与 queries 不是生产运行必需文件，但包含可复现研究输入，应保留。其 README 引用的 `EXPERIMENT_BLUEPRINT.md` 不在本次 main，后续需明确来源。 |
| `.planning/` 与 `docs/testing/` | 执行计划、验收限制及证据；不能仅按日期老就删除。 |
| `.agents/` | 本地技能，已忽略；非项目源码，也不是构建缓存。保留本机文件，不交给协作者。 |
| `.swiftpm/`、Xcode `xcuserdata/` | 本地用户偏好，已忽略；本次不删除个人设置。 |
| `Tests/ReadiumIntegrationTests/Fixtures/Corpus/book-01-slow-gaze.epub` | 本机被忽略的实验 EPUB，来源/是否仍需未知；不是已确认可再生成的缓存，保留。 |

## 协作前仍需对齐的事项

这些是已发现的交接问题，不在本次文件清理中替团队决定：

1. **分支交付范围。** 起点 main 领先本地记录的 origin/main 18 commits；未 fetch，不代表远端实时状态。`ragbench@9b13a9a` 中已有架构图集和后续 RAG Bench 工作，尚未包含在本次 main 起点中。需要维护者决定是否及如何合并；本次未 merge、push 或重写历史。
2. **历史计划没有完全归档。** `docs/exec-plans/active/context-planner-protocol-refactor.md` 标明已完成，`llm-context-routing.md` 标明已被取代，`context-engineering-evolution.md` 标明已实施；仍被其他文档引用。建议后续以任务状态为依据归档并同步链接，不直接删除。
3. **设计文档存在时代差异。** `ReadLoop_Technical_Design.md` 仍自称长期 Source of Truth，`docs/brain.md` 含提案式表述，`ARCHITECTURE.md` 引用历史 develop 分支。PRD、Feature Spec 和当前代码的边界需统一解释，避免新成员把提案当实现。
4. **规划进度漂移。** `.planning/STATE.md` 顶部仍有 8 月进度及旧测试数量，后面已有 9 月完成记录；不依据文件清理推断哪些验收已经通过。
5. **个人环境约定。** `.planning/WORKTREES.md` 含维护者绝对路径，并有与 AGENTS.md 不一致的 Agent 构建要求；以当前 AGENTS.md 验证分工为准。`CLAUDE.md` 的 Git 作者身份和本地代理配置也需要为多人协作重新约定。未改写这些 Agent 指令。
6. **签名与许可。** `project.yml` 的 DEVELOPMENT_TEAM 为维护者签名团队标识，并非密码；新成员需要配置自己的签名权限。根 LICENSE 尚未发布，许可证选择由维护者决定。

README 已修正可直接确认的 Readium 版本（3.11.0）、旧测试数量/成功声明和 Today 目录说明，增加 [开发与协作入口](../DEVELOPMENT.md)。未按猜测重写产品完成度。

## 敏感信息检查的范围

检查了当前 Git 跟踪文件的敏感文件名、私钥头、常见 Provider/GitHub/AWS token 形状以及疑似硬编码凭据。4 处宽松匹配命中经检查为 Bench 环境变量提示语和测试用 `secret-for-test`，没有识别到真实凭据。

这属于常见模式静态检查，不是完整密钥审计：未安装/运行 gitleaks，未扫描全部 Git 历史、其他分支、被忽略的个人工具目录或二进制内容；也未对全部验收材料做个人信息审查。文档中能看到维护者用户名、邮箱、签名团队和机器路径，它们是协作约定信息，不等同于密钥。

## 验证记录

- 6 个迁移文件逐字节对照清理前 Git 内容；重复 Logo 对照留存 AppIcon。
- 检查 asset catalog 18 个图片资源引用。
- 确认 Swift 源码、App 资源、测试、Fixtures、Scripts、包配置、依赖 pins、Xcode 工程和 project.yml 均无变更。
- 检查本次新增/修改文档中的本地链接和原型资源路径，以及 `git diff --check`。
- 确认 `.build/`、`DerivedData/` 不再存在；Git 忽略规则、个人设置及实验 EPUB 保留。
- 本次不涉及业务或构建输入变更，未运行 `swift test`、xcodebuild、模拟器、真机或真实 Provider 验收，不声称 App 已经重新验证。

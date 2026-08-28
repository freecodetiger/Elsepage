# ReadLoop(工程代号,候选名:余思 / 页外)

## What This Is

一个以阅读为入口、长期陪用户思考的 iOS Personal Thinking Agent:本地优先的 EPUB 阅读器 + BYOK 云端模型 + 本地 Agent Runtime。用户读完输出 Reflection,Agent 基于阅读上下文与个人长期记忆给出克制而有增量的反馈,沉淀为 Journal 与 Memory。首批用户:18–35 岁、有阅读习惯、接受 BYOK 的中文读者。

Source of Truth 为仓库根目录 `ReadLoop_PRD.md`(当前 v0.2,计划内将更新至 v0.3 以记录实现偏差豁免)。

## Core Value

用户在读完书后愿意持续输出高质量 Reflection,并且这些输出随时间累积成一份可回溯的个人思想档案。

优先级冲突时遵循 PRD P9:`Reflection Quality > Memory Quality > Reader Agent Quality > Habit Loop > Reader Feature Breadth`。

## Requirements

### Validated

已有代码中实现并通过测试的能力(0.1–0.3 内核,详见 `ARCHITECTURE.md` 与代码盘点):

- ✓ EPUB 导入(Files/Share Sheet/AirDrop、指纹去重、后台全文索引)与书架(封面/进度/搜索/排序/删除)— 0.1
- ✓ 成熟阅读器(分页/滚动、外观、主题、TOC、划线 4 色、批注、书内搜索、位置恢复、引用回跳)— 0.1
- ✓ Reading Session 追踪与 Session Ending 汇总(有意义会话门槛策略)— 0.2
- ✓ 语音(Apple 系统转写)与文字 Reflection、转写润色、原始表达优先持久化 — 0.2
- ✓ BYOK 多 Provider(13+ preset、Keychain 存储、测试连接、请求透明度)— 0.2
- ✓ Reader Agent 反馈(628 行中文系统提示词、上下文路由、书内检索+跨书检索+记忆检索、引用校验)— 0.2
- ✓ 思想(Journal)时间线与书籍分组视图 — 0.2/0.3
- ✓ Memory 五类、evidence 可溯、准确/不准确/修改/忘记,My Mind「AI 眼中的我」— 0.3
- ✓ Reading/Thinking Streak、Today 产品状态机、4 个成就 — 0.5(部分)

### Active

当前首发范围见 `.planning/REQUIREMENTS.md`(v0.5 TestFlight 就绪 + v1.0 App Store 两个里程碑)。

### Out of Scope

PRD §17 全部非目标(PDF/OCR/漫画/书城/社交/排行榜/多 Agent/自建账号与后端/自动读后感等),另加本次决策明确的排除项——见 REQUIREMENTS.md Out of Scope 表。

## Context

- 技术栈:Swift 6 / iOS 18 / SwiftUI `@Observable` / GRDB+SQLite(v18 迁移,25+ 表)/ Readium swift-toolkit 3.3.0;约 17.3k LOC,40+ 测试文件。
- 模块:`Sources/` 14 个本地包(ReflectionCore、AgentRuntime、ReaderAgent、ContextRouting/ContextEngineering、RetrievalCore、ModelProviders、Persistence、SpeechCore、AchievementCore 等)+ `App/` SwiftUI 层。
- 已知缺口(2026-08-29 盘点):Onboarding 缺失、无 Delete All Local Data、ReaderAgentBench 缺失、假 Streaming 开关、Library/Today 信息不全、Journal 无用户编辑入口、agentDiscussionCount 恒为 0、Questioner/Changed-My-Mind 成就未解锁、无障碍未系统处理。
- 历史:曾有 15 个 codex/* worktree,已于规划时全部清理(含 vnext-provider-runtime 的 Anthropic 客户端 WIP,决定按现状重写)。

## Constraints

- **Tech stack**: 不换栈、不引重依赖 — 保持 Swift 6 + 现有包结构
- **Verification 分工**: Agent 只负责开发与 `swift test`(全部测试目标绿);xcodebuild 构建、模拟器、真机手测、TestFlight 上传均由用户手动完成 — 用户明确要求
- **Product invariants**: PRD 产品不变量 P1–P9 优先于任何 phase 目标;已接受的偏差必须先写回 PRD(§0 约定)再做对应代码改动
- **Data**: local-first,无 ReadLoop 自有后端;API Key 仅 Keychain;请求仅直连用户选择的 Provider
- **AI**: BYOK;涉及真实 Provider 联调的验收项(Test Connection、Agent 流程、Bench 真跑)需要用户提供 API Key

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| 首发分两阶段:v0.5(TestFlight 就绪)→ v1.0(App Store) | 对齐 PRD §18 路线,先真实用户验证核心循环再冲上架 | — Pending |
| 不做真流式输出,首发前移除假 Streaming 开关 | 开关现状是模拟 delta,给用户错误预期;流式非核心循环 | — Pending |
| 软缺口纳入:Library/Today 补全、Journal 用户编辑、小偏差批量修 | 强化信息架构完整性与 F9「忠于用户」 | — Pending |
| PRD 偏差写回 PRD v0.3(而非仅记在 .planning) | 保持 PRD Source of Truth 地位,符合 PRD §0 约定 | — Pending |
| 清理全部 15 个旧 worktree;Anthropic 客户端按现状重写 | 旧分支已合并或被 main 重新实现;WIP 落后 104 commits | ✓ Done 2026-08-29 |
| GSD:YOLO 模式 + 并行 + Standard 粒度 | 长程多 worktree 并发,人工只在验收节点介入 | — Pending |
| 每个 phase ≈ 一个并发 worktree(`elsepage-worktrees/`) | 延续既有惯例;集成纪律见 WORKTREES.md | — Pending |
| ReaderAgentBench 含 LLM-as-judge 自动评审 | 支撑「Prompt/Model/Retrieval 大改必跑回归」的可持续纪律 | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `$gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `$gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-08-29 after project initialization*

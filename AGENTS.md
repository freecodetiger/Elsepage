<!-- GSD:project-start source:PROJECT.md -->
## Project

**ReadLoop(工程代号,候选名:余思 / 页外)**

一个以阅读为入口、长期陪用户思考的 iOS Personal Thinking Agent:本地优先的 EPUB 阅读器 + BYOK 云端模型 + 本地 Agent Runtime。用户读完输出 Reflection,Agent 基于阅读上下文与个人长期记忆给出克制而有增量的反馈,沉淀为 Journal 与 Memory。首批用户:18–35 岁、有阅读习惯、接受 BYOK 的中文读者。

Source of Truth 为仓库根目录 `ReadLoop_PRD.md`(当前 v0.2,计划内将更新至 v0.3 以记录实现偏差豁免)。

**Core Value:** 用户在读完书后愿意持续输出高质量 Reflection,并且这些输出随时间累积成一份可回溯的个人思想档案。

优先级冲突时遵循 PRD P9:`Reflection Quality > Memory Quality > Reader Agent Quality > Habit Loop > Reader Feature Breadth`。

### Constraints

- **Tech stack**: 不换栈、不引重依赖 — 保持 Swift 6 + 现有包结构
- **Verification 分工**: Agent 只负责开发与 `swift test`(全部测试目标绿);xcodebuild 构建、模拟器、真机手测、TestFlight 上传均由用户手动完成 — 用户明确要求
- **Product invariants**: PRD 产品不变量 P1–P9 优先于任何 phase 目标;已接受的偏差必须先写回 PRD(§0 约定)再做对应代码改动
- **Data**: local-first,无 ReadLoop 自有后端;API Key 仅 Keychain;请求仅直连用户选择的 Provider
- **AI**: BYOK;涉及真实 Provider 联调的验收项(Test Connection、Agent 流程、Bench 真跑)需要用户提供 API Key
<!-- GSD:project-end -->

<!-- GSD:stack-start source:STACK.md -->
## Technology Stack

Technology stack not yet documented. Will populate after codebase mapping or first phase.
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->

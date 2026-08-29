# Phase 17: BrainProjectionService - Context

**Gathered:** 2026-08-29
**Status:** Ready for planning
**Source:** PRD Express Path(docs/brain.md §7-9,§20 Phase 6)

<domain>
## Phase Boundary

大脑的**唯一生产写入方**:Reflection 留下后,异步观察 → BrainRetriever 取候选 → LLM 输出强类型 BrainMutationProposal → BrainMutationValidator → 事务执行 → (embedding 由 Phase 15 的 contentHash 懒刷新)。交付后:大脑开始自动更新,记忆真正形成(proposeMemory),旧的 Journal memory_proposals 死链路被自然取代。

本 phase **不含**:继续想想 UI(形态已定 C,随本 phase 后的 App 任务接)、质量评估/trace 持久化(Phase 19)、旧 Journal 提案链路的删除(实践中是死代码,待投影路径 UAT 后清理)。
</domain>

<decisions>
## Implementation Decisions

### 四条蒸馏纪律(与用户讨论后锁定)
1. **statement 重写不续写**:updateThought 的陈述是"当前最好的单段总结",目标 ≤120 字,validator 硬上限 200 字(trim 后),超长拒绝并记 correction;旧陈述进 revisions(Phase 18)。
2. **置顶上下文最小化**:观察输入只带反思文本 + 候选摘要,不带任何历史对话与全部证据。
3. **attach > update > create(brain.md §9)**:v1 碎片化护栏——**仅在候选为空时允许 create**(候选来自 BrainRetriever 阈值过滤,非空即存在相关条目);候选非空时的 create 一律拒绝并记 correction。
4. **每次观察至多一个 mutation**:wire schema 是单提案,结构性杜绝一次刷一堆。

### 模块与触发(锁定)
- `BrainMutationProposal`(tagged union,7 值)定义在 **BrainCore**;Validator + Service 在 **ReaderAgent 模块**(它独有 AgentRuntime;Package.swift:ReaderAgent += BrainCore)。
- 触发:ReaderAgent 回复持久化完成后 fire-and-forget `Task { observe(...) }`——Brain 失败绝不影响 Reflection/回复(WAL:不 await、错误吞掉只记 outcome)。`projectionService: BrainProjectionService? = nil` 默认关闭(测试/Bench 零影响)。
- 观察文本:respond → 反思原文;continueDiscussion → 用户追问文本。
- 预算:1 call / 20s / 600 tok,temperature 0,**无修复重试**(维护路径,解码失败 = noChange outcome,永不阻塞用户)。

### 提案语义(锁定)
- attachEvidence(itemID, relation):证据 source = .reflection(观察的反思),weight 1;updateThought 附 .revises 证据;createThought 附 .origin;createQuestion/updateQuestion 附 .raises/.revises;proposeMemory 附 .origin。
- proposeMemory:创建 `BrainMemory(origin: .agentInferred, confidence: .medium, state: .needsReview)`——记忆的"AI 推断待确认"生命周期起点,用户在 MyMind 确认。
- validator:target 必须在候选中;内容 trim 非空 ≤200;create 仅候选为空;否则拒绝(noChange + corrections)。

### the agent's Discretion
- wire DTO 字段命名;prompt 文案;BrainProjectionOutcome 字段;测试断言方式。

</canonical_refs placeholder>
<canonical_refs>
## Canonical References

- `docs/brain.md` §7-9,§18,§20 Phase 6
- `Sources/ContextEngineering/BrainRetriever.swift`(候选)、`Sources/BrainCore/BrainRepository.swift`(执行)
- `Sources/ReaderAgent/ReaderAgent.swift`(触发点:completed 持久化后)
- `App/AppModel.swift:60-90`(embedding factory 复用)

</canonical_refs>

<deferred>
## Deferred Ideas

- brainProjectionTraces 持久化与验收率/碎片化率观测 → Phase 19
- 旧 Journal memory_proposals 链路删除 → 投影路径 UAT 后
- create 的相似度阈值(createThreshold 数值化)→ Phase 19 评估
- 继续想想按钮(App,形态 C 已定)→ 本 phase 后的 App 任务

</deferred>

---

*Phase: 17-brain-projection*
*Context gathered: 2026-08-29 via PRD Express Path*

# Phase 19: Evaluation / Observability - Context

**Gathered:** 2026-08-29
**Status:** Ready for planning
**Source:** PRD Express Path(docs/brain.md §20 Phase 8)

<domain>
## Phase Boundary

Brain 投影质量可观测:`brainProjectionTraces` 持久化(复用 routingTraces 的单 JSON 列模式)+ 诊断聚合(验收率/碎片化拒绝率/动作分布)+ Service 接线 + **继续想想按钮**(形态 C,用户已拍板)+ ARCHITECTURE.md 更新。

本 phase **不含**:LLM-judge 式的 Brain 质量评分(需要真实 Key 与样本积累,先以确定性指标 + 手测清单替代,见 Deferred)。
</domain>

<decisions>
## Implementation Decisions

### 追溯与隐私(锁定)
- `BrainProjectionTrace`:reflectionID、action、applied、corrections、candidateCount、durations、decodeFailed——**绝不存观察文本/反思正文**(ADR 0001 同款纪律);整行 JSON 单列,forward-compatible。
- 仓储协议 `BrainProjectionTraceRepository`(save / recentTraces(limit:) / diagnostics())定义在 BrainCore,GRDB 实现在 Persistence;v25 迁移建表;擦除清单覆盖。
- `BrainProjectionDiagnostics`:totalRuns、appliedCount、acceptanceRate、fragmentationRejections、actionDistribution([action: count])。BrainProjectionService 增加可选 `traceRepository`(nil = 不记录,默认关闭,测试零影响)。

### 继续想想(形态 C,用户已拍板,锁定)
- 入口:Thought/Question 详情页「继续想想」→ 输入 sheet(TextEditor)→ 提交后:
  1. 新建 Reflection(originalText = 用户文字,F9 满足;挂书规则 = item 最近一条 reflection 证据的书,无证据回退最近打开的书,无书则按钮隐藏);
  2. `readerAgent.respond(to: newID, activeBrain: item)` 流式回复直接显示在同一 sheet;
  3. 对话历史与回复沉淀在 Thoughts/Journal,Thought 靠 Phase 17 投影自然吸收新反思(attach/修订)。
- MyMindModel 需注入 `readerAgent: ReaderAgent?`(nil = 按钮隐藏);新增 `discussionBook(for:)` 与 `continueThinking(item:text:)`。
- 投影触发:新反思走 ReaderAgent 主链,投影服务自动观察(Phase 17 机制,无需额外接线)。

### the agent's Discretion
- sheet 布局与流式渲染细节(贴现有模式);诊断暂不出 UI(Settings 展示延后)。

</decisions>

<canonical_refs>
## Canonical References

- `docs/brain.md` §20 Phase 8;`docs/brain.md` §11A(继续想想)
- `Sources/Persistence/RoutingTraceRepository.swift` + v9 迁移(单 JSON 列模式,照抄)
- `Sources/ReaderAgent/BrainProjectionService.swift`(接线点)
- `App/MyMind/MyMindView.swift`(详情页按钮位)
- `.planning/phases/16-agent-bridge/16-SUMMARY.md`(形态 C 决策)

</canonical_refs>

<deferred>
## Deferred Ideas

- Brain 质量的 LLM-judge 评估集(需要真实 Key + 样本积累;先用手测清单:一条反思 → 检查是否形成 Thought/Memory、验收率数字)
- 诊断的 Settings UI
- 投影 trace 的 retention/清理策略

</deferred>

---

*Phase: 19-brain-observability*
*Context gathered: 2026-08-29 via PRD Express Path*

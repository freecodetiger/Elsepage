# Context Planner 协议重构 v2 — 已实施(2026-08-29)

> **状态**:已完成。`swift test` 全绿(327 tests / 15 suites)。本文记录协议 v2 的持久决策;链路全貌见根目录 `ARCHITECTURE.md`(子图 B 一节)。
> **原则**:LLM 决定语义意图,代码决定执行策略。单次 Planner LLM 调用不变。

## 目标链路

```text
ContextRoutingInput
→ LLM Semantic Planner (LLMReaderContextRouter, wire schema v2)
→ PlannerWirePlan → normalized()
→ strict SemanticContextPlan (tagged union ContextRequest)
→ SemanticPlanValidator → 修正后 SemanticContextPlan + corrections
→ ContextPolicyCompiler → ContextExecutionPlan
→ 既有 retrieval / ContextAssembler 管线(零语义行为变更)
```

## 持久决策(以源码消费为据)

1. **从 LLM 面移除的字段**及依据:
   - `memoryRetrieval`:ReaderAgent/Bench 在路由**前**就无条件取记忆(原 `ReaderAgent.swift:194`),plan 字段无任何消费者 → 记忆检索是**确定性系统策略**,由 `ContextPolicyCompiler` 输出 `MemoryRetrievalPolicy(topN: 2)`,不再进入 LLM 面(§5 nil 语义消歧)。
   - `candidateLimit` / `useReranker` / `expansionMode` / `expansionMaxTokens` / `retrievalMode`:检索层(`RetrievalQuery`/`LocalBookRetriever`)从不接收这些 plan 字段,仅曾流入指标与 trace → 全部改为编译期常量(hybrid / 10 / true / boundedWindow)。
   - `maximumEvidenceCount`:改为 purpose 查表(verifyBookFact 2 / 其余 3 / traceConcept 4),沿用原 validator 1...4 钳制域与兜底值 3 的量级。
   - `shouldNaturallyEnd`:ReaderAgentPolicy 从不消费 → 由 posture 编译导出,仅存于兼容 trace 形状。
   - `rationale`:免费文本无运营价值 → 从 Planner 协议移除;结构化可观测性走 `validationCorrections` + 既有 plan 快照字段。
2. **保留的语义决策**:intent(沿用 `ReflectionIntent` 枚举名,避免破坏 trace/bench)、nearby include/omit、book request(query/purpose/scope/denseQuery/lexicalTerms)、pastThought request(query/purpose)、`posture: respondOnly | mayAskQuestion`(取代 allowQuestion 裸布尔;`previousAgentAskedQuestion` 硬规则仍由代码强制)。
3. **封闭世界用枚举,开放世界用字符串**:queries/denseQuery/lexicalTerms 保持自然语言,240 字符上限在 wire 归一化与 validator 双重强制。
4. **Wire/域分离**:`PlannerWirePlan`(v2 契约,严格枚举解码)→ `normalized()` → `SemanticContextPlan`(无可选字段域模型,tagged union `ContextRequest`: nearby / book / pastThought)。memory 无请求变体(见 1)。
5. **兜底同域**:`DeterministicReaderContextRouter` 直接产出 `SemanticContextPlan`,与 LLM 路径共用同一 Validator + Compiler,单一执行语义。
6. **持久化兼容(边界兼容,内部正确)**:`routingTraces.traceJSON` 内嵌的 v1 形状(`ReaderContextPlan` / `ValidatedContextPlan`)原样保留;新行由 `ContextExecutionPlan.legacyProposal / legacyValidatedPlan` 编译出同形状快照。新增可选字段 `planSchemaVersion`(=2)/ `validationCorrections` / `routingDecodeAttempts`,旧行解码为 nil。`ContextPlanValidator` 删除(两套语义不允许并存)。
7. **可靠性边界保留**:结构化解码 → 围栏剥离 → 一次修复 → 确定性兜底,全链路 trace 化;重试数不扩大(仍 1 次修复),新增 `decodeAttempts` 观测清洗/修复率。ReadingBoundary 不经过 Planner 任何节点。

## 测试矩阵(§16 对应)

- A 解码:合法 v2 plan、非法枚举整计划拒绝→兜底、每个 tagged 变体、旧 trace 兼容解码。
- B 非法状态:未知旧键忽略且 memory 结构性不可能成为请求、缺省请求显式语义。
- C 语义校验:不可用来源丢弃+corrections、空 query 修复/丢弃、previousAgentAskedQuestion 硬规则、reflection 模式长度钳制。
- D 策略编译:purpose→策略表(4/3/2, hybrid+rerank+10+boundedWindow)、intent→预算表、posture→guidance、legacy 快照含编译参数。
- E 兜底:非 JSON / provider 失败 → 兜底,兜底计划走同一校验+编译路径产出合法执行计划。
- F 回归:trace round-trip、pipelineMetrics round-trip、旧形状解码、ContextAssembler 预算行为、全仓 327 测试。

## 未做(Non-Goals 维持)

Router Fast Path、多 Planner LLM 节点、ANN/HNSW/sqlite-vec、新 embedding/Small-to-Big/reranker 基建、工作流引擎、通用规划 DSL。

## 后续可另行考虑

- 若新 schema 下修复调用率实测趋零,可评估移除修复重试(需 bench 数据支撑)。
- `preferredScope` 三值在下游塌缩为两值(currentSection/currentChapter → currentResource);若语义规划持续区分不明显,可收敛为两值枚举。
- `denseQuery/lexicalTerms` 已进入执行计划,但 `RetrievalQuery` 尚未拆分 dense/lexical 检索通道(P1 演进的最后一段接线),当前两者仍共用 `query` 文本进 lexicalSearch 与 embedding。

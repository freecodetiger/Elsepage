# Elsepage 架构总览(Agent 链路全貌)

> 俯视图:从架构视角审视当前 Agent 编排。**忠实于代码现状**(截至 `develop` 分支),节点与边界均以源码为据。
>
> 结论先行:**3 个 LLM 子图**(ReaderAgent / ContextPlanner / Polish),共享 1 个有界执行运行时,背后是 2 个模型适配器(chat / embeddings / rerank)+ 本地 GRDB 持久化 + 1 个 **Context Engineering 层**(确定性检索/去重/预算/组装,非 LLM)。确定性服务(校验、策略编译、兜底路由、引用验证、small-to-big、candidate ranking)与 LLM 节点严格分离。Planner 协议 v2:**LLM 决定语义意图,代码决定执行策略**(`SemanticPlanValidator` + `ContextPolicyCompiler`)。

---

## 1. 总览:Agent 图 + Context Engineering + 共享运行时 + 工具层

```mermaid
flowchart TD
    UI["用户层<br/>阅读 / 反思 / 语音口述 / 设置"]

    subgraph AGENTS["Agent 编排层 (3 个 LLM 子图)"]
        RA["ReaderAgent<br/>主回答 Agent<br/>budget: readerReply<br/>(1 call / 45s 墙钟 / 1000 output tok)"]
        ROUTER["LLMReaderContextRouter<br/>Context Planner 子图 (wire schema v2)<br/>budget: 1 call / 8s / 800 tok"]
        POLISH["TranscriptPolishService<br/>语音润色子图<br/>1 call / 无 output 上限"]
    end

    subgraph CTX["Context Engineering 层 (确定性, 非 LLM)"]
        RET["Book Child Retriever<br/>lexical BM25 + semantic cosine + RRF + rerank gate<br/>→ SmallToBig 扩展 + 防剧透复检"]
        HYB["Reflection/Memory Retriever<br/>lexical + 独立 semantic 召回 (RRF 融合)<br/>SemanticVectorCache 进程内缓存"]
        ASM["ContextAssembler<br/>候选 → 去重 → source 优先级 → 预算打包<br/>→ ContextBundle → ReaderAgent"]
    end

    subgraph RUNTIME["共享运行时 (AgentRuntime)"]
        EXEC["AgentExecutor<br/>有界执行 + 流式事件 + 截断检测<br/>(finishReason == length → .truncated)"]
        BUDGET["ExecutionBudget<br/>maxModelCalls / maxWallTime / maxOutputTokens"]
    end

    subgraph PROV["模型适配器 (ModelProviders)"]
        CHAT["OpenAICompatibleModelClient<br/>chat/completions<br/>+ response_format(json_object 能力门控)"]
        EMB["OpenAICompatibleEmbeddingProvider<br/>/embeddings"]
        RERANK["SiliconFlowReranker<br/>/rerank cross-encoder"]
    end

    subgraph DB["本地持久化 (GRDB/SQLite)"]
        PERS["bookTextBlocks / bookChunks(parent+child, role/parentID)<br/>bookChunksFTS(trigram, child only) / bookChunkEmbeddings(child only)<br/>bookIndexJobs / bookReflections / reflectionMessages<br/>agentResponseEvidence / reflectionConnections / routingTraces / memories<br/>brainItems / brainItemEvidence / brainItemRelations / brainItemRevisions<br/>brainItemEmbeddings / brainProjectionTraces"]
    end

    UI --> RA
    UI --> POLISH
    UI --> ROUTER

    RA --> ROUTER
    RA --> RET
    RA --> HYB
    RA --> ASM
    RA --> EXEC
    ROUTER --> EXEC
    POLISH --> CHAT

    EXEC --> BUDGET
    EXEC --> CHAT

    RET --> EMB
    RET --> RERANK
    RET --> PERS
    HYB --> EMB
    ASM --> PERS
    RET --> PERS
```

**说明**
- 三个 LLM 子图各自独立、边界清晰:Planner 是 ReaderAgent 的**前置子图**;Polish 完全独立。
- **Context Engineering 是确定性层**:检索、扩展、防剧透、去重、预算、组装全部是代码,不押在 LLM 上。`AgentCitationValidator`、`SemanticPlanValidator`、`ContextPolicyCompiler`、`DeterministicReaderContextRouter`、`SmallToBigExpander`、`ContextCandidateRanker` 都是确定性服务。
- `AgentExecutor` 是三个节点**共用**的有界执行器;`ModelClientFactory`(BYOK)在运行期解析密钥。
- 防剧透边界(`ReadingBoundary`)在检索层与扩展层双重强制,不依赖 LLM 节点。

---

## 2. 子图 A:ReaderAgent 主链路(读 → 反思 → 有据回应)

```mermaid
flowchart TD
    START["respond(reflectionID) / continueDiscussion(reflectionID, messageID, text)"]
    START --> LOAD["加载 reflection + 历史 messages"]
    LOAD --> DEDUP{"已完成 agent 回复?<br/>(幂等重试)"}
    DEDUP -->|是| DONE["yield .completed(已存消息)<br/>直接结束"]
    DEDUP -->|否| CLIENT["models.makeClient()<br/>失败 → .providerNotConfigured"]

    CLIENT --> EVID["加载 currentEvidence → 取 currentLocator"]
    EVID --> CAND["全量反思 → sameBook / crossBook 候选"]
    CAND --> SESS["SessionContextBuilder.build<br/>session 区间 / 划线 / 批注 / 书内过往反思"]
    SESS --> RIN["组装 ContextRoutingInput<br/>interactionMode / 当前反思 / 最近6条对话 / 阅读状态 / 可用源 / 上轮是否提问"]

    RIN --> ROUTE["→ 子图B: LLMReaderContextRouter.route<br/>(语义计划: intent / 请求来源 / purpose / scope / 查询改写)"]
    ROUTE --> VALID["SemanticPlanValidator.validate<br/>可用性门控 / 空 query 修复 / 强对话规则<br/>→ SemanticContextPlan + corrections"]

    VALID --> COMPILER["ContextPolicyCompiler.compile<br/>证据数 / 检索策略 / 预算 按 intent+purpose 查表<br/>→ ContextExecutionPlan"]

    COMPILER --> CONN{"executionPlan.pastThought?"}
    CONN -->|是| SC["ReflectionRetriever<br/>lexical + 独立 semantic 召回 (RRF 融合)<br/>同书优先, 否则跨书<br/>连接持久化"]
    CONN -->|否| NOC
    SC --> NOC["yield .contextPrepared"]

    NOC --> MEM["MemoryRetriever<br/>lexical + semantic 融合, topN 2 (编译期系统策略)<br/>仅证据, 不建连接"]

    NOC --> BOOK{"executionPlan.book && 有边界?"}
    BOOK -->|是| BUILD["ReaderAgentContextBuilder.build<br/>→ 子图C: Child 检索 + Small-to-Big 扩展<br/>无边界 → 空证据(防剧透保守默认)"]
    BOOK -->|否| NOB

    NOB --> ASM["ContextAssembler<br/>nearby/book/reflection/memory → ContextCandidates<br/>→ 去重 / source 优先级 / 预算打包 → ContextBundle"]
    ASM --> REPLY["AgentExecutor.run(policy.input(...))<br/>ReaderAgentSystemPrompt.v3 + 证据块(带 [E1] 标记)"]

    REPLY --> EVT{"事件流"}
    EVT -->|.textDelta| TXT["yield .textDelta"]
    EVT -->|.truncated| TRUNC["replyTruncated = true"]
    EVT -->|.completed| CITE["AgentCitationValidator.validate<br/>evidenceID 存在 + 书索引 + 边界内"]
    EVT -->|.cancelled / .failed| ABORT["yield .cancelled / .failed"]
    CITE --> PERSIST["持久化 agent 消息 + responseEvidence + citations"]
    PERSIST --> YDONE["yield .citationsValidated + .completed"]
    YDONE --> DISC["yield .contextDisclosed<br/>(replyTruncated / dedup 数 / fallback 信息)"]
    DISC --> TRACE["saveTrace<br/>plan + 时长 + token 用量 + ContextPipelineMetrics<br/>(扩展数 / 去重数 / 实际 token / 语义缓存 hit-miss<br/>+ planSchemaVersion / validationCorrections / decodeAttempts)"]
```

**代码锚点**:`Sources/ReaderAgent/ReaderAgent.swift` · `ReaderAgentPolicy.swift` · `ReaderAgentSystemPrompt.swift` · `SessionContextBuilder.swift` · `AgentCitationValidator.swift` · `Sources/ContextEngineering/ContextAssembler.swift` · `Sources/ContextRouting/`(语义计划 / 校验 / 策略编译)

---

## 3. 子图 B:上下文 Planner 子图(语义规划 → 校验 → 策略编译)

Planner 协议 v2。中心原则:**LLM 决定语义意图,代码决定执行策略**。单次 LLM 调用不变;LLM 不再输出任何数值检索参数。

```mermaid
flowchart TD
    IN["ContextRoutingInput<br/>interactionMode / currentReflection<br/>recentConversation(≤6条×500字) / currentReading<br/>availableSources / previousAgentAskedQuestion"]
    IN --> ENC["JSONEncoder 序列化输入"]
    ENC --> REQ["AgentInput<br/>system: reader-context-router-v2 prompt<br/>temperature 0<br/>responseFormat: .jsonObject ← 能力门控"]
    REQ --> EXEC["AgentExecutor<br/>budget: 1 call / 8s / 800 tok"]

    EXEC --> COMP{"completed?"}
    COMP -->|"decode(PlannerWirePlan) 成功"| NORM["normalized()<br/>trim / 240 上限 / denseQuery·lexicalTerms 回退 query<br/>→ SemanticContextPlan"]
    COMP -->|"decode 失败"| STRIP["strippingJSONFences<br/>剥 Markdown 代码围栏后重试一次<br/>(decodeAttempts 计入 trace)"]
    STRIP -->|成功| NORM
    STRIP -->|仍失败| FB["DeterministicReaderContextRouter<br/>规则兜底 → 同一 SemanticContextPlan 域模型"]
    EXEC -->|".failed / .cancelled / .truncated"| FB

    NORM --> V["SemanticPlanValidator.validate<br/>来源可用性门控 / 空 query 修复 / ≤1 请求每源<br/>previousAgentAskedQuestion → 禁止提问(硬规则)<br/>reflection 模式 long→medium<br/>→ 修正后 SemanticContextPlan + corrections"]
    FB --> V

    V --> C["ContextPolicyCompiler.compile<br/>evidenceLimit 按 purpose 查表(2/3/4)<br/>retrievalMode=hybrid / candidateLimit=10 / useReranker=true / boundedWindow<br/>intent → ContextBudget 查表<br/>posture → ResponseGuidance<br/>→ ContextExecutionPlan (+v1 兼容快照)"]
```

**Wire schema v2(PlannerWirePlan,`reader-context-router-v2`)**:

```jsonc
{
  "intent": "emotionalRecord | passageObservation | authorDisagreement | conceptualQuestion | personalConnection | conversationContinuation | unclear",
  "nearbyPassage": "include | omit",
  "bookRetrieval": null 或 { "query", "purpose": "clarifyCurrentPassage | findEarlierSupport | findEarlierContrast | traceConcept | verifyBookFact",
                             "scope": "currentSection | currentChapter | readSoFar", "denseQuery?", "lexicalTerms?" },
  "pastThoughtRetrieval": null 或 { "query", "purpose": "findContinuation | findChange | findContradiction | findRecurringQuestion" },
  "response": { "length": "short | medium | long", "posture": "respondOnly | mayAskQuestion" }
}
```

**v1 → v2 字段决策**(以源码消费为据):
- 从 LLM 面移除:`maximumEvidenceCount`、`candidateLimit`、`useReranker`、`expansionMode`、`expansionMaxTokens`、`retrievalMode`、`memoryRetrieval`、`rationale`、`shouldNaturallyEnd` — 除 `denseQuery/lexicalTerms` 外全部无下游执行消费(仅曾流入指标/trace),记忆检索本就在路由前无条件执行。
- `allowQuestion` → `posture: respondOnly | mayAskQuestion`(闭集姿态,硬规则仍由代码强制)。
- `denseQuery/lexicalTerms` 保留(真实语义改写),执行策略中仍作为指标观测是否定制。
- 持久化兼容:`routingTraces` 行内嵌的 v1 形状(`ReaderContextPlan`/`ValidatedContextPlan`)原样保留,新行由 `ContextExecutionPlan` 编译出同形状快照;新增可选字段 `planSchemaVersion` / `validationCorrections` / `routingDecodeAttempts`(旧行为 nil)。

**代码锚点**:`Sources/ContextRouting/LLMReaderContextRouter.swift`(含 DeterministicReaderContextRouter 兜底)· `PlannerWirePlan.swift` · `SemanticContextPlan.swift` · `SemanticPlanValidator.swift` · `ContextPolicyCompiler.swift` · `ContextRoutingModels.swift`

---

## 4. 子图 C:RAG 链路(索引构建 + Child 检索 + Small-to-Big + 精排)

```mermaid
flowchart TD
    subgraph IDX["索引构建 (BookIndexPipeline) — 写侧"]
        A["extractor.blocks(for:startingAtResource:)<br/>按资源流式读取"] --> B["StructureAwareChunker<br/>parent target 900 / max 1400 / overlap 150<br/>+ child target 350 / max 600<br/>每个 parent 内切出 retrieval child"]
        B --> C["持久化<br/>bookTextBlocks + bookChunks(role=parent|child, parentID)<br/>FTS(trigram, 仅 child)"]
        C --> D["job.state = lexicalReady"]
        D --> EF{"embedding factory 可用?"}
        EF -->|是| F["embed 分批(100/批), 仅 child<br/>→ bookChunkEmbeddings(chunkID, model, dimensions, vector)"]
        F --> G["job.state = ready"]
        EF -->|否| G
    end

    subgraph RET["检索 (LocalBookRetriever.retrieve) — 读侧"]
        Q["RetrievalQuery<br/>text / ReadingBoundary(防剧透) / limit(parent 数) / scope"]
        Q --> L["词法: FTS5 BM25 (child only)<br/>CJK 重叠三元组 OR 召回<br/>边界谓词 + role + version 进 SQL"]
        L --> LR["lexical 排序 (1/(1+abs(bm25)))"]

        Q --> SF{"embedding provider?"}
        SF -->|"是"| V["查询向量 embed(query)<br/>拉全书 child 向量 + 余弦(topN)"]
        V --> SM["semantic 排序 (VectorMath.cosine)"]

        LR --> FUSE{"融合"}
        SM --> FUSE
        FUSE -->|"只有词法"| LEX["纯词法结果"]
        FUSE -->|"词法+语义"| RRF["HybridRanker.fuse<br/>RRF, k=60"]

        RRF --> GATE{"reranker?"}
        GATE -->|"是"| RR["SiliconFlowReranker.rerank<br/>child 候选交叉编码重打分<br/>过滤 score ≤ minimumRelevance(0.25)"]
        RR --> EXP["SmallToBigExpander<br/>child → 按 parentID 分组 → 父内 sibling 扩展<br/>maxTokens 有界, 不越出 parent<br/>ReadingBoundary 复检 + 裁剪未来部分<br/>(evidence.end ≤ boundary 由代码保证)"]
        EXP --> OUT["BookEvidence: id = anchor parent<br/>excerpt = 扩展窗口 (parent 锚定)"]

        LEX --> EXP
        GATE -->|"否"| EXP
    end

    C --> PDB[("GRDB/SQLite")]
    F --> PDB
    L --> PDB
    V --> PDB
```

**说明**
- **防剧透**:lexical SQL 谓词 → semantic 内存过滤 → **扩展层复检 + 未来裁剪**(含 straddling 裁剪与 endLocator 夹取)→ 无边界直接空。`evidence.end <= boundary` 由确定性代码保证。
- **rerank 是精排 gate**:默认 `minimumRelevance=0.25`;失败降级为融合结果。
- **退化链**:无 embedding → 纯词法;无 reranker / rerank 失败 → 融合;index 不可用 → graceful;无 boundary → 无 book evidence。

**代码锚点**:`Sources/RetrievalCore/RetrievalServices.swift` · `StructureAwareChunker.swift` · `SmallToBigExpander.swift` · `RetrievalModels.swift` · `Sources/Persistence/BookIndexRepository.swift` · `AppDatabase.swift` · `Sources/ModelProviders/OpenAICompatibleEmbeddingProvider.swift` · `SiliconFlowReranker.swift`

---

## 5. 子图 D:Personal Brain 维护路径(v1.1,fire-and-forget)

与 ReaderAgent 主链**解耦**的异步维护路径:回复持久化完成后触发,失败绝不影响 Reflection/回复。

```mermaid
flowchart TD
    PERSIST2["Reflection/回复持久化完成"] --> OBS["BrainProjectionService.observe<br/>(fire-and-forget Task)"]
    OBS --> CAND["BrainRetriever<br/>lexical + 持久化 embedding(brainItemEmbeddings)+ RRF<br/>kinds 过滤,候选 ≤4"]
    CAND --> LLM["brain-projection-v1<br/>1 call / 20s / 600 tok,无修复重试"]
    LLM --> DEC{"解码成功?"}
    DEC -->|否| NC["noChange(decodeFailed 入 trace)"]
    DEC -->|是| VAL["BrainMutationValidator<br/>target∈候选 / 内容≤200字蒸馏纪律<br/>create 仅候选空(碎片化护栏)/ 单提案"]
    VAL -->|通过| EXEC["事务执行<br/>attachEvidence(.origin/.revises/.raises…)<br/>updateThought 先记录旧陈述→brainItemRevisions"]
    VAL -->|拒绝| TRACE2["brainProjectionTraces<br/>(验收率/碎片化拒绝率/动作分布)"]
    EXEC --> TRACE2
```

**关键决策**:
- Brain 条目(用户自己的想法)**不进 [E] 引用体系**——它们不是可校验的外部证据;经 BrainContextProvider 适配为 `ContextSource.brain/pinnedBrain` 候选进 prompt 专属区块。
- 记忆经 `proposeMemory` 形成(needsReview/agentInferred),用户在 MyMind 确认;旧 Journal memory_proposals 链路为死代码待清理。
- 「继续想想」= 基于旧想法写新反思(挂书规则:item 最近反思证据的书),`activeBrain` 置顶直通 prompt,LLM 不可否决。
- 陈述蒸馏纪律:update 重写不续写(≤200 字硬上限),旧表述降级为修订 → 演化时间线。

**代码锚点**:`Sources/ReaderAgent/BrainProjectionService.swift` · `Sources/ContextEngineering/BrainRetriever.swift` · `BrainContextProvider.swift` · `Sources/BrainCore/`

---

## 5. 子图 D:AgentRuntime 执行器(三个子图共用的底座)

```mermaid
flowchart TD
    IN["AgentInput<br/>metadata(agentKind/promptVersion/contextRecipe) / messages / temperature / responseFormat"]
    IN --> RUN["AgentExecutor.run"]

    RUN --> BUD{"maxModelCalls > 0?"}
    BUD -->|否| BFAIL["yield .failed(.budgetExceeded)"]
    BUD -->|是| CALL["executeModelCall<br/>单次非流式 complete()"]

    CALL --> WATCH["watchdog 任务<br/>Task.sleep(maxWallTime) → 到点抛 budgetExceeded"]
    CALL --> STREAM["provider 事件透传<br/>.modelStarted / .textDelta / .usageUpdated"]

    CALL --> TRUNC{"finishReason == length?"}
    TRUNC -->|是| T["yield .truncated(先于 completed)"]
    TRUNC -->|否| COMP
    T --> COMP["yield .completed(AgentResult)"]

    COMP --> NORM["错误归一化<br/>ModelFailure → AgentFailure"]
    CALL --> CANCEL["Task.checkCancellation → .cancelled"]
```

**代码锚点**:`Sources/AgentRuntime/AgentExecutor.swift` · `AgentDomain.swift` · `ModelContracts.swift` · `FakeModelClient.swift`

---

## 6. 数据/持久化层(非 LLM,但支撑全部节点)

| 数据 | 用途 | 关键点 |
|---|---|---|
| `bookTextBlocks` | 原始文本块(资源级) | locator / progression 双轴 |
| `bookChunks` | **parent + child 单表** | `role`(parent\|child)+ `parentID`(v16);parent=上下文/证据单元,child=检索单元 |
| `bookChunksFTS` | FTS5 词法索引(仅 child) | `tokenize='trigram'`,BM25 打分,`indexVersion` 谓词 |
| `bookChunkEmbeddings` | 向量存储(仅 child) | BLOB 裸 Float32,按 `(chunkID, model)` 分桶 |
| `bookIndexJobs` | 索引状态机 | pending → extracting → lexicalReady → embedding → ready;`indexVersion` 当前 v3 |
| `bookReflections` / `reflectionMessages` | 反思与对话 | agent 消息附带 evidence + citations |
| `agentResponseEvidence` | 每次回复的证据快照 | 由 ContextAssembler 打包后的 bundle 映射而来 |
| `reflectionConnections` | 过去想法连接 | 同书优先;relevance 由融合排序产生 |
| `routingTraces` | 路由 + 管道可观测性 | `ContextPlanTrace` + `ContextPipelineMetrics`(全可选,旧行可解码) |
| `memories` | 长期记忆 | 仅作为证据透出,不建连接 |

---

## 7. 从俯视角度看到的边界与观察

1. **职责边界清晰**:三个 LLM 子图各管一段(计划 / 主回答 / 润色);Context Engineering 层把检索/扩展/防剧透/去重/预算/组装全部确定性化,ReaderAgent 不再手工竞争证据源。
2. **可靠性不押在 LLM 上**:计划有确定性兜底;检索层与扩展层双重防剧透;引用有确定性校验;截断有 `.truncated` 信号;语义检索失败回退纯词法。
3. **Small-to-Big 解耦**:child(≈350)负责"找到"(FTS/embedding),parent(900-1400)负责"理解"(证据/扩展窗口),`BookEvidence` 锚定 parent。
4. **可观测性成环**:`routingTraces` + `ContextDisclosure` + `ContextPipelineMetrics` 让计划/检索/扩展/去重/预算/语义缓存都可审计、可统计 fallback。
5. **语义混合是真召回**:Reflection/Memory 的有界 eligible 集整体嵌入,与 lexical 独立 top-K 经 RRF 融合——不是 lexical 召回后 rerank。

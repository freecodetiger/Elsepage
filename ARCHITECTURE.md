# Elsepage 架构总览(Agent 链路全貌)

> 俯视图:从架构视角审视当前 Agent 编排。**忠实于代码现状**(截至 `develop` 分支),节点与边界均以源码为据。
>
> 结论先行:**3 个 LLM 子图**(ReaderAgent / ContextPlanner / Polish),共享 1 个有界执行运行时,背后是 2 个模型适配器(chat / embeddings / rerank)+ 本地 GRDB 持久化 + 1 个 **Context Engineering 层**(确定性检索/去重/预算/组装,非 LLM)。确定性服务(校验、兜底路由、引用验证、small-to-big、candidate ranking)与 LLM 节点严格分离。

---

## 1. 总览:Agent 图 + Context Engineering + 共享运行时 + 工具层

```mermaid
flowchart TD
    UI["用户层<br/>阅读 / 反思 / 语音口述 / 设置"]

    subgraph AGENTS["Agent 编排层 (3 个 LLM 子图)"]
        RA["ReaderAgent<br/>主回答 Agent<br/>budget: readerReply<br/>(1 call / 45s 墙钟 / 1000 output tok)"]
        ROUTER["LLMReaderContextRouter<br/>Context Planner 子图<br/>budget: 1 call / 8s / 500 tok"]
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
        PERS["bookTextBlocks / bookChunks(parent+child, role/parentID)<br/>bookChunksFTS(trigram, child only) / bookChunkEmbeddings(child only)<br/>bookIndexJobs / bookReflections / reflectionMessages<br/>agentResponseEvidence / reflectionConnections / routingTraces / memories"]
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
- **Context Engineering 是确定性层**:检索、扩展、防剧透、去重、预算、组装全部是代码,不押在 LLM 上。`AgentCitationValidator`、`ContextPlanValidator`、`DeterministicReaderContextRouter`、`SmallToBigExpander`、`ContextCandidateRanker` 都是确定性服务。
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

    RIN --> ROUTE["→ 子图B: LLMReaderContextRouter.route<br/>(计划含 denseQuery/lexicalTerms/retrievalMode/记忆源)"]
    ROUTE --> VALID["ContextPlanValidator.validate<br/>clamp / trim / 按 intent 分配预算 / 强制的回复规则"]

    VALID --> CONN{"plan.pastThoughtRetrieval?"}
    CONN -->|是| SC["ReflectionRetriever<br/>lexical + 独立 semantic 召回 (RRF 融合)<br/>同书优先, 否则跨书<br/>连接持久化"]
    CONN -->|否| NOC
    SC --> NOC["yield .contextPrepared"]

    NOC --> MEM["MemoryRetriever<br/>lexical + semantic 融合, topN 2<br/>仅证据, 不建连接"]

    NOC --> BOOK{"plan.bookRetrieval && 有边界?"}
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
    DISC --> TRACE["saveTrace<br/>plan + 时长 + token 用量 + ContextPipelineMetrics<br/>(扩展数 / 去重数 / 实际 token / 语义缓存 hit-miss)"]
```

**代码锚点**:`Sources/ReaderAgent/ReaderAgent.swift` · `ReaderAgentPolicy.swift` · `ReaderAgentSystemPrompt.swift` · `SessionContextBuilder.swift` · `AgentCitationValidator.swift` · `Sources/ContextEngineering/ContextAssembler.swift`

---

## 3. 子图 B:上下文 Planner 子图(ContextRouter)

```mermaid
flowchart TD
    IN["ContextRoutingInput<br/>interactionMode / currentReflection<br/>recentConversation(≤6条×500字) / currentReading<br/>availableSources / previousAgentAskedQuestion"]
    IN --> ENC["JSONEncoder 序列化输入"]
    ENC --> REQ["AgentInput<br/>system: reader-context-router-v1 prompt<br/>temperature 0<br/>responseFormat: .jsonObject ← 能力门控"]
    REQ --> EXEC["AgentExecutor<br/>budget: 1 call / 8s / 500 tok"]

    EXEC --> COMP{"completed?"}
    COMP -->|"decode(ReaderContextPlan) 成功"| OK["ContextRoutingResult<br/>plan + usedFallback=false"]
    COMP -->|"decode 失败"| STRIP["strippingJSONFences<br/>剥 Markdown 代码围栏后重试一次"]
    STRIP -->|成功| OK
    STRIP -->|仍失败| FB["DeterministicReaderContextRouter<br/>规则兜底"]
    EXEC -->|".failed / .cancelled / .budgetExceeded"| FB

    OK --> VALID["ContextPlanValidator.validate<br/>(下游, 见子图A)"]
    FBR --> VALID

    subgraph PLAN["ReaderContextPlan (增强, 全可选字段)"]
        P1["intent / nearbyPassage / responseGuidance / rationale"]
        P2["bookRetrieval: query + denseQuery? + lexicalTerms?<br/>+ retrievalMode?(dense|lexical|hybrid)<br/>+ candidateLimit? + useReranker? + expansionMode?"]
        P3["pastThoughtRetrieval: query + maxCount"]
        P4["memoryRetrieval: query + maxCount (仅证据)"]
    end
    REQ --> PLAN
```

**代码锚点**:`Sources/ContextRouting/LLMReaderContextRouter.swift`(含 DeterministicRouter 兜底)· `ContextRoutingModels.swift` · `ContextPlanValidator.swift`

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

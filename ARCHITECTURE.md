# Elsepage 架构总览(Agent 链路全貌)

> 俯视图:从架构视角审视当前 Agent 编排。**忠实于代码现状**(截至 `develop` 分支),节点与边界均以源码为据。
>
> 结论先行:**3 个 LLM 子图**(ReaderAgent / ContextRouter / Polish),共享 1 个有界执行运行时,背后是 2 个模型适配器(chat / embeddings / rerank)+ 本地 GRDB 持久化。确定性服务(校验、兜底路由、引用验证)与 LLM 节点严格分离。

---

## 1. 总览:Agent 图 + 共享运行时 + 工具层

```mermaid
flowchart TD
    UI["用户层<br/>阅读 / 反思 / 语音口述 / 设置"]

    subgraph AGENTS["Agent 编排层 (3 个 LLM 子图)"]
        RA["ReaderAgent<br/>主回答 Agent<br/>budget: readerReply<br/>(1 call / 45s 墙钟 / 1000 output tok)"]
        ROUTER["LLMReaderContextRouter<br/>上下文路由子图<br/>budget: 1 call / 8s / 500 tok"]
        POLISH["TranscriptPolishService<br/>语音润色子图<br/>1 call / 无 output 上限"]
    end

    subgraph RUNTIME["共享运行时 (AgentRuntime)"]
        EXEC["AgentExecutor<br/>有界执行 + 流式事件 + 截断检测<br/>(finishReason == length → .truncated)"]
        BUDGET["ExecutionBudget<br/>maxModelCalls / maxWallTime / maxOutputTokens"]
    end

    subgraph RAG["RAG 检索工具链 (RetrievalCore)"]
        RET["LocalBookRetriever<br/>词法BM25 + 语义余弦 + RRF融合 + Rerank gate"]
        IDX["BookIndexPipeline<br/>索引构建: extract → chunk → FTS → embed"]
    end

    subgraph PROV["模型适配器 (ModelProviders)"]
        CHAT["OpenAICompatibleModelClient<br/>chat/completions<br/>+ response_format(json_object 能力门控)"]
        EMB["OpenAICompatibleEmbeddingProvider<br/>/embeddings"]
        RERANK["SiliconFlowReranker<br/>/rerank cross-encoder"]
    end

    subgraph DB["本地持久化 (GRDB/SQLite)"]
        PERS["bookTextBlocks / bookChunks / bookChunksFTS(trigram)<br/>bookChunkEmbeddings / bookIndexJobs<br/>bookReflections / reflectionMessages / agentResponseEvidence<br/>reflectionConnections / routingTraces / memories"]
    end

    UI --> RA
    UI --> POLISH
    UI --> ROUTER

    RA --> ROUTER
    RA --> RET
    RA --> EXEC
    ROUTER --> EXEC
    POLISH --> CHAT

    EXEC --> BUDGET
    EXEC --> CHAT

    RET --> EMB
    RET --> RERANK
    RET --> PERS
    IDX --> PERS
    RET --> IDX

    RA --> PERS
```

**说明**
- 三个 LLM 子图各自独立、边界清晰:Router 是 ReaderAgent 的**前置子图**;Polish 完全独立(不共享上下文、无路由)。
- `AgentExecutor` 是三个节点**共用**的有界执行器;`ModelClientFactory`(BYOK,`ConfiguredModelClientFactory`)在运行期解析密钥。
- Embedding / Rerank 是**工具调用**(无状态 HTTP 适配器),不是子图;`AgentCitationValidator`、`ContextPlanValidator`、`DeterministicReaderContextRouter` 是**确定性服务**,不是 LLM 节点。
- 防剧透边界(`ReadingBoundary`)在检索层强制,不依赖 LLM 节点。

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
    SESS --> MEM["matchingMemories(routingText, topN:2)<br/>词法匹配长期记忆(仅证据,不建连接)"]
    MEM --> RIN["组装 ContextRoutingInput<br/>interactionMode / 当前反思 / 最近6条对话 / 阅读状态 / 可用源 / 上轮是否提问"]

    RIN --> ROUTE["→ 子图B: LLMReaderContextRouter.route"]
    ROUTE --> VALID["ContextPlanValidator.validate<br/>clamp 条数 / trim query / 按 intent 分配预算 / 强制的回复规则"]

    VALID --> CONN{"plan.pastThoughtRetrieval?"}
    CONN -->|是| SC["strongestConnection<br/>同书反思优先, 否则跨书<br/>ReflectionLexicalMatcher(≥2词共现 + 40%重叠)"]
    CONN -->|否| NOC
    SC --> NOC["saveConnection + yield .contextPrepared"]

    NOC --> BOOK{"plan.bookRetrieval && 有边界?"}
    BOOK -->|是| BUILD["ReaderAgentContextBuilder.build<br/>→ 子图C: LocalBookRetriever.retrieve<br/>query / ReadingBoundary / scope / evidenceLimit<br/>按 bookEvidenceCharacters 截断 excerpt"]
    BOOK -->|否| NOB
    BUILD --> NOB["无边界 → 空证据(防剧透保守默认)"]

    NOB --> AEVID["组装 responseEvidence<br/>nearbyPassage(按预算) / bookPassage / pastReflection / memories"]
    AEVID --> REPLY["AgentExecutor.run(policy.input(...))<br/>ReaderAgentSystemPrompt.v3 + 证据块(带 [E1] 标记)"]

    REPLY --> EVT{"事件流"}
    EVT -->|.textDelta| TXT["yield .textDelta"]
    EVT -->|.truncated| TRUNC["replyTruncated = true<br/>(provider 在 maxOutputTokens 处截断)"]
    EVT -->|.completed| CITE["AgentCitationValidator.validate<br/>解析 ---CITATIONS--- 块<br/>校验 evidenceID 存在 + 书索引 + 边界内"]
    EVT -->|.cancelled / .failed| ABORT["yield .cancelled / .failed"]
    CITE --> PERSIST["持久化 agent 消息 + responseEvidence + citations"]
    PERSIST --> YDONE["yield .citationsValidated + .completed"]
    YDONE --> DISC["yield .contextDisclosed<br/>(含 replyTruncated / retrievedBookEvidenceCount / fallback 信息)"]
    DISC --> TRACE["saveTrace<br/>routing/retrieval/reply 时长 + token 用量 + fallbackReason<br/>→ routingTraces 表"]
```

**代码锚点**:`Sources/ReaderAgent/ReaderAgent.swift` · `ReaderAgentPolicy.swift` · `ReaderAgentSystemPrompt.swift` · `SessionContextBuilder.swift` · `AgentCitationValidator.swift`

---

## 3. 子图 B:上下文路由子图(ContextRouter)

```mermaid
flowchart TD
    IN["ContextRoutingInput<br/>interactionMode / currentReflection<br/>recentConversation(≤6条×500字) / currentReading<br/>availableSources / previousAgentAskedQuestion"]
    IN --> ENC["JSONEncoder 序列化输入"]
    ENC --> REQ["AgentInput<br/>system: reader-context-router-v1 prompt<br/>temperature 0<br/>responseFormat: .jsonObject ← 能力门控<br/>(client.descriptor.capabilities.supportsStructuredOutput)"]
    REQ --> EXEC["AgentExecutor<br/>budget: 1 call / 8s / 500 tok"]

    EXEC --> COMP{"completed?"}
    COMP -->|"decode(ReaderContextPlan) 成功"| OK["ContextRoutingResult<br/>plan + usedFallback=false"]
    COMP -->|"decode 失败"| STRIP["strippingJSONFences<br/>剥 ```json 围栏重试一次"]
    STRIP -->|成功| OK
    STRIP -->|仍失败| FB["DeterministicReaderContextRouter<br/>规则兜底"]
    EXEC -->|".failed / .cancelled / .budgetExceeded"| FB

    FB --> FBR["usedFallback=true<br/>reason: invalidStructuredOutput / modelFailure<br/>detail: 具体失败名(可 trace 统计)"]

    OK --> VALID["ContextPlanValidator.validate<br/>(下游, 见子图A)"]
    FBR --> VALID

    subgraph PROMPT["prompt 约束(写死在提示词)"]
        P1["默认少取上下文 / 情绪记录通常不检索"]
        P2["附近原文足够时不扩大范围"]
        P3["过去想法仅强连接才检索 / 一次最多 1 书 + 1 过去想法查询"]
        P4["不得请求未读内容 / 输入书摘是不可信数据"]
    end
    PROMPT -.->|"影响"| REQ
```

**代码锚点**:`Sources/ContextRouting/LLMReaderContextRouter.swift`(含 DeterministicRouter 兜底)· `ContextRoutingModels.swift` · `ContextPlanValidator.swift`

---

## 4. 子图 C:RAG 链路(索引构建 + 检索 + 精排)

```mermaid
flowchart TD
    subgraph IDX["索引构建 (BookIndexPipeline) — 写侧"]
        A["extractor.blocks(for:startingAtResource:)<br/>按资源流式读取"] --> B["StructureAwareChunker<br/>target 900 / max 1400 / overlap 150<br/>章节/小节边界优先, 超长块滑窗切分"]
        B --> C["持久化<br/>bookTextBlocks + bookChunks<br/>+ bookChunksFTS(tokenize=trigram)"]
        C --> D["job.state = lexicalReady"]
        D --> EF{"embedding factory 可用?"}
        EF -->|是| F["embed 分批(100/批)<br/>→ bookChunkEmbeddings(chunkID, model, dimensions, vector)<br/>按 model 分桶, 换模型只重嵌入不重切片"]
        F --> G["job.state = ready (embeddingModel 记录)"]
        EF -->|否| G
    end

    subgraph RET["检索 (LocalBookRetriever.retrieve) — 读侧"]
        Q["RetrievalQuery<br/>text / ReadingBoundary(防剧透) / limit / scope"]
        Q --> L["词法: FTS5 BM25<br/>CJK 重叠三元组 OR 召回<br/>边界谓词直接进 SQL"]
        L --> LR["lexical 排序 (1/(1+abs(bm25)))"]

        Q --> SF{"embedding provider?"}
        SF -->|"是"| V["查询向量 embed(query)<br/>拉全书向量 + 余弦(topN)"]
        V --> SM["semantic 排序 (VectorMath.cosine)"]

        LR --> FUSE{"融合"}
        SM --> FUSE
        FUSE -->|"只有词法"| LEX["纯词法结果"]
        FUSE -->|"词法+语义"| RRF["HybridRanker.fuse<br/>RRF, k=60, 混合排序位次"]

        RRF --> GATE{"reranker?"}
        GATE -->|"是"| RR["SiliconFlowReranker.rerank<br/>top-10 候选交叉编码重打分<br/>过滤 score ≤ minimumRelevance(0.25)<br/>(gate 默认开启)"]
        RR --> OUT["证据: prefix(query.limit)<br/>+ boundary.contains 复核"]

        LEX --> OUT
        GATE -->|"否"| OUT
    end

    C --> PDB[("GRDB/SQLite")]
    F --> PDB
    L --> PDB
    V --> PDB
```

**说明**
- **防剧透四层**:词法 SQL 谓词 → 语义候选内存过滤 → 最终输出复核 → 无边界直接空(`ReaderAgentContextBuilder.build`)。
- **rerank 是精排 gate**:默认 `minimumRelevance=0.25`(非 0),真正剔除低相关段落;失败降级为融合结果。
- **退化链**:无 embedding → 纯词法;无 reranker / rerank 失败 → 融合结果;均不阻塞主回复。

**代码锚点**:`Sources/RetrievalCore/RetrievalServices.swift` · `StructureAwareChunker.swift` · `RetrievalModels.swift` · `Sources/Persistence/BookIndexRepository.swift` · `AppDatabase.swift` · `Sources/ModelProviders/OpenAICompatibleEmbeddingProvider.swift` · `SiliconFlowReranker.swift`

---

## 5. 子图 D:AgentRuntime 执行器(三个子图共用的底座)

```mermaid
flowchart TD
    IN["AgentInput<br/>metadata(agentKind/promptVersion/contextRecipe) / messages / temperature / responseFormat"]
    IN --> RUN["AgentExecutor.run"]

    RUN --> BUD{"maxModelCalls > 0?"}
    BUD -->|否| BFAIL["yield .failed(.budgetExceeded)"]
    BUD -->|是| CALL["executeModelCall<br/>单次非流式 complete()(client.stream 内部就是一次调用)"]

    CALL --> WATCH["watchdog 任务<br/>Task.sleep(maxWallTime) → 到点抛 budgetExceeded"]
    CALL --> STREAM["provider 事件透传<br/>.modelStarted / .textDelta / .usageUpdated"]

    CALL --> TRUNC{"finishReason == length?"}
    TRUNC -->|是| T["yield .truncated(先于 completed)"]
    TRUNC -->|否| COMP
    T --> COMP["yield .completed(AgentResult)"]

    COMP --> NORM["错误归一化<br/>ModelFailure → AgentFailure<br/>(authentication/rateLimited/network/...)"]
    CALL --> CANCEL["Task.checkCancellation → .cancelled"]
```

**代码锚点**:`Sources/AgentRuntime/AgentExecutor.swift` · `AgentDomain.swift` · `ModelContracts.swift` · `FakeModelClient.swift`

---

## 6. 数据/持久化层(非 LLM,但支撑全部节点)

| 数据 | 用途 | 关键点 |
|---|---|---|
| `bookTextBlocks` | 原始文本块(资源级) | locator / progression 双轴 |
| `bookChunks` | 检索粒度单元 | `indexVersion`(当前 v2,overlap 变更后升版) |
| `bookChunksFTS` | FTS5 词法索引 | `tokenize='trigram'`,BM25 打分 |
| `bookChunkEmbeddings` | 向量存储 | BLOB 裸 Float32,按 `(chunkID, model)` 分桶 |
| `bookIndexJobs` | 索引状态机 | pending → extracting → lexicalReady → embedding → ready |
| `bookReflections` / `reflectionMessages` | 反思与对话 | agent 消息附带 evidence + citations |
| `agentResponseEvidence` | 每次回复的证据快照 | 供引用校验与 UI 溯源 |
| `reflectionConnections` | 过去想法连接 | 同书优先 |
| `routingTraces` | 路由可观测性 | `RoutingTraceDiagnostics` 聚合 fallback 统计 |
| `memories` | 长期记忆 | 仅作为证据透出,不建连接 |

---

## 7. 从俯视角度看到的边界与观察

1. **职责边界清晰**:三个 LLM 子图各管一段(路由决策 / 主回答 / 润色),共享底座是唯一的耦合点。
2. **可靠性不押在 LLM 上**:路由有确定性兜底;检索层有防剧透强制;引用有确定性校验;截断有 `.truncated` 信号。
3. **可观测性成环**:`routingTraces` + `ContextDisclosure` 让每次路由/检索/回复决策都可审计,`RoutingTraceDiagnostics` 已能统计 fallback 率。
4. **检索是双通道 + gate**:词法 BM25 与语义余弦经 RRF 融合,再由 cross-encoder rerank 精排,退化链完整。

我建议把「我的大脑」做成一个独立的 **Brain Domain**，而不是在现有 `memories` 表上不断加字段。核心原则是：

> **Reflection 是原始思考记录；Thought / Question 是从多次 Reflection 中逐渐形成的思想结构；Memory 是 Agent 可以长期依赖的稳定用户知识。**

这样 UI、Agent Context、长期记忆三件事就能统一，但不会混成一个概念。目前 ElsePage 已经把 Book / Reflection / Memory 当成不同 Context Source，并有确定性的 `ContextAssembler` 做去重、优先级和预算，因此 Brain 最好的接入方式是增加一层领域模型，而不是绕开现有 Context Engineering。 


---

# ElsePage Brain Module

## 1. 产品定义

「我的大脑」包含三个一级对象：

| 对象           | 本质                  | 示例               | 生命周期           |
| ------------ | ------------------- | ---------------- | -------------- |
| **Thought**  | 正在形成/演化的观点          | “自由真正困难的是承担选择”   | 会发展、修正、甚至反转    |
| **Question** | 尚未解决且值得继续追踪的问题      | “理解一个人是否意味着认同他？” | 出现→反复→探索→可能解决  |
| **Memory**   | Agent 可以长期依赖的稳定用户信息 | “用户倾向从责任角度理解自由”  | 建立→确认/强化→修改/遗忘 |

而已有的：

```text
Reflection
Book Passage
Conversation Message
```

不是 Brain Item，而是 **Evidence**。

关系应该是：

```text
                      Brain
                       │
          ┌────────────┼────────────┐
          ↓            ↓            ↓
       Thought       Question      Memory
          ↑            ↑            ↑
          └────────────┼────────────┘
                       │
                    Evidence
                       │
       ┌───────────────┼───────────────┐
       ↓               ↓               ↓
   Reflection      Book Passage    Conversation
```

这里最关键的设计约束是：

> **不要把 Reflection 升级成 Thought。Reflection 是“我某时某刻说过什么”，Thought 是“从多个证据看，我正在形成什么观点”。**

---

# 2. 三种对象必须保持语义区别

### Thought

Thought 是“可演化命题”。

例如：

```text
Title
自由是否意味着责任

Current Statement
我越来越觉得，自由最困难的部分并不是拥有选择，
而是没有人能替你承担选择的后果。

Stage
evolving

Evidence
8 Reflections
3 Books

History
2026.06 → 自由意味着不被束缚
2026.07 → 自由也会带来不安
2026.08 → 自由意味着承担选择
```

它不是 Memory，因为：

> 用户明天完全可能改变这个观点。

因此 Thought 天然应该保留：

```swift
enum ThoughtStage {
    case emerging
    case evolving
    case stable
    case reconsidering
    case archived
}
```

不要用 `isStable: Bool` 这种弱表达。

---

### Question

Question 是“持续存在的问题”，而不是一句带问号的 Reflection。

例如：

```text
理解一个人是否意味着认同他？

第一次出现
《局外人》 Chapter 2

再次出现
《人间失格》

相关 Thought
人与他人的距离
共情与判断

State
exploring
```

推荐：

```swift
enum QuestionState {
    case open
    case exploring
    case partiallyResolved
    case resolved
    case dormant
}
```

一个 Question 被“解决”以后，不应该简单删除。

更自然的是：

```text
Question
  ↓
逐渐形成答案
  ↓
Thought
```

因此存在关系：

```text
Thought --addresses--> Question
```

---

### Memory

Memory 是三者里权限最高的对象。

因为它以后会影响 Agent 的回答。

例如：

```text
“用户不喜欢 Agent 在每次回复最后继续追问。”

origin:
userExplicit

confidence:
high

source:
多次明确反馈
```

与：

```text
“用户似乎更喜欢从人物心理而不是情节角度阅读小说。”

origin:
agentInferred

confidence:
medium
```

必须在 UI 上区分。

推荐：

```swift
enum MemoryOrigin {
    case userExplicit
    case agentInferred
    case derivedFromThought
}

enum MemoryState {
    case active
    case needsReview
    case superseded
    case forgotten
}
```

Memory 必须：

```text
可查看
可编辑
可删除
可追溯来源
```

否则「我的大脑」很容易变成用户不信任的“隐形画像系统”。

---

# 3. Domain Model：优先使用强类型

这里非常适合我们刚讨论的原则：

> **Make illegal states unrepresentable.**

不要：

```swift
struct BrainItem {
    var type: String
    var questionState: String?
    var thoughtStage: String?
    var memoryOrigin: String?
}
```

推荐：

```swift
enum BrainItem {
    case thought(Thought)
    case question(Question)
    case memory(Memory)
}
```

领域对象：

```swift
struct Thought {
    let id: BrainItemID
    var title: String
    var statement: String
    var stage: ThoughtStage

    var createdAt: Date
    var updatedAt: Date

    var provenance: BrainProvenance
}

struct Question {
    let id: BrainItemID
    var question: String
    var state: QuestionState

    var createdAt: Date
    var updatedAt: Date
}

struct Memory {
    let id: BrainItemID
    var content: String
    var origin: MemoryOrigin
    var confidence: MemoryConfidence
    var state: MemoryState

    var createdAt: Date
    var updatedAt: Date
}
```

这样三种对象不会因为数据库方便而失去自己的语义。

---

# 4. Evidence 是整个 Brain 最重要的基础设施

我甚至认为 `BrainItem` 本身没有 Evidence 就不应该拥有很高可信度。

定义：

```swift
enum BrainEvidenceSource {
    case reflection(ReflectionID)
    case bookChunk(BookChunkID)
    case message(MessageID)
}
```

关系：

```swift
enum EvidenceRelation {
    case origin
    case supports
    case contradicts
    case revises
    case raises
    case answers
}
```

于是：

```text
Thought: 自由意味着责任
│
├── Reflection #17   supports
├── Reflection #31   supports
├── Reflection #44   revises
└── BookChunk #812   origin
```

Question：

```text
Question: 共情意味着认同吗？
│
├── Reflection #27   raises
├── Reflection #52   revises
└── Thought #8       answers
```

这会给你以后非常强的：

```text
可解释性
时间线
思想变化
Citation
Agent Context
```

能力。

---

# 5. Brain Item 之间也需要 Relation，但保持克制

不要一开始做一个“万能 Knowledge Graph”。

只存真正有产品意义的强关系：

```swift
enum BrainRelationType {
    case related
    case supports
    case contradicts
    case evolvesFrom

    case raises
    case addresses

    case derivedMemory
}
```

例如：

```text
Thought A
“自由意味着没有束缚”

       evolvesFrom
            ↓

Thought B
“自由意味着承担选择”


Question Q
“自由为什么会令人焦虑？”

       addressedBy
            ↓

Thought B
```

未来 Knowledge Graph 可以直接建立在这上面。

但 Graph 是这些关系的**视图**，不要反过来让图谱成为数据模型本身。

---

# 6. Persistence

我推荐：

```text
brainItems
brainItemEvidence
brainItemRelations
brainItemEmbeddings
```

而不是马上为 Thought / Question / Memory 建几十张表。

核心表概念上：

```text
brainItems
────────────────────────────
id
kind
title
content
state
origin
confidence
createdAt
updatedAt
contentHash
schemaVersion
```

Repository 层负责：

```text
kind = thought
→ Thought

kind = question
→ Question

kind = memory
→ Memory
```

Domain 层继续保持严格 `enum`，不要让数据库表示方式污染领域模型。

---

## brainItemEvidence

```text
brainItemID
sourceType
sourceID
relation
weight
createdAt
```

## brainItemRelations

```text
sourceItemID
targetItemID
relation
weight
createdAt
```

## brainItemEmbeddings

```text
brainItemID
model
dimensions
contentHash
vector
updatedAt
```

Embedding 应该持久化。

Brain Item 是非常典型的：

> 创建一次、长期反复检索。

查询时没有必要反复 embedding 全部 Thought / Question / Memory。

---

# 7. Brain 的构建不要阻塞 ReaderAgent

这一点非常重要。

当前 ReaderAgent 已经有完整的同步主链：

```text
Planner
→ Reflection/Memory/Book Retrieval
→ ContextAssembler
→ ReaderAgent
→ Citation/Persist
```



我不会把 Brain 更新塞进这条 critical path。

推荐：

```text
用户留下 Reflection
        ↓
Reflection Persisted
        ↓
ReaderAgent 正常响应
        │
        │ 不等待
        ↓
Brain Observation Event
        ↓
BrainProjectionService
```

也就是：

```text
ReaderAgent path
和
Brain maintenance path

解耦
```

这样 Brain 模块失败：

```text
不应该导致
Reflection 保存失败
ReaderAgent 回复失败
阅读流程卡住
```

---

# 8. BrainProjectionService：负责“形成大脑”

这是整个模块的核心服务。

输入：

```text
New Reflection
New Conversation
Book Context
Existing Brain Candidates
```

第一步不是把全部 Brain 塞给 LLM。

而是：

```text
New Reflection
      ↓
BrainRetriever
      ↓
Top relevant existing
Thought / Question / Memory
      ↓
LLM Brain Projection
```

模型输出一个**强类型 Mutation Proposal**。

例如：

```swift
enum BrainMutationProposal {
    case attachEvidence(...)
    case createThought(...)
    case updateThought(...)
    case createQuestion(...)
    case updateQuestion(...)
    case proposeMemory(...)
    case noChange
}
```

LLM 不直接写数据库。

流程：

```text
Observation
    ↓
Candidate Retrieval
    ↓
Brain Synthesizer LLM
    ↓
BrainMutationProposal
    ↓
BrainMutationValidator
    ↓
BrainRepository transaction
    ↓
Embedding refresh
```

再次保持：

> **LLM 提议，代码执行。**

这与 ElsePage 现有 Context Planner 的设计哲学完全一致。

---

# 9. Brain 不应该“每条 Reflection 都创建一个 Thought”

这是一个很重要的质量规则。

否则：

```text
100 Reflection
→ 83 Thought
→ 45 Question
```

「我的大脑」很快就会变垃圾场。

BrainProjection 的默认倾向应该是：

```text
attach > update > create
```

即：

```text
① 能挂到已有 Thought
→ attach

② 是已有 Thought 的变化
→ update

③ 真的是新主题
→ create
```

Question 同理。

可以定义：

```text
createThreshold > attachThreshold
```

宁愿少生成，也不要大量碎片化。

---

# 10. Thought 应该保留“演化”，而不是覆盖旧总结

例如：

```text
Thought
自由意味着责任
```

随着新 Reflection：

```text
旧 statement
“自由就是能够选择。”

新 statement
“自由的核心可能不是选择，
而是承担选择的结果。”
```

不要只：

```text
UPDATE statement
```

最好留下：

```text
BrainItemRevision
```

概念：

```text
brainItemRevisions

itemID
revision
content
createdAt
triggerEvidenceID
```

于是 UI 可以展示：

```text
六月
自由意味着不受限制

       ↓

七月
自由会制造不安

       ↓

八月
自由意味着承担选择
```

这将是「我的大脑」最有价值的产品能力之一。

---

# 11. 和现有 Agent 的接入方式

这里我不建议直接把 Brain 强行塞进所有 Prompt。

应该分两种。

## A. 用户正在 Brain 页面里讨论一个 Item

比如用户打开：

```text
Thought:
自由意味着责任
```

然后点：

> 继续想想

RuntimeContext 加：

```swift
activeBrainContext: {
    id
    kind
    title
    currentContent
}
```

然后：

```text
ContextRoutingInput
+
activeBrainContext
        ↓
Context Planner
```

这个 Thought 本身应该作为：

> **Pinned Context**

确定性进入 Context Bundle。

不要再依赖 Retriever “碰巧搜回来”。

---

## B. 普通阅读过程中发现过去思想相关

例如用户读书时说：

> “这个观点好像和我之前想过的很像。”

Planner 才请求：

```text
Brain Retrieval
```

未来可以增加：

```swift
enum ContextRequest {
    ...
    case brain(BrainContextRequest)
}
```

而：

```swift
enum BrainContextRequest {
    case relatedThoughts(query: String)
    case openQuestions(query: String)
}
```

Memory 仍然可以保持现有独立 source，因为它与 Thought / Question 的权限语义不同。

---

# 12. BrainRetriever

内部可以统一检索 primitive：

```text
lexical
+
persistent embedding
+
RRF
```

但 Query 可以指定：

```text
kinds = thought
kinds = question
kinds = thought + question
```

输出：

```swift
BrainCandidate {
    item
    semanticScore
    lexicalScore
    evidenceSummary
}
```

然后进入现有：

```text
ContextCandidate
→ ContextAssembler
```

而不是另外造一套 Context 拼装系统。

当前 `ContextAssembler` 已经承担不同来源 candidate 的去重、source priority 和预算打包，因此 Brain 应该适配它，而不是复制它。

---

# 13. 最终 Agent Context 链可以变成

```text
                    Context Planner
                           │
            ┌──────────────┼───────────────┐
            ↓              ↓               ↓
        Book           Reflection        Memory
      Retriever         Retriever       Retriever
            │              │               │
            │              └───────┐       │
            │                      │       │
            │                BrainRetriever
            │                 Thought
            │                 Question
            │                      │
            └──────────────┬───────┘
                           ↓
                   ContextCandidate
                           ↓
                   ContextAssembler
              dedup / rank / token budget
                           ↓
                     ContextBundle
                           ↓
                      ReaderAgent
```

注意：

> Brain 是新的 Context Source，不是新的主 Agent。

---

# 14. 「我的大脑」UI

首页我会保持非常简单：

```text
我的大脑

最近的我
────────────────────────
最近反复出现：
自由 · 责任 · 疏离


Thoughts · 正在形成
────────────────────────

自由意味着责任
3 本书 · 8 条思考
最近更新 2 天前

人与他人的距离
2 本书 · 5 条思考


Questions · 还没想明白
────────────────────────

理解是否意味着认同？
出现过 4 次

如果没有确定意义，
行动依据是什么？


Memories · ElsePage 记住的我
────────────────────────

你不喜欢 Agent 不断追问
你通常更关注人物心理
```

首页不是数据库管理器。

---

# 15. Thought Detail

```text
自由意味着责任

当前的我
────────────────────

也许自由真正令人不安的地方，
不是拥有太多选择，而是没有人
能够替你承担选择。


我的变化
────────────────────

Jun
“自由就是不受束缚。”

        ↓

Jul
“自由似乎也带来不安。”

        ↓

Aug
“自由意味着承担选择。”


来自我的阅读
────────────────────

《局外人》
3 Reflections

《存在与虚无》
4 Reflections


相关问题
────────────────────

自由为什么会令人焦虑？


[继续想想]
```

---

# 16. Question Detail

重点不是给答案，而是展示：

```text
问题
↓
为什么它产生
↓
过去在哪里遇到
↓
我尝试过怎样理解
↓
哪些 Thought 正在回答它
```

例如：

```text
理解一个人是否意味着认同他？

Still exploring


它从哪里来
────────────────

《局外人》
“我能够理解他的冷漠，
但理解是不是意味着站在他这一边？”


后来又遇到
────────────────

《人间失格》
...


正在形成的答案
────────────────

人与他人的距离 →

[继续探索]
```

---

# 17. Memory Detail

Memory 页最重要的是**信任**。

例如：

```text
你不喜欢 Agent 连续向你提问

用户明确表达
高可信度

来源
Aug 24 · 一次阅读讨论

Agent 使用方式
用于控制 ReaderAgent 的交互风格

[编辑]
[删除]
```

如果是推断：

```text
你似乎经常从人物心理而非情节理解小说

AI 推断
中等可信度

基于 6 条阅读反思

[确认]
[修改]
[删除]
```

---

# 18. 三者之间最重要的生命周期

我会明确这一条：

```text
Reflection
    │
    ├──────────────→ Question
    │
    ↓
 Thought
    │
    │ repeatedly stable
    │ user confirmed
    ↓
 Memory
```

以及：

```text
Question
    ↓
逐渐被理解
    ↓
Thought
```

但这是**关系**，不是自动数据转换。

比如：

```text
Thought
--derivedMemory-->
Memory
```

两条记录仍然存在。

因为：

```text
Thought：
表达思想形成过程

Memory：
表达 Agent 可以依赖的稳定知识
```

语义完全不同。

---

# 19. 模块边界

为了后续可维护，我会让 Brain 保持这样的依赖：

```text
┌──────────────────────────┐
│ Brain Domain             │
│ Models / Policies        │
└─────────────┬────────────┘
              ↓
┌──────────────────────────┐
│ Brain Persistence        │
│ Repository / Embeddings  │
└─────────────┬────────────┘
              ↓
┌──────────────────────────┐
│ Brain Services           │
│ Projection / Retrieval   │
└─────────────┬────────────┘
              ↓
       ┌──────┴──────┐
       ↓             ↓
    Brain UI    Agent Bridge
```

特别注意：

```text
BrainCore
```

不要：

```text
import ReaderAgent
```

应该由一个 integration layer：

```text
BrainContextProvider
```

把 Brain 转成：

```text
ContextCandidate
```

这样以后 ReaderAgent 重构时，Brain Domain 不受影响。

---

# 20. 我会要求 Agent 分阶段实现

| Phase | 内容                                    | 完成后能力                               |
| ----- | ------------------------------------- | ----------------------------------- |
| 1     | Brain Domain + Persistence            | Thought / Question / Memory 可可靠存储   |
| 2     | Brain UI                              | 我的脑页面可浏览/编辑                         |
| 3     | Evidence / Relation                   | Brain Item 有来源和关系                   |
| 4     | Persistent Embedding + BrainRetriever | Thought / Question 可语义检索            |
| 5     | Agent Bridge                          | Brain Context 进入现有 ContextAssembler |
| 6     | BrainProjectionService                | Reflection 自动更新 Brain               |
| 7     | Revision / Evolution                  | Thought 时间演化                        |
| 8     | Evaluation / Observability            | 可验证 Brain 质量                        |

我尤其不会让 Agent 第一轮就同时做：

```text
DB
+
UI
+
LLM synthesis
+
Graph
+
Retriever
+
Agent integration
```

否则很难知道到底哪层设计错了。

---

## 最终架构

我希望最后形成的是：

```text
                     ElsePage
                        │
               ┌────────┴────────┐
               │                 │
          Reading World      Personal Brain
               │                 │
        Book / Reflection   Thought
                            Question
                            Memory
               │                 │
               └────────┬────────┘
                        ↓
                  Context Planner
                        ↓
               Source-specific Retrieval
                        ↓
                  ContextCandidate
                        ↓
                  ContextAssembler
                        ↓
                    ReaderAgent
```

当前 ElsePage 已经有 `reflectionConnections`、`memories`、`agentResponseEvidence`、`routingTraces` 等基础设施，所以 Brain 并不是一个孤立的新功能，而很自然地可以成为现有 Context Engineering 的上层个人知识模型。

我认为这里最值得坚持的三个架构原则是：

> **Evidence 是事实，Brain Item 是解释。**

> **Thought 可以变化，Question 可以悬而未决，Memory 才是 Agent 可以稳定依赖的知识。**

> **Brain 负责形成个人思想结构，Context Engineering 负责决定其中哪些内容应该进入这一次 Agent 上下文。**

这样设计以后，「我的大脑」既能成为一个很强的用户可见产品模块，又不会把 UI、Memory、RAG、Agent Router 搅成一个难以维护的大系统。


# ReadLoop Reader Help 临时选句答疑 Spec

> 状态：Proposed（2026-09-13）
> 分支：`codex/reader-help-spec`
> 适用范围：EPUB 阅读器内的选中文字临时答疑
> 核心决策：**显式触发、默认临时、书籍内上下文、CARC 防剧透、单次回复模型调用、显式保存才持久化**

---

## 1. 摘要

Reader Help 是阅读器内的轻量 Agent 能力：用户读到一句令自己疑惑的话时，主动选中并点击“问”，获得一段有上下文依据、可继续追问的临时解答。

它不是第二个 Reflection 流程，也不是通用聊天入口。Reader Help 的目标是帮助用户跨过理解障碍，然后回到阅读；Reflection 的目标则是让用户输出并沉淀自己的思考。

核心边界：

- Agent 只响应用户主动选句，不自动解释、不主动弹窗。
- 默认不持久化问答；只有用户明确“存为笔记”时才触碰数据库。
- 只使用当前选段、已读附近文本和 read-so-far 书籍证据。
- 严格沿用 CARC 防剧透策略，不读取后续 child、后续 resource 或 `textAfter`。
- v1 不调用过去 Reflection、Brain、Memory 或 Reader Profile。
- 复用现有 Agent Runtime 的模型执行、上下文压缩、检索和引用校验，但不复用 Reflection 的产品编排与持久化生命周期。
- 每一轮生成只调用一次回复模型；不运行 Reflection 的 LLM routing。

---

## 2. 产品定位

### 2.1 用户 Job

> 我在阅读中看到一句话，不确定它在这里是什么意思。我希望不离开阅读上下文，用最少操作获得一个直接、可靠、不过度展开的解答。

典型场景：

- 词语或句子在当前语境中的含义不明确。
- 代词的指代对象不清楚。
- 某个论证的前提、结论或转折关系没有看明白。
- 作者提到一个概念，但当前解释不足。
- 用户有一个具体疑问，需要 Agent 基于已读内容回答。
- 第一轮回答后，用户需要追问一到两次。

### 2.2 与 Reflection 的区别

| 维度 | Reader Help | Reflection Agent |
|---|---|---|
| 触发 | 选中一句话后主动点击“问” | 主动反思、会话结束或追问 |
| 目标 | 消除理解障碍 | 帮助用户形成和沉淀思考 |
| 默认数据生命周期 | 临时，离开 Reader 即丢弃 | 持久化，进入 Journal/Memory 闭环 |
| 默认上下文 | 当前选段 + read-so-far 书籍证据 | 阅读区间、Reflection、长期记忆、书籍证据 |
| 输出风格 | 直接解答、短、少提问 | 克制回应、可提炼、可追问 |
| 模型调用 | 每轮一次回复调用 | routing + reply，并可能触发 Brain projection |
| UI | 轻量底部面板 | Session Reflection Sheet |

### 2.3 对应 PRD 不变量

- **P1 Don't interrupt reading**：只有用户主动选句后才出现；不自动解释。
- **P3 Agent extends thinking**：帮助澄清，不替用户生成读后感或标准答案。
- **P5 Local-first**：默认不持久化；请求仅发送完成当前解答所需的最小上下文。
- **P9 Thinking is the product moat**：临时问答不能污染 Reflection、Journal、Memory 与成就指标。
- PRD §10.2：Agent 可以出现在阅读器中，但“聊天页”不是唯一容器。
- PRD §13.2：先本地检索、压缩，再发送必要文本；UI 可解释本次使用了什么。

---

## 3. In Scope / Out of Scope

### 3.1 In scope

- 选中文字后的“问”入口。
- 无输入时的一键“解释这段”。
- 用户输入具体问题。
- 轻量底部面板内的流式回答。
- 面板内的有限轮次追问。
- read-so-far 本地检索和引用校验。
- 基于当前选段 locator 的 CARC 边界。
- 显式“存为笔记”和“复制”。
- 内存态会话与取消。
- 内容无关的 DEBUG 性能指标。
- 自动化测试与真机验收清单。

### 3.2 Out of scope

- 自动解释所选文字或整页内容。
- 独立的全局 Chat Tab。
- 持久化临时问答历史。
- 新增数据库表或迁移。
- 写入 Journal、Memory、Brain、Reader Profile、Streak 或 Achievement。
- 调用过去 Reflection、长期记忆或 Brain。
- 全书范围和未读章节检索。
- 语音输入和音频录制。
- Tool calling、多 Agent、后台任务或开放式 agent loop。
- 自动把回答提升为 Reflection。
- 替代现有 Reflection 会话。

---

## 4. 用户交互

### 4.1 入口

在现有文字选区工具栏中新增一个“问”按钮，与高亮、笔记、复制、反思并列。

点击后：

1. 立即捕获当前 `ReaderSelectionContext`，包括 locator、文字和屏幕 frame。
2. 关闭系统选区菜单，但保留已捕获的值。
3. 打开轻量 `ReaderHelpSheet`。
4. 不跳转到 `SessionReflectionSheet`，不创建 Reflection。

### 4.2 首屏

面板顶部固定展示：

- 标题：“问 Agent”或“这句怎么理解”。
- 当前选段的短引用，建议最多 3 行。
- 书内位置提示，例如章节名或百分比。

首屏提供：

- 主按钮：“解释这段”。
- 文本输入框：占位文案“想知道什么？”
- 发送按钮。

若用户未输入问题而点击“解释这段”，构造默认问题：

```text
请解释这段文字在当前上下文中的意思。
```

若用户直接输入问题，则发送用户问题。选段本身始终作为不可省略的上下文。

### 4.3 回答展示

- 回答以流式文本呈现。
- 显示状态包括准备中、生成中、完成、失败、已取消。
- 引用若存在，以轻量来源标记展示；点击可回到对应原文。
- 完成后提供“继续追问”“复制”“存为笔记”。
- 不允许在面板内编辑 Agent 的回答，也不把回答伪装成用户原始表达。

### 4.4 追问

- 用户可以继续输入 1–3 轮问题。
- 追问只携带最多 6 条最近消息，并按字符预算裁剪。
- 追问题味与第一问走同一条 Reader Help pipeline。
- 每轮仍只调用一次回复模型。
- 对话保存在 `ReaderHelpModel` 内存中，不写数据库。

### 4.5 关闭与生命周期

- 关闭面板会取消正在进行的请求。
- 同一 ReaderScreen 生命周期内，关闭后再次打开可恢复最近一次 help thread。
- 选择另一句话时创建新的 help session。
- 退出阅读器、App 被系统终止或清理内存后，未保存内容丢失。
- 不提供“历史问答”列表。

### 4.6 显式保存

“存为笔记”是 v1 唯一持久化入口：

- 若选段 locator 与已有 Highlight 相同，则把内容保存为该 Highlight 的 Note。
- 否则保存为 locator 上的独立 Note。
- 保存格式建议：

```text
问：<用户问题，若为默认解释可省略>

Agent：<最终完整回答>
```

- 流式未完成时禁用“存为笔记”。
- 同一 help thread 的同一回答只能保存一次；保存后按钮显示“已保存”。
- 保存失败必须可见，不静默丢弃。
- v1 不自动保存 Agent 引用，也不创建 Reflection 或 Memory。

### 4.7 视觉与无障碍

- 使用底部 sheet，建议 `.presentationDetents([.medium, .large])`，初始 `.medium`。
- 不覆盖正文持续动画；面板关闭后阅读器状态保持不变。
- 所有按钮满足 44pt 点击区域。
- VoiceOver 需读出选段、流式状态、错误和保存结果。
- Dynamic Type 下选段预览和输入区不能互相遮挡。
- 键盘出现后不得重复引入会话区回落或强制滚动问题。

---

## 5. 架构决策

### 5.1 复用与不复用

**复用：**

- `Sources/AgentRuntime/AgentExecutor.swift`
- `Sources/AgentRuntime/ModelContracts.swift`
- `Sources/RetrievalCore/RetrievalModels.swift` 中的 `ReaderAgentContextBuilder`
- `Sources/ContextEngineering/ContextAssembler.swift`
- `Sources/ReaderAgent/AgentCitationValidator.swift`
- 现有 `ModelClientFactory`、Provider 错误分类和 BYOK 配置
- CARC 阅读边界和本地引用校验

**不复用为入口：**

- `ReaderAgent.respond(to:)`
- `ReaderAgent.continueDiscussion(...)`
- `SessionReflectionSheet`
- `SessionReflectionModel`
- `ReflectionRepository`
- `BrainProjectionService`
- `RoutingTraceRepository`
- Reflection 专属 Prompt 和消息持久化

原因：

- `ReaderAgent` 的现有公开入口要求一条持久化 Reflection。
- 当前 pipeline 会追加 Agent message、保存 connection、trace 和 Brain projection。
- 当前流程包含 Reflection routing model call，对临时答疑过重。
- 为临时答疑伪造 Reflection 会污染产品数据并造成架构耦合。

### 5.2 建议模块边界

不新增 Package target。首版把新类型放在 `ReaderAgent` target 内，按独立职责拆分。

建议新增：

- `Sources/ReaderAgent/ReaderHelp.swift`
- `Sources/ReaderAgent/ReaderHelpPolicy.swift`
- `Sources/ReaderAgent/ReaderHelpService.swift`
- `App/Reader/ReaderHelpModel.swift`
- `App/Reader/ReaderHelpSheet.swift`

建议修改：

- `App/Reader/AnnotationUI.swift`：增加选句工具栏入口。
- `App/Reader/ReaderModel.swift`：暴露帮助 service 与捕获的 selection，不承载回答状态。
- `App/Reader/ReaderScreen.swift`：呈现轻量 help sheet。
- `App/Library/LibraryModel.swift`、`App/AppModel.swift`：将 service 注入 Reader 生命周期。

### 5.3 依赖方向

```text
ReaderHelpSheet
      ↓
ReaderHelpModel (@MainActor, ephemeral)
      ↓
ReaderHelpService (non-main isolated)
      ├── ReaderHelpPolicy
      ├── ReaderAgentContextBuilder
      ├── ContextAssembler
      ├── AgentExecutor
      └── AgentCitationValidator

AgentExecutor
      ↓
ModelClientFactory
      ↓
ModelProviders
```

`ReaderHelpService` 不得依赖：

- `ReflectionRepository`
- `BrainRetriever`
- `BrainProjectionService`
- `RoutingTraceRepository`
- SwiftUI / UIKit
- Readium 具体类型

### 5.4 数据流

```text
ReaderSelectionContext
        ↓
ReaderHelpRequest
        ↓
ResolvedReadingBoundary + Book context
        ↓
ReaderHelpPolicy / AgentInput
        ↓
AgentExecutor (1 次回复模型调用)
        ↓
AgentCitationValidator
        ↓
AsyncStream<ReaderHelpEvent>
        ↓
ReaderHelpModel
        ↓
ReaderHelpSheet
```

### 5.5 为什么不抽到独立 target

Reader Help 暂时与 Reader Agent 共享检索、上下文装配和引用校验。额外 target 会迫使这些共享类型重新导出或搬迁，增加模块复杂度，而不是降低耦合。

真正需要拆 target 的信号是：

- Reader Help 拥有独立于 Reader Agent 的发布或复用需求；
- 两条流程出现超过一个有实质价值的共享编排层；
- ReaderAgent target 的依赖图无法通过文件级隔离保持清晰。

在此之前，保持“同 target、无 Reflection repository 依赖、类型与 policy 分离”更合适。

---

## 6. 领域契约

### 6.1 Request

建议值类型：

```swift
public struct ReaderHelpRequest: Hashable, Sendable {
    public let bookID: BookID
    public let anchor: BookLocator
    public let selectedText: String?
    public let question: String
    public let recentTurns: [ReaderHelpTurn]
}
```

约束：

- `anchor` 必须来自用户选中文字时的 locator，不能使用滚动后的 viewport locator。
- `selectedText` 只用于展示与 Prompt；若为空，从 `anchor.textHighlight` 读取。
- `question` 去除首尾空白后不能为空。
- 选段建议上限 1,000 中文字；超过时要求用户缩小选区或输入具体问题，不自动截断并假装完整。
- 问题建议上限 500 字。
- `recentTurns` 最多 6 条，优先保留最近消息。

### 6.2 Turn

```swift
public struct ReaderHelpTurn: Hashable, Sendable {
    public enum Role: Sendable { case user, agent }
    public let role: Role
    public let content: String
}
```

### 6.3 Event

```swift
public enum ReaderHelpEvent: Equatable, Sendable {
    case started
    case contextPrepared(ReaderHelpContextSummary)
    case textDelta(String)
    case citationsValidated(ReaderHelpProvenance)
    case completed(ReaderHelpResponse)
    case cancelled
    case failed(ReaderHelpFailure)
}
```

事件语义：

- `.started`：边界与轻量上下文准备开始。
- `.contextPrepared`：说明是否带入选段附近文本、书籍证据数量、是否 fail-closed；不暴露内部 Prompt。
- `.textDelta`：模型返回的可见增量。
- `.citationsValidated`：最终采用的本地证据和引用。
- `.completed`：包含完整文本与本地生成本轮 id，不代表已持久化。
- `.cancelled`：正常状态，不显示为错误。
- `.failed`：可恢复错误类型。

### 6.4 Failure

```swift
public enum ReaderHelpFailure: Error, Equatable, Sendable {
    case providerNotConfigured
    case invalidSelection
    case emptyQuestion
    case selectionTooLong
    case runtime(AgentFailure)
    case emptyResponse
}
```

`AgentFailure` 保持现有语义，不增加 UI 无法处理的细分错误。

### 6.5 Response

```swift
public struct ReaderHelpResponse: Hashable, Sendable {
    public let id: UUID
    public let content: String
    public let citations: [AgentCitation]
}
```

`id` 只用于当前内存会话、重试和 UI 状态，不写入数据库。

---

## 7. 执行 Pipeline

### 7.1 步骤

1. 校验 `ReaderHelpRequest`。
2. 通过 `ReaderAgentContextBuilder.readingBoundary(for:locator:)` 解析 `ResolvedReadingBoundary`。
3. 构造检索 query：优先使用用户问题；若为默认解释，则使用选段文字。
4. 调用 `nearbyText(...)` 获取允许进入 Prompt 的附近文本。
5. 在边界可用且索引可用时调用 `build(...)`：
   - `scope: .readSoFar`
   - `evidenceLimit: 2`
   - `characterBudget: 2_000`
6. 使用 `ContextAssembler` 组装 near/deep evidence：
   - `previousReflection: nil`
   - `brainCandidates: []`
7. 构造 `ReaderHelpPolicy.input(...)`。
8. 调用 `AgentExecutor`，设置 Reader Help 独立预算。
9. 按事件流输出 `.textDelta`。
10. 完成后调用 `AgentCitationValidator`。
11. 输出 `.citationsValidated` 与 `.completed`。
12. 不执行任何数据库写入。

### 7.2 模型预算

建议固定：

```swift
ExecutionBudget(
    maxModelCalls: 1,
    maxWallTime: .seconds(30),
    maxOutputTokens: 600
)
```

理由：

- 临时答疑不应运行 routing 模型。
- 默认回答目标为 120–250 中文字。
- 600 output tokens 为引用块和短追问留出余量，同时限制失控长文。
- 30 秒是网络异常上界；用户可以随时关闭面板取消。

### 7.3 上下文预算

建议上限：

| 来源 | 预算 |
|---|---:|
| 选中文字 | 1,000 字 |
| nearby / active chunk | 1,000 字 |
| 书籍证据 | 2,000 字 |
| 追问历史 | 800 字 |
| 模型输入总预算（不含 system prompt） | 4,800 字 |

规则：

- 选段与 nearby 无论如何优先保留。
- 书籍证据最多 2 条。
- 最近追问从后向前填充，完整消息放不下时停止。
- 不把整本书、整章未读内容或与问题无关的阅读记录发送给 Provider。
- UI 的“本次使用了什么”只展示来源类型、数量和可点击证据，不展示系统 Prompt。

### 7.4 不运行 LLM routing

Reflection 的 `ContextRoutingInput` + `LLMReaderContextRouter` 用于判断意图和来源。Reader Help 的 v1 场景足够窄，使用确定性 policy：

- `ReflectionIntent`: `.conceptualQuestion` 或本地 help intent。
- `NearbyPassagePlan`: `.include`，边界可用时。
- `RetrievalPurpose`: `.clarifyCurrentPassage`。
- `PreferredBookScope`: `.readSoFar`。
- `ResponseLength`: `.short` 或 `.medium`。
- `allowQuestion`: `false`。

如果未来证明“解释、找前文、查事实、连接旧想法”需要不同的检索策略，再增加确定性分支或复用 router。首版不为了可能的未来需求增加一次模型往返。

---

## 8. 上下文与防剧透

### 8.1 绝对规则

- 选段本身属于用户已经看到的内容，允许进入 Prompt。
- `locator.textBefore` 允许进入 nearby。
- `locator.textAfter` 永远不得进入 Prompt。
- 只有 CARC 边界解析成功时，才允许补全 active retrieval child。
- active child 之后的 child 永远拒绝。
- 后续 resource 永远拒绝。
- citation 校验必须使用同一个 resolved boundary。
- `progression == nil` 时必须 fail-closed：允许选段和 `textBefore`，不允许 broad retrieval。

### 8.2 CARC 示例

```text
当前 resource 有 6 个 child，阅读 cursor = 3.5

允许进入 Prompt：child 1、2、3、完整 child 4
拒绝进入 Prompt：child 5、6
```

```text
cursor 恰好位于 3.0

允许：child 1、2、3
拒绝：child 4、5、6
```

Reader Help 必须调用与 Anti-Spoiler Spec 相同的 boundary 和 validator，不能复制一份近似逻辑。

### 8.3 无索引降级

若书籍索引未 ready：

- 仍允许使用选段、`textHighlight` 和 `textBefore`。
- 不执行书籍 RAG。
- 回答必须明确基于目前可见文本或一般知识。
- 不因为缺少索引而回退为全书检索。

### 8.4 上下文来源优先级

```text
用户选中的句子
    > 当前 active child / textBefore
    > read-so-far 书籍证据
    > 模型的一般知识
```

模型一般知识不能冒充书中原文。若没有本地证据，回答应使用“这可能是在说”“一种理解是”，并说明不能确认作者原意。

---

## 9. Prompt 与回答策略

Reader Help 不复用 `ReaderAgentSystemPrompt.v3`。新增独立 system prompt，核心约束：

- 直接回答用户对当前选段的疑问。
- 先解释当前语境，再补充必要的一般含义。
- 区分书中原文、用户问题、Agent 推断。
- 不确定时明确说不能确认。
- 不剧透当前位置之后的内容。
- 默认 120–250 中文字，最长不超过两个自然段。
- 除非用户明确要求，不引入外部作者、理论或长篇背景。
- 不主动提出反思问题；目标是解除疑惑并回到阅读。
- 不泛泛赞美用户，也不评价用户的阅读能力。
- 引用原文时必须来自提供的 evidence。
- 无法确认原文时不使用引号伪造引用。

建议行为：

| 用户困惑 | 回答策略 |
|---|---|
| 词语/短句含义 | 先给当前语境含义，再给必要的词典义 |
| 代词指代 | 明确最可能指代对象和依据，保留不确定性 |
| 论证关系 | 只解释前提、转折、结论，不替作者辩护 |
| 文化/历史引用 | 仅在有证据或稳定共识时简述 |
| 多义文本 | 给出 2 个以内主要解释，说明各自依据 |
| 可能剧透的问题 | 拒绝回答后文事实，只基于已读范围解释 |

若回答引用了本地证据，继续使用现有 `[E1]` 标记和 `---CITATIONS---` 结构化块。Reader Help 可以复用 `AgentCitationValidator`，但展示上应比 Reflection 更轻量。

---

## 10. 状态机

`ReaderHelpModel` 至少包含以下状态：

```text
idle
  → preparing
  → streaming
  → completed

preparing/streaming
  → cancelled

preparing/streaming
  → failed

failed/completed
  → preparing      （追问或重试）
```

要求：

- `preparing` 与 `streaming` 期间只允许一个活动 Task。
- 新一轮追问前取消或等待上一轮结束。
- 关闭面板取消活动 Task。
- 选择新 anchor 时清空当前 thread，创建新 session。
- `.cancelled` 不进入错误 UI。
- 重试使用新的内存 message id；不存在数据库幂等问题。
- 面板刷新不得因为每个 token 重建整个 ReaderScreen。

---

## 11. 错误与离线行为

| 状态 | 用户可见行为 |
|---|---|
| 未配置 Provider | 保留阅读器功能；入口可禁用或提示先配置 Provider |
| 网络失败 | 面板显示可重试错误，不离开阅读器 |
| 认证失败 | 复用现有 Provider 错误文案与设置引导 |
| 限流/Provider 不可用 | 显示可稍后重试状态 |
| 空回答 | 视为失败，不显示“完成” |
| 用户取消 | 静默取消，不弹 Alert |
| 边界无法解析 | 允许仅基于可见选段的回答，不进行 RAG |
| 选段过长 | 不自动发送，提示缩小选区或输入具体问题 |
| 保存笔记失败 | 保留本轮回答，显示错误和重试入口 |

离线时 EPUB 阅读、位置、Highlight、Note 不应受 Reader Help 影响。

---

## 12. 隐私、成本与性能

### 12.1 隐私

每次请求只允许发送：

- 用户当前选中的文字；
- 允许的 `textBefore` / active child；
- 最多 2 条 read-so-far 书籍证据；
- 用户问题；
- 最多 6 条临时追问。

禁止发送：

- 整本书；
- 未读章节；
- 后续 EPUB resource；
- 过去 Reflection；
- Brain、Memory、Reader Profile；
- 与当前问题无关的文件或日志。

默认无持久化，因此无需新增“删除 Reader Help 历史”入口。保存为 Note 后，内容按现有 Note 删除与数据导出规则处理。

### 12.2 成本

- 每轮最多一次回复模型调用。
- 不做 LLM routing。
- 默认最多 2 条证据。
- 用户关闭面板立即取消请求。
- 相同问题不自动重试，避免不可控计费。
- 可选内存缓存不得跨 Provider、书籍索引版本或阅读边界复用。

### 12.3 性能

目标：

- 点击“问”后面板立即可见，不等待网络。
- 状态切换和输入不阻塞主线程。
- 流式增量更新使用现有缓冲/去抖思路，避免每个 token 触发整棵树重排。
- 面板关闭取消后不再更新 UI。
- 键盘弹出不得引入新的回落、跳动或强制滚动。

网络首 token 延迟由 Provider 决定，不以绝对时间作为硬断言；必须记录并验证“无本地阻塞、单次模型调用、取消及时”。

---

## 13. 可观测性

Reader Help 必须进入现有 DEBUG 测试闭环，但默认不持久化 trace。

建议内容无关指标：

- `readerHelp.present`
- `readerHelp.start`
- `readerHelp.firstVisibleDelta`
- `readerHelp.complete`
- `readerHelp.cancel`
- `readerHelp.fail`
- `readerHelp.context.evidenceCount`
- `readerHelp.context.nearbyIncluded`
- `readerHelp.runtimeMs`
- `readerHelp.outputCharacters`
- `readerHelp.modelCalls`

约束：

- 不记录完整问题、回答、选段或引用正文。
- 不做 ReflectionID 级持久 trace。
- 若未来需要诊断记录，必须单独定义保留期和用户清理入口。
- UI 的“本次使用”仅展示来源摘要和可跳转证据。

---

## 14. 测试与验收

### 14.1 自动化测试

**Domain / Policy**

- 默认问题正确生成。
- 空问题、空选段、超长选段被拒绝。
- 追问历史按预算倒数裁剪。
- Reader Help 不要求 Reflection 存在。
- Reader Help 构造依赖中不存在 Reflection/Brain repository。

**Anti-Spoiler**

- cursor 3.5 时仅允许 active child 完整进入。
- cursor 3.0 时不允许下一 child。
- `textAfter` 永不进入 Prompt 或 context summary。
- 无 progression 时 broad retrieval fail-closed。
- citation 越界时被拒绝。
- 无索引时降级为选段/textBefore，不执行全书检索。

**Runtime**

- Fake model 的 delta 按顺序映射为 `ReaderHelpEvent`。
- 每轮只调用一次 `AgentExecutor`。
- Provider 未配置、认证、限流、网络、空回答均映射为正确状态。
- 取消 Task 后不再发出完成事件。
- 流式未完成不能触发保存。

**Persistence**

- 普通问答不写 Reflection、Journal、Brain、Memory、Achievement。
- “存为笔记”才调用现有 Note 保存接口。
- 保存幂等，不重复生成 Note。
- 保存失败不丢当前内存回答。

**UI Model**

- 一个 anchor 对应一个内存 thread。
- 切换 anchor 创建新 thread。
- 关闭再打开可恢复当前 ReaderScreen 内 thread。
- 退出 Reader 后内存状态释放。

### 14.2 自动化命令

代码实施后必须执行：

```bash
swift test
git diff --check
```

当前 spec-only 变更只需：

```bash
git diff --check
```

### 14.3 真机验收

由用户执行 xcodebuild、安装和手势测试：

1. 长按选句后出现“问”入口。
2. 点击“问”立即打开轻量面板。
3. “解释这段”能流式显示回答。
4. 输入具体问题与追问正常。
5. 键盘弹出、输入和收起无跳动。
6. 回答引用可跳回原文。
7. cursor 3.5 / 3.0 无后续内容泄漏。
8. 关闭面板会取消请求。
9. 重开同一 thread 的临时状态符合预期。
10. 退出 Reader 后临时内容不存在。
11. 存为 Note 后可从标注列表恢复。
12. 未配置 Provider 不影响阅读器。
13. 后台、旋转、Dynamic Type 和 VoiceOver 不破坏面板。

---

## 15. 分阶段实施

### Phase 1：Domain + Policy

- 新增 `ReaderHelpRequest`、`ReaderHelpTurn`、`ReaderHelpEvent`、`ReaderHelpFailure`、`ReaderHelpResponse`。
- 新增 `ReaderHelpPolicy` 和独立 system prompt。
- 不接入 UI。
- 覆盖请求校验、预算和 Prompt 单元测试。

### Phase 2：Service Pipeline

- 新增 `ReaderHelpService`。
- 复用 context builder、assembler、executor、citation validator。
- 不注入 Reflection/Brain repository。
- 使用 fake model 覆盖流式、取消、错误和 CARC。
- 验证每轮只有一次回复模型调用。

### Phase 3：Reader UI

- 选句工具栏增加“问”。
- 新增 `ReaderHelpModel` 与 `ReaderHelpSheet`。
- 接入临时 thread、追问、复制、存为 Note。
- 增加 DEBUG 指标和主线程性能检查。

### Phase 4：真机验收

- 用户完成手势、键盘、边界、取消、保存与退出生命周期验收。
- 不通过则只改 Reader Help 接缝，不回退现有 Reflection Agent。

### Phase 5：按证据决定是否抽共享引擎

只有在 Reader Help 与 Reflection Agent 出现真实重复且难以独立维护时，才抽取共享的 stateless evidence/execution engine。首版不先做大规模 `ReaderAgent` 重构。

---

## 16. 不变量清单

实施完成后必须同时满足：

- [ ] 只有用户主动选句后才调用 Agent。
- [ ] 默认没有数据库写入。
- [ ] 不创建 Reflection，不写 Journal、Memory、Brain、Achievement。
- [ ] v1 不读取过去 Reflection、Brain 或 Reader Profile。
- [ ] 每轮只调用一次回复模型。
- [ ] 使用选段 locator 解析 CARC 边界。
- [ ] `textAfter` 永不进入模型。
- [ ] 后续 child 与 resource 永不进入模型或引用。
- [ ] 无 progression 时 broad retrieval fail-closed。
- [ ] 面板关闭取消请求。
- [ ] 只有“存为笔记”才持久化。
- [ ] 退出 Reader 后临时问答不残留。
- [ ] Provider 故障不影响 EPUB 阅读。
- [ ] Prompt 中不出现完整系统提示、内部 trace 或未选中的隐私上下文。

---

## 17. 已知风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| 复用 `ReaderAgent` 业务壳 | 临时问答污染 Reflection | 新建独立 service，不注入 Reflection repository |
| 为临时问答新表 | 数据与架构扩张 | v1 内存态，仅 Note 显式保存 |
| routing 多一次模型调用 | 延迟和成本偏高 | 确定性 policy，一跳生成 |
| 选段 locator 不准确 | 防剧透边界错误 | 使用 selection locator；无 progression fail-closed |
| 追问上下文过长 | 成本上升、重点漂移 | 最多 6 条、800 字预算 |
| Sheet 与键盘引入回归 | 阅读交互抖动 | 独立轻量面板，复用性能闭环测试 |
| 回答变成通用百科 | 偏离阅读上下文 | Prompt 强制先语境、限外部知识 |
| 未来需要个人记忆 | 当前实现受限 | 作为独立扩展评估，不提前耦合 Brain |

---

## 18. 最终建议

Reader Help 应作为一个明确的轻量产品用例落地，而不是把现有 `ReaderAgent` 扩成多入口 God object。

首版最小闭环：

```text
选中一句
  → 点击“问”
  → 默认解释或输入问题
  → 基于当前书籍已读上下文流式回答
  → 可追问
  → 可复制或显式存为 Note
  → 关闭/退出即丢弃未保存内容
```

这样才能同时满足：

- 阅读中不被打扰；
- 临时问题快速得到解答；
- Agent 复用现有 Runtime 能力；
- Reflection 数据与产品闭环不被污染；
- 架构新增面保持在 Reader Help 的清晰接缝内。

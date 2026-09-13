# ReadLoop Anti-Spoiler Boundary Spec

> 状态：Implemented（2026-09-13，待提交/真机复验）
> 分支：`codex/anti-spoiler-audit`
> 适用范围：Reader Agent 的本地 RAG、nearby passage、small-to-big expansion、citation validation
> 决策：**Complete Active Retrieval Chunk（CARC，补全当前检索 child）**

---

## 1. 决策摘要

边界不再按字符精确截断，而是允许“补全用户当前已经进入的那个 retrieval child”。

示例：

```text
当前章节有 6 个 retrieval child
阅读 cursor = 3.5

允许：child 1、2、3 + child 4
禁止：child 5、6
```

这里的 child 4 不是“额外解锁的下一段”，而是用户当前正在阅读的段落。其尚未读完的尾部可以整体进入 Agent 上下文，用来避免句子、论证或段落被切半。

但必须区分两种情况：

```text
cursor = 3.5  → 允许 1、2、3、4
cursor = 3.0  → 允许 1、2、3，不允许 4
```

即：

- cursor 落在 child 内部：补全 active child。
- cursor 恰好位于 child 边界：只允许已经完成的 child，不自动进入下一 child。

---

## 2. 范围

### In scope

- 当前章节已读内容的召回。
- 当前章节 active child 的完整保留。
- 当前章节后续 child 的排除。
- 后续章节和后续 EPUB resource 的排除。
- lexical、semantic、rerank、small-to-big expansion 的最终边界一致性。
- nearby passage 中 `textAfter` 的边界裁剪。
- citation validation 的边界一致性。
- 边界相关的自动化测试和可观测性。

### Out of scope

- 不改变模型 Prompt 的“不要剧透”行为；边界必须由代码强制，不能依赖模型。
- 不建设整本书的“永久已读集合”。
- 不追踪跨设备阅读进度。
- 不提供逐字符 progression 映射。
- 不改变 chunk 算法本身，除非需要补足 active child 解析接口。

---

## 3. 术语

### Read cursor

当前 Reflection 或追问对应的 `BookLocator` 位置，包含：

- `resourceOrdinal`
- `chapterID`（如果索引可用）
- `progression`
- 可选 `textBefore`、`textHighlight`、`textAfter`

### Retrieval child

由 `StructureAwareChunker` 生成的约 350 字、最大 600 字的检索单元。它拥有 FTS 和 embedding，是边界策略的最小粒度。

### Parent evidence window

由 small-to-big 从 retrieval children 组合出的约 900–1400 字证据窗口。Parent 是上下文和 citation 的展示单位，但不能作为“整块放行”的边界单位。

### Active child

满足以下条件的唯一 child：

```text
child.startProgression < cursor.progression < child.endProgression
```

- 更早完成的 child 不属于 active child。
- cursor 正好在边界上时没有 active child。
- active child 之后的 child 永远禁止。

### ResolvedReadingBoundary

由数据库解析出的运行时边界：

```text
ResolvedReadingBoundary {
  resourceOrdinal
  chapterID?
  progression
  activeChildID?
  activeEndProgression?
  policy = completeActiveChunk
}
```

`progression` 缺失时不能解析为“允许整个 resource”，必须 fail-closed。

---

## 4. 当前实现证据

当前主边界是：

```text
ReadingBoundary(resourceOrdinal, progression)
```

定义见 `Sources/RetrievalCore/RetrievalModels.swift`。

正常路径行为：

1. 更早 resource：允许。
2. 当前 resource：`chunk.startProgression <= progression` 允许。
3. 后续 resource：排除。

对应实现：

- `ReaderAgentContextBuilder.build` 解析 boundary。
- `GRDBBookIndexRepository.lexicalSearch` 在 SQL 中过滤。
- `LocalBookHybridRetriever.retrieve` 对 semantic candidate 再过滤。
- `SmallToBigExpander` 对跨边界窗口做尾部裁剪。
- `AgentCitationValidator` 对书籍引用重新检查 boundary。
- `ReaderAgent.run` 将 `locator.textBefore/textHighlight/textAfter` 拼成 nearby passage。

### 已覆盖的正常行为

- 后续 resource 的 chunk 会被 lexical search 排除。
- `scope: currentResource` 会限制到当前 resource。
- small-to-big 正常路径会裁剪跨越 boundary 的尾部。
- citation 指向 boundary 外的 chunk 会被拒绝。

### 当前缺口

| 缺口 | 影响 | 证据 |
|---|---|---|
| `progression == nil` 对当前 resource fail-open | 可能放行整个当前 resource | `ReadingBoundary.contains` 与 lexical SQL 的 `?? 1` |
| `textAfter` 不经过 boundary 裁剪 | nearby passage 可能带入未来文本 | `ReaderAgent.run` 拼接 locator 三段文本 |
| expander 失败后使用原始 chunk | 起点在边界内、尾部越界的 chunk 可能整体进入 | `RetrievalServices.retrieve` fallback |
| `currentSection/currentChapter` 折叠成 `currentResource` | 边界精度退化为 resource + progression | `ReaderAgent.run` scope 映射 |
| 只比较 chunk 起点 | 无法区分“已完成 child”与“active child” | `ReadingBoundary.contains(_ chunk:)` |
| `textAfter` 没有 active child 上限 | 可能从 active child 进入下一个 child | nearby candidate 组装 |

---

## 5. 规范行为

### 5.1 允许集合

对当前书和当前 read cursor，允许以下内容进入 Agent：

1. 更早 resource 的全部已索引内容。
2. 当前 resource 中已经完成的 retrieval child：
   `child.endProgression <= cursor.progression`
3. 当前 resource 中唯一的 active child：
   `child.startProgression < cursor.progression < child.endProgression`
4. active child 的完整文本，即使其尾部超过 cursor。
5. active child 所属 parent window 中，截止到 active child 的内容。

### 5.2 禁止集合

以下内容绝对禁止进入 Agent：

1. active child 之后的所有 sibling。
2. 当前 resource 中 `startProgression > activeChild.endProgression` 的内容。
3. 后续 resource 或后续 chapter。
4. 无法解析 active child 时，所有 `endProgression > cursor` 的内容。
5. progression 缺失时，当前 resource 的宽泛 RAG 结果。
6. nearby passage 中越过 active child 结尾的 `textAfter`。
7. citation 指向上述禁止内容。

### 5.3 精确示例

#### cursor = 3.5

```text
完成：1、2、3
active：4
禁止：5、6
```

#### cursor = 3.0

```text
完成：1、2、3
active：无
禁止：4、5、6
```

#### cursor 位于两个 child 之间

如果 cursor 落在结构空白或没有 child 覆盖：

```text
允许：已完成的 child
禁止：下一个 child
```

#### cursor 与 chapter 边界的关系

如果 active child 跨 chapter：

- chapter 边界优先。
- active child 只能保留到当前 chapter 结束。
- 不允许通过补全 active child 进入下一 chapter。

---

## 6. Read Access Policy

所有数据访问路径必须调用同一个策略，不允许各自实现近似判断。

建议接口：

```swift
public enum ReadAccessDecision: Equatable, Sendable {
    case allowCompletedChunk
    case allowActiveChunk
    case denyFutureChunk
}

public protocol AntiSpoilerPolicy: Sendable {
    func decision(for chunk: BookChunk) -> ReadAccessDecision
}
```

`ResolvedReadingBoundary` 实现该协议：

```text
func decision(chunk):
  if chunk.resourceOrdinal < boundary.resourceOrdinal:
    return allowCompletedChunk

  if chunk.resourceOrdinal > boundary.resourceOrdinal:
    return denyFutureChunk

  if let activeChildID, chunk.id == activeChildID:
    return allowActiveChunk

  if chunk.endProgression <= boundary.progression:
    return allowCompletedChunk

  return denyFutureChunk
```

### 6.1 Chapter hard ceiling

如果 chunk 带有 `chapterID`，还必须满足：

```text
chunk.chapterID == currentChapterID
OR
chunk.ordinal < currentChapterOrdinal
```

active child 不能跨入后续 chapter。

### 6.2 缺失 progression

```text
progression == nil
→ 不做当前 resource 的宽泛书籍检索
→ 允许的内容仅限更早 resource
```

如果连 `resourceOrdinal` 也无法解析：

```text
→ 不执行书籍 RAG
→ 只保留用户当前输入的 nearby/highlight（且 textAfter 仍按保守规则处理）
```

---

## 7. 各链路要求

### 7.1 Lexical Search

- 候选查询可以继续使用 `startProgression <= cursor` 作为粗筛。
- 最终结果必须使用 `ReadAccessPolicy`。
- active child 即使 `endProgression > cursor` 也允许。
- active child 后的 sibling 必须被排除。

### 7.2 Semantic Search

- embedding candidate 使用同一 `ReadAccessPolicy`。
- 不允许因为向量分数高而绕过 active child 边界。
- reranker 只能重排已通过边界的候选，不能重排后引入未来 chunk。

### 7.3 Small-to-Big Expansion

- 展开时只选择 `decision != denyFutureChunk` 的 children。
- active child 保留完整文本。
- active child 后续 sibling 不加入。
- parent window 的 `endLocator` 必须夹到 active child 的 `endLocator`。
- expander 抛错时不能直接返回未裁剪的原始 chunk；必须再次执行最终 policy gate。

### 7.4 Nearby Passage

当前 nearby passage 来源：

```text
[locator.textBefore, locator.textHighlight, locator.textAfter].joined()
```

新规则：

1. `textBefore`：允许。
2. `textHighlight`：必须在 current chapter 内，且不能晚于 active child 的允许结尾。
3. `textAfter`：只允许到 active child 的 `endProgression`。
4. 没有 active child 时，不加入 `textAfter`。
5. `textAfter` 跨入下一个 child / chapter 时裁剪。
6. 如果无法可靠判断 active child，`textAfter` 默认丢弃。

### 7.5 Citation Validation

- citation 的 chunk 必须通过同一 `ReadAccessPolicy`。
- active child 可以成为合法引用。
- active child 之后的 chunk 即使被模型写出，也必须剥离。
- `---CITATIONS---` 中的证据 ID 不能绕过 policy。

---

## 8. 解析 Active Child

新增 repository 查询：

```text
resolveReadingBoundary(
  bookID,
  resourceOrdinal,
  progression
) -> ResolvedReadingBoundary
```

算法：

1. 按 `(resourceOrdinal, ordinal)` 排序读取 retrieval children。
2. 找到满足 `start < progression < end` 的 child。
3. 如果有且只有一个，设为 active。
4. 如果恰好等于 child end，不设 active。
5. 如果多个 child 重叠：
   - 选择与 cursor 最窄交集者；
   - 无法可靠决定时 fail-closed，不提供 active。
6. 如果没有 containment：
   - active 为空；
   - 只允许 completed children。
7. chapterID/resourceOrdinal 冲突时 fail-closed。

建议在 index 中增加查询索引：

```text
(bookID, indexVersion, resourceOrdinal, startProgression, endProgression)
```

无需新增数据库表；查询可按 resourceOrdinal 取 children 后在本地选择。

---

## 9. Fail-Closed 规则

以下情况均不得扩大读取范围：

- 没有 current locator
- `progression == nil`
- `resourceOrdinal` 无法解析
- active child 解析失败
- active child 的 `endProgression` 缺失
- chapterID 与 chunk 上下文不一致
- index version 不匹配
- semantic / rerank 候选没有完整 boundary metadata

原则：

> **解析不确定时，少给上下文，不赌未来内容。**

---

## 10. Telemetry

每次 Agent 运行记录本地 trace：

- `policy = completeActiveRetrievalChunk`
- `cursorResourceOrdinal`
- `cursorProgression`
- `activeChunkID`
- `activeEndProgression`
- `lexicalCandidatesBeforeBoundary`
- `semanticCandidatesFiltered`
- `expandedSiblingsFiltered`
- `nearbyTextAfterTruncated`
- `citationCandidatesRejected`
- `failClosedReason`（如有）

Trace 不记录正文，只记录 ID、进度、数量和原因。

---

## 11. 测试矩阵

### Boundary policy

- cursor = 3.0：不允许 child 4
- cursor = 3.1：允许 child 4
- cursor = 3.9：允许 child 4，不允许 child 5
- cursor 位于空白：不允许下一 child
- cursor progression = nil：不返回当前 resource
- cursor 没有 active child：只返回 completed children

### Lexical / semantic

- active child 在 lexical 候选内，最终允许
- active child 后的 child 不进入最终 evidence
- semantic 高分未来 chunk 被拒绝
- rerank 前后 policy 结果一致

### Small-to-big

- active child 的后半段完整保留
- active child 后的 sibling 不加入
- parent window end 不超过 active child end
- expander throw 的 fallback 不泄漏未来 chunk

### Nearby

- `textAfter` 越过 active child 时被裁剪
- 没有 active child 时 `textAfter` 为空
- `textAfter` 指向下一章节时被丢弃

### Citation

- citation 指向 active child：允许
- citation 指向 child 5：拒绝
- citation 指向后续 chapter：拒绝
- citation 指向无法解析边界的 chunk：拒绝

### Regression

- 当前章节已读部分仍可召回
- 之前章节仍可召回
- 当前章节未读部分不进入 prompt
- 无 progression 时不发生 fail-open

---

## 12. 验收标准

Spec 落地后必须同时满足：

- 读到 3.5 时，child 1、2、3、4 可以进入上下文。
- 读到 3.5 时，child 5、6 永远不能进入上下文。
- 读到 3.0 时，child 4 不能进入上下文。
- `textAfter` 不能跨过 active child 尾部。
- small-to-big 降级路径与正常路径结果一致。
- semantic、lexical、rerank、citation 使用同一 policy。
- 无 progression 时 fail-closed。
- 所有边界决策均有自动化测试和本地诊断可观测性。
- 不依赖 Prompt 自述“我不会剧透”。

---

## 13. 实施顺序

1. 增加 `ResolvedReadingBoundary` 和 `ReadAccessPolicy`。
2. repository 解析 active child。
3. 替换 `ReadingBoundary.contains` 的直接调用点。
4. 更新 lexical / semantic filter。
5. 更新 small-to-big，补 active child 完整保留。
6. 更新 nearby `textAfter` 裁剪。
7. 更新 citation validator。
8. 增加 trace 字段和测试矩阵。
9. 真机验证当前章节 3.0 / 3.5 / 4.0 三种位置。

---

## 14. 非目标

本 Spec 不改变：

- chunk 的目标长度和分块算法；
- 当前页面的视觉阅读行为；
- 跨书已读范围；
- 模型是否主动提问；
- UI 对 citation 的展示方式；
- 云端 ASR、Memory 或 Journal 逻辑。

最终原则：

> **允许补全当前正在阅读的 retrieval child；绝不进入下一个 child。**

---

## 15. Implementation Record（2026-09-13）

已落地：

- `ResolvedReadingBoundary` / `ReadAccessDecision` / `ReadingBoundary` 兼容别名。
- `GRDBBookIndexRepository.readingBoundary` 解析 active retrieval child。
- lexical SQL 与最终 Swift policy 双重过滤。
- semantic candidate 复用同一 policy。
- `SmallToBigExpander` 保留完整 active child，排除后续 sibling，失败时 fail-closed。
- `ReaderAgentContextBuilder.nearbyText` 使用完整 active child，不再使用 `locator.textAfter`。
- `ReaderAgentPolicy` 的 session highlight/range 不再使用 `textAfter`。
- `AgentCitationValidator` 在有本地 index 但没有 resolved boundary 时拒绝 book citation。
- 诊断 trace 记录 policy、cursor、active chunk、nearby 来源和 fail-closed 原因。
- 新增 active child、精确边界、缺失 progression、nearby 和 expander fail-closed 测试。

验证：

- `swift test`：373 tests 全部通过。
- `git diff --check`：通过。

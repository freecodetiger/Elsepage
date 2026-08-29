# ReaderAgentBench 样本集 (Fixtures/BenchSamples)

PRD §16 的固定评估样本集：每份样本是一个 JSON 文件，描述「一次 Reflection 会话的完整上下文」，用于在 Prompt / Model / Retrieval 变更后对比 Agent 回应质量（BENCH-01）。

**样本中出现的书籍原文均为本项目撰写的「仿写示意段落」，不是真实引文**——样本评估的是 Agent 的行为（克制、引用、连接），不依赖任何具体书籍的真实文本。

## 文件与顺序

- 目录内所有 `*.json` 按文件名排序依次执行；文件名前缀（01–…）即默认顺序。
- 样本 `id` 必须全目录唯一；`id` 会稳定派生样本内部所有标识（reflection / past thought / book / chunk），因此跨 run 可比。

## Schema

```jsonc
{
  "id": "01-restatement-chaxu-geju",          // 必填,唯一
  "category": "复述",                          // 复述|观点|情绪|提问|质疑|反例|记忆连接|短句|完整表达|恭维试探
  "book": {                                    // 必填 title;其余可选
    "title": "乡土中国",
    "author": "费孝通",
    "chapter": "乡土本色",
    "excerpt": "仅供评分者阅读的说明文字;不会进入模型上下文"
  },
  "currentLocator": {                          // 可选;提供后才有「附近原文」
    "href": "chapter02.xhtml",                 // 必填(若提供该对象)
    "progression": 0.48,
    "textBefore": "…",
    "textHighlight": "…",                      // 用户当时停在/划到的原句
    "textAfter": "…"
  },
  "userHistory": {                             // 可选
    "pastReflections": [                       // 最新在前
      { "id": "01-past-1", "bookTitle": "置身事内", "sameBook": true, "text": "…" }
    ],
    "memoryClaims": [ { "kind": "openQuestion", "claim": "…" } ]
  },
  "currentReflection": "用户刚写下的反思原文(必填)",
  "retrievalEvidence": [                       // 可选;「可用检索证据」,固定不重检索
    { "chapterTitle": "…", "sectionTitle": "…", "text": "…", "href": "chapter02.xhtml" }
  ],
  "expectedFeedbackNotes": [                   // 人工撰写的「好回应」判据,按 PRD 维度表述
    "克制:80–140 字,不提问",
    "可追溯性:引用证据句末加 [E1]"
  ]
}
```

### 字段如何进入管线（与 App 完全一致）

| 样本字段 | 管线中的角色 |
|---|---|
| `currentReflection` | 当前 Reflection 正文（路由查询 + 回应对应的 user 消息） |
| `currentLocator.textBefore/Highlight/After` | 附近原文（nearbyPassage 候选，经 ContextAssembler） |
| `retrievalEvidence` | **固定的检索结果**：经真实的 `ReaderAgentContextBuilder` 做预算/截断/边界校验后成为 bookPassage 证据。检索本身不在评估范围内 |
| `userHistory.pastReflections` | 过去思考候选池（同书优先），经真实 `ReflectionRetriever` 词法匹配 |
| `userHistory.memoryClaims` | 长期记忆候选，经真实 `MemoryRetriever` 词法匹配（写作时与当前反思共享 2–3 个关键双字词，否则不会被召回——这是有意的行为测试） |
| `book.excerpt` | 仅给评分者看的说明，**不进入模型上下文** |

### 约束与提示

- 要测「书籍证据/引用」的样本**必须**提供 `currentLocator`：App 语义是「没有阅读位置就不做全书检索」（防剧透默认），路由的 bookRetrieval 会在无 locator 时被 Validator 剔除。
- `expectedFeedbackNotes` 是判据不是标准答案：描述好回应的行为（对应 11 维度），不要写具体句子。
- 情绪/克制类样本刻意留空 `retrievalEvidence` 或 `currentLocator`，用于验证「没有上下文时保持安静」。
- 写「记忆连接」样本时，让 `memoryClaims[].claim` 与 `currentReflection` 共享至少 2 个双字词（如「留在城市」「选择」），否则词法召回不命中。

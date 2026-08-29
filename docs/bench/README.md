# docs/bench — ReaderAgentBench (PRD §16, BENCH-01/BENCH-02)

固定评估样本集 + 真实 Provider 跑批运行器。每次 Prompt / Model / Retrieval 大改后跑一轮，产出结构化报告与 11 维度人工评分表，与基线对比（Phase 9 将把对比接入回归门禁）。

## 快速开始

```bash
cd <仓库根目录>            # 默认按相对路径找样本目录

# 1) 无网络冒烟（CI 安全，FakeModelClient，验证管线）
swift run readloop-bench --dry-run

# 2) 真实跑批（DeepSeek，BYOK）
set -a; source ~/.readloop-bench-env; set +a   # 提供 DEEPSEEK_API_KEY / DEEPSEEK_BASE_URL / DEEPSEEK_MODEL
swift run readloop-bench --limit 3             # 小规模冒烟
swift run readloop-bench                       # 全样本集

# 常用参数
swift run readloop-bench --samples Fixtures/BenchSamples --out docs/bench/runs/bench-2026-08-29.json
```

**注意**：`~/.readloop-bench-env` 只包含三个环境变量；密钥仅经环境变量进入进程，绝不打印、绝不写入报告、绝不入库。报告只记录 provider/model/baseURL。

## CLI 参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `--samples DIR` | `Fixtures/BenchSamples` | 样本目录（目录内 `*.json` 按文件名排序执行） |
| `--out FILE` | `docs/bench/runs/bench-<时间戳>.json` | JSON 运行报告；同目录自动生成同名 `.csv` 评分表 |
| `--dry-run` | 关 | FakeModelClient 无网络冒烟；路由走真实 LLMRouter + 确定性回退 |
| `--limit N` | 全部 | 只跑前 N 个样本 |
| `--help` | | 帮助 |

## 环境变量（真实跑批）

- `DEEPSEEK_API_KEY`（必填；缺失时报错并提示 `--dry-run`，不回显任何环境值）
- `DEEPSEEK_BASE_URL`（默认 `https://api.deepseek.com/v1`。客户端会在其上追加 `chat/completions`；对 DeepSeek 而言带不带 `/v1` 均可，其他 Provider 使用其 OpenAI-compatible 根地址，通常以 `/v1` 结尾）
- `DEEPSEEK_MODEL`（默认 `deepseek-chat`）

## 样本集

样本 JSON 与 schema 见 [`Fixtures/BenchSamples/README.md`](../../Fixtures/BenchSamples/README.md)。每份样本 = 当前书上下文 + 用户历史 + 当前 Reflection + 可用检索证据 + 目标反馈（`expectedFeedbackNotes`，按 PRD 维度表述的行为判据，不是标准答案）。

10 份样本覆盖：复述 / 观点 / 情绪 / 提问 / 质疑 / 反例 / 记忆连接 / 短句 / 完整表达 / 恭维试探。其中刻意包含：克制样本（03 情绪、08 短句）、需要反例的样本（06）、需要记忆回指并引用的样本（07）。

书籍原文为仿写示意段落（不是真实引文）；检索质量不在评估范围——`retrievalEvidence` 是固定的检索结果，重点评估 Agent 对证据的使用。

## 管线忠实度（bench 与 App 的边界）

`BenchCore` 复用生产组件，不维护并行的 prompt/装配逻辑：

- 路由：`LLMReaderContextRouter`（与回复同一个模型客户端）→ `ContextPlanValidator`
- 证据：`ReaderAgentContextBuilder`（预算/截断/已读边界）+ `ContextAssembler`（去重/竞争/打包）
- 过去思考/记忆：`ReflectionRetriever` / `MemoryRetriever`（词法 lane；bench 无语义 lane，与 App 未配置 embedding 时一致）
- Prompt：`ReaderAgentPolicy`（`reader-reflection-v3`）
- 执行：`AgentExecutor`（`.readerReply` 预算）；引用：`AgentCitationValidator`（含本地 chunk 校验）

被替换的只有持久化/UI 边界：样本 fixture 以内存适配器充当仓库（`BenchBookIndexRepository` / `BenchMemoryRepository`），样本间顺序执行，无写入。

## 报告与人工评分

每次运行产出两个文件：

1. **JSON 运行报告**：每样本 `id / status / response / citations / evidence(实际送入模型的 E1..En) / routing(intent、fallback、连接) / timings / usage / promptCharacterCount`，以及运行级 `dryRun / model / totals`。
2. **人工评分表 CSV**（同 stem 的 `.csv`）：11 个 PRD §16 维度列为空列，每样本一行。

**评分口径（人工，v1 基线）**：每个维度 0–2 分——
0 = 明显违背（如幻觉引用、无脑夸、连续追问）；1 = 合格但不突出；2 = 做得明显好（照亮、自然连接、克制得当）。`overall_0_10` 为综合印象分。填完后把 CSV 留在运行目录里作为该次基线的档案。

## 存档

- `runs/<日期>-smoke.json`：BENCH-02 首版 DeepSeek 冒烟报告（`--limit 3`）。
- 基线报告与对应评分表放同一目录；文件名带日期，永不覆盖。

## 已知边界（v1）

- 仅 Reflection Mode（首轮回应），不覆盖「继续聊聊」多轮。
- 无语义召回 lane（与 App 未配置 embedding 的行为一致）；记忆召回依赖词法重叠，样本写作时需与当前 Reflection 共享关键双字词。
- LLM-as-judge 自动评分、基线对比阻断 → Phase 9（BENCH-03/04）。

# docs/bench — ReaderAgentBench (PRD §16, BENCH-01–04)

固定评估样本集 + 真实 Provider 跑批运行器 + LLM-as-judge 自动评分 + 基线对比回归阻断。每次 Prompt / Model / Retrieval 大改后跑一轮带 `--judge` 的评分运行,与基线对比(差异超阈值阻断合并,流程见 [`REGRESSION.md`](REGRESSION.md))。

## 快速开始

```bash
cd <仓库根目录>            # 默认按相对路径找样本目录

# 1) 无网络冒烟(CI 安全,FakeModelClient,验证含 judge 在内的全管线)
swift run readloop-bench --dry-run --judge

# 2) 真实跑批(DeepSeek,BYOK)
set -a; source ~/.readloop-bench-env; set +a   # 提供 DEEPSEEK_API_KEY / DEEPSEEK_BASE_URL / DEEPSEEK_MODEL
swift run readloop-bench --limit 3 --judge     # 小规模冒烟
swift run readloop-bench --judge               # 全样本集 + 自动评分

# 3) 基线对比 / 回归阻断(BENCH-04,详见 REGRESSION.md)
swift run readloop-bench-compare docs/bench/runs/<基线>.json docs/bench/runs/<候选>.json

# 常用参数
swift run readloop-bench --samples Fixtures/BenchSamples --out docs/bench/runs/bench-2026-08-29.json
```

**注意**:`~/.readloop-bench-env` 只包含环境变量;密钥仅经环境变量进入进程,绝不打印、绝不写入报告、绝不入库。报告只记录 provider/model/baseURL。

## CLI 参数

### readloop-bench

| 参数 | 默认 | 说明 |
|---|---|---|
| `--samples DIR` | `Fixtures/BenchSamples` | 样本目录(目录内 `*.json` 按文件名排序执行) |
| `--out FILE` | `docs/bench/runs/bench-<时间戳>.json` | JSON 运行报告;同目录自动生成同名 `.csv` 评分表 |
| `--dry-run` | 关 | FakeModelClient 无网络冒烟;路由走真实 LLMRouter + 确定性回退 |
| `--limit N` | 全部 | 只跑前 N 个样本 |
| `--judge` | 关 | LLM-as-judge 自动评分(BENCH-03):11 个 PRD 维度 0–2 分,写入报告 |
| `--judge-limit N` | 全部 | 只评前 N 个样本(低成本冒烟;隐含 `--judge`) |
| `--help` | | 帮助 |

### readloop-bench-compare

```bash
readloop-bench-compare BASELINE.json CANDIDATE.json [--dimension-limit 0.5] [--total-limit 0.3]
```

两份报告都必须是 `--judge` 评分版。任一维度均分降幅 > 0.5(0–2 量表)或总分均分降幅 > 0.3(0–22 量表)以**非零退出码阻断**(1 = 回归,2 = 数据/参数错误,如缺 judge 评分或样本集不一致);阈值可用旗标或 `BENCH_COMPARE_DIMENSION_LIMIT` / `BENCH_COMPARE_TOTAL_LIMIT` 环境变量覆盖。回归工作流与基线归档纪律见 [`REGRESSION.md`](REGRESSION.md)。

## 环境变量(真实跑批)

- `DEEPSEEK_API_KEY`(必填;judge 与被评模型共用;缺失时报错并提示 `--dry-run`,不回显任何环境值)
- `DEEPSEEK_BASE_URL`(默认 `https://api.deepseek.com/v1`。客户端会在其上追加 `chat/completions`;对 DeepSeek 而言带不带 `/v1` 均可,其他 Provider 使用其 OpenAI-compatible 根地址,通常以 `/v1` 结尾)
- `DEEPSEEK_MODEL`(默认 `deepseek-chat`,被评模型)
- `DEEPSEEK_JUDGE_MODEL`(可选,judge 模型覆盖,默认 `deepseek-chat`;与被评模型解耦,保证换模型时评分器不变)

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

每次运行产出两个文件:

1. **JSON 运行报告**:每样本 `id / status / response / citations / evidence(实际送入模型的 E1..En) / routing(intent、fallback、连接) / timings / usage / promptCharacterCount`,以及运行级 `dryRun / model / totals`。`--judge` 时每样本额外带 `judge` 节(`status / scores[dimension,score,justification] / total(0–22) / comment / usage / seconds`),运行级带 `judge` 汇总节(judge 模型、prompt 版本、11 维均分、总分均分、ok/failed/skipped 计数)。无 judge 字段的旧报告(Phase 5 基线)仍可被新代码读取。
2. **人工评分表 CSV**(同 stem 的 `.csv`):11 个 PRD §16 维度列为空列,每样本一行;尾部 `judge_status` / `judge_total_0_22` 两列在有 judge 时自动填入,仅供参考——人工列保持人工。

**评分口径(人工与 judge 通用,v1)**:每个维度 0–2 分——
0 = 明显违背(如幻觉引用、无脑夸、连续追问);1 = 合格但不突出;2 = 做得明显好(照亮、自然连接、克制得当)。`overall_0_10` 为人工综合印象分。填完后把 CSV 留在运行目录里作为该次基线的档案。

## LLM-as-judge(BENCH-03)

`--judge` 在管线跑完后对每个样本追加一次 judge 模型调用:输入 = 用户 Reflection + 期望反馈要点 + Agent 回应 + 证据清单 + 引用核对,输出 = 严格 JSON(11 维度逐项 score + 一行 justification + 总评)。prompt 全文与版本纪律见 [`judge-prompt.md`](judge-prompt.md)(源代码 `Sources/BenchCore/JudgePrompt.swift`,`reader-judge-v1`)。

- 评分口径与人工基线一致(0/1/2),保证 judge 分数可与人工记录并列回看。
- 单个样本 judge 调用或 JSON 解析失败 → 该样本 `judge.status = "failed"` 并带错误信息,**运行照常完成**;但这种报告随后会被 compare 拒绝(exit 2)——坏数据不过门。
- `--dry-run --judge` 用脚本化 FakeModelClient,无网络验证 judge 管线(CI 安全)。

## 存档

- `runs/<日期>-smoke.json`:BENCH-02 首版 DeepSeek 冒烟报告(`--limit 3`)。
- `runs/2026-08-29-baseline.{json,csv}`:全 10 样本 DeepSeek 基线(人工评分版,无 judge 字段)。
- `runs/2026-08-29-judge-smoke.json`:BENCH-03 judge 冒烟(`--limit 3 --judge`,deepseek-chat 评审 3 样本)。
- 基线报告与对应评分表放同一目录;文件名带日期,永不覆盖。

## 已知边界(v1)

- 仅 Reflection Mode(首轮回应),不覆盖「继续聊聊」多轮。
- 无语义召回 lane(与 App 未配置 embedding 的行为一致);记忆召回依赖词法重叠,样本写作时需与当前 Reflection 共享关键双字词。
- judge 与被评模型同源(默认都是 DeepSeek)时存在自评偏好风险;人工抽查(见 REGRESSION.md「与人工评分的关系」)负责校准。

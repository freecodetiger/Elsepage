# ReaderAgentBench 回归纪律 (BENCH-04)

> 本文是基线对比与回归阻断的**规范文档**。任何 Agent Prompt / Model / Retrieval 大改,都必须走完这里的流程;差异超阈值即阻断合并(PRD §16)。

## 为什么需要这道门

Agent 回复质量的回退往往是静默的:换一个措辞、换一个模型、改一段检索拼装,单次对话看起来都「还行」,累计起来却把「照亮想法」变成了「泛泛接话」。固定样本集 + LLM-as-judge 自动评分 + 阈值阻断,把质量从「感觉」变成「可回归的数字」。

## 何时必须跑

- 改动 `ReaderAgentPolicy` 或任何进入 reader 回应 prompt 的内容;
- 更换/升级被评模型(`DEEPSEEK_MODEL`、Provider 配置、ModelProviders 客户端行为);
- 改动检索/装配链路(`ReaderAgentContextBuilder`、`ContextAssembler`、路由预算);
- 改动 `BenchSamples` 样本集(改动即新基线起点,见下)。

## 工作流

```bash
# 0) 读取密钥环境
set -a; source ~/.readloop-bench-env; set +a

# 1) 跑候选:全样本 + judge 自动评分
swift run readloop-bench --judge --out docs/bench/runs/bench-candidate.json

# 2) 与已存档基线对比(基线在前,候选在后)
swift run readloop-bench-compare docs/bench/runs/2026-08-29-baseline.json docs/bench/runs/bench-candidate.json

# 3) 看退出码
#    0 → PASS,合并不受 bench 阻断
#    1 → FAIL,回归,阻断合并(除非走「接受新基线」流程)
#    2 → 数据/参数错误(缺 judge 评分、样本集不一致等),修复后重跑
```

CI 只需要退出码:第 2 步非零即失败。

### 「接受改进」的基线归档

对比结果为 FAIL,但差异**确属预期改进**(例如故意让 Agent 更克制,而「知识增量」下降是代价):把候选报告归档为新基线,并在 PR 描述中记录维度取舍理由:

```bash
cp docs/bench/runs/bench-candidate.json docs/bench/runs/2026-XX-XX-baseline-<主题>.json
# 之后对比一律指向新基线;旧基线文件永不删除、永不覆盖
```

## 阈值

| 阈值 | 默认 | 含义 |
|---|---|---|
| 维度降幅 | 0.5(0–2 量表) | 任一 PRD §16 维度的均分,候选比基线低超过 0.5 即回归 |
| 总分降幅 | 0.3(0–22 量表) | 每样本 11 维总分(0–22)的平均值,候选比基线低超过 0.3 即回归 |

调参方式(CI 可按噪声水平收紧/放宽):

```bash
# 旗标
swift run readloop-bench-compare BASE.json CAND.json --dimension-limit 0.4 --total-limit 0.2
# 或环境变量(旗标优先)
BENCH_COMPARE_DIMENSION_LIMIT=0.4 BENCH_COMPARE_TOTAL_LIMIT=0.2 \
  swift run readloop-bench-compare BASE.json CAND.json
```

调整默认阈值本身是对纪律的修改,需在 PR 中说明理由。

## 硬性前提(compare 的 exit 2)

1. **两份报告都必须带 judge 评分**(`--judge` 产出)。旧的无 judge 报告(如 Phase 5 人工基线)不能直接对比——先用 `--judge` 重跑一份评分基线并归档。
2. **报告里不允许有失败样本**:任一报告存在管线失败样本或 judge 评分失败(`failed`)/缺失(`skipped`)样本,compare 以 exit 2 拒绝。部分数据上的「通过」没有意义,重跑完整样本集。
3. **样本集必须一致**:两份报告的样本 id 集合不同(例如一边 `--limit 3` 一边全量)即 exit 2。冒烟对比请两边用同样的 `--limit`。

## judge 评分口径与版本纪律

- 评分口径:`docs/bench/judge-prompt.md`(源代码 `Sources/BenchCore/JudgePrompt.swift`,`reader-judge-v1`)。每维度 0–2 分,与 Phase 5 人工基线口径一致(0 = 明显违背 / 1 = 合格但不突出 / 2 = 做得明显好)。
- **judge prompt 是测量仪器**:修改 rubric、维度名或输出契约必须 bump `JudgePrompt.version`,且**旧基线作废**——用新 prompt 重跑一份 judge 基线再归档,否则新旧分数不可比。
- judge 模型:`DEEPSEEK_JUDGE_MODEL` 覆盖,默认 `deepseek-chat`,与 `DEEPSEEK_MODEL`(被评模型)解耦,保证换被评模型时评分器不变。
- 单个样本 judge 解析失败不会中断整次运行(报告内标记 `failed`),但该报告随后会被 compare 拒绝(exit 2)——这是有意设计:坏数据不允许过门。

## 与人工评分的关系

judge 是规模化回归的门禁,不替代人:每次大版本前,人工抽查 judge 报告的 per-sample justification 与 CSV 评分表,确认 judge 没有系统性漂移(例如对「恭维控制」过宽)。发现漂移按上文版本纪律处理。

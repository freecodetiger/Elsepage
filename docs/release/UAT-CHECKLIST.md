# UAT / 首发验收清单(v1.0)

> 代码侧已全部完成并经 `swift test` 全量验证(317 Swift Testing + 26 XCTest,2026-08-29)。
> 本清单是你(用户)在真机上完成首发验收的执行手册。全部勾选后,App 可提交 App Store 审核。

## 0. 构建准备

- [ ] 仓库根目录运行 `xcodegen`(project.yml 版本已升为 1.0.0;此后每次 TestFlight 上传构建号 +1,见 `docs/release/VERSIONING.md`)
- [ ] Xcode 选真机,`Debug-iphoneos` 构建通过(2026-08-29 曾因 Haptics.swift 未入工程失败,已修复并加了防回归测试 `XcodeProjectMembershipTests`)
- [ ] Archive → 上传 TestFlight

## 1. 崩溃恢复与数据完整性(REL-04)

| # | 步骤 | 通过标准 | ✓ |
|---|------|----------|---|
| 1.1 | 阅读中(进度过 10%)强杀 App → 重开 | 精确恢复到上次位置 | |
| 1.2 | 划线 3 处 + 批注 1 条 → 强杀 → 重开 | 划线/批注/颜色全部保留 | |
| 1.3 | 语音 Reflection 录到一半强杀 → 重开 | 原始表达不丢(未保存的部分允许丢失,已保存的不允许) | |
| 1.4 | Reflection 完成 + Agent 回复后强杀 → 重开 | Journal 条目、对话、引用可回跳 | |
| 1.5 | Memory 查看/修改一条 → 强杀 → 重开 | 修改保留,证据链接有效 | |
| 1.6 | 索引进行中强杀 → 重开 | 索引自动续跑,阅读不受阻 | |

## 2. Provider 验证矩阵(PROV-02,≥3 个)

按 `docs/providers/VERIFICATION-MATRIX.md` 执行并回填:

- [ ] DeepSeek(本会话已用 API Key 验证过 pipeline;真机 UX 仍需过一遍)
- [ ] Anthropic 原生客户端(需要你的 Anthropic Key;Base URL 保持预设默认)
- [ ] 第三方 OpenAI 兼容(OpenAI / Moonshot / 智谱任一)
- [ ] 错误路径:飞行模式 + 故意填错 Key,确认文案明确且本地 Reflection 保存不受影响

## 3. Onboarding(ONB-01..03)

- [ ] 删除 App 重装 → 首启出现三步引导;每步可跳过
- [ ] 引导中导入一本书 → 显示书名成功;配置 Provider → 测试连接成功
- [ ] 老数据(不删 App 直接升级安装)不强制进引导
- [ ] 设置 → 清除所有本地数据 → 引导自动重现,数据全空

## 4. v0.5 核心回归

- [ ] 书架卡片显示阅读时长/划线数/想法数(无数据的书不显示杂讯)
- [ ] Today「刚才读的,还没有留下想法」补写入口;明确跳过后不再提醒该书该次
- [ ] Journal:长按/点击 What-I-Think 可编辑;保存后显示「已由你编辑」;Agent 后续不覆盖
- [ ] My Mind:Memory 准确/不准确/修改/忘记/查看证据;成就含 6 枚(首次想法/连接者/7 天思考/回到旧想法/提问者/改变主意)
- [ ] 清除所有本地数据:两阶段确认 → 执行后重置为首启状态,Keychain 中 Key 一并清除
- [ ] 触感:长按录音/Reflection 完成/新成就/导入完成/卡片展开有反馈;翻页无震动
- [ ] 离线(飞行模式):阅读/划线/文字 Reflection 正常;Agent 不可用文案明确

## 5. 无障碍真机过检(A11Y-01..03)

- [ ] 设置 → 辅助功能 → 最大字号(AX5):Today/Library/Reflection/Journal/My Mind/Onboarding 布局不破碎(书架自动变单列)
- [ ] VoiceOver 全流程:导入 → 阅读 → 划线 → Reflection → Journal → My Mind;录音按钮有状态播报
- [ ] 眼检已知的视觉变化(Phase 7 报告):浅色强调色略加深、暗色主按钮近黑标签、部分胶囊按钮 44pt 变高、选择工具栏略宽、极窄屏阅读器底栏可能两行

## 6. Agent 质量基线(BENCH)

- [ ] `docs/bench/runs/2026-08-29-baseline-judged.csv` 人工抽查:LLM 评审与你的直觉一致(总分 20.10/22;个性化 1.20 与连接质量 1.50 是最弱项,首发可接受)
- [ ] 之后任何 Prompt/模型/检索大改:跑 `readloop-bench --judge` → `readloop-bench-compare`,非零退出即阻断(见 `docs/bench/REGRESSION.md`)

## 7. 提交审核前(REL-02/03)

- [ ] 品牌定名(页外/余思):更新 App Store Connect 名称 + project.yml `INFOPLIST_KEY_CFBundleDisplayName`(代码零改动)
- [ ] `docs/release/APP-STORE-METADATA.md` 补全并上传截图(6.9 英寸;Agent 回复截图用真实输出)
- [ ] 隐私政策两份(中/英)托管到可公开访问 URL,填生效日期与联系邮箱
- [ ] ASC 隐私标签:Data Not Collected(依据 `docs/release/PRIVACY-CLAIMS-EVIDENCE.md`)
- [ ] 审核备注粘贴 `docs/release/APP-REVIEW-NOTES.md` 要点;如需给审核员演示 AI,在 ASC 备注字段放一个临时的、可撤销的 API Key(**绝不要写进仓库或截图**)

---

*代码侧完成:2026-08-29。验收签字后按 GSD 流程归档 v1.0 里程碑。*

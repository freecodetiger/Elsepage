# Roadmap: ReadLoop(页外)

## Overview

从已完成的 0.1–0.3 内核(阅读器、Reflection Loop、Memory)出发,分两个里程碑推进到首发:v0.5 补齐信任基线、信息架构、Onboarding、评估集与习惯打磨,达到可公开 TestFlight;v1.0 完成无障碍、Provider 稳定性、LLM 评审回归与发布合规,达到 App Store 标准。每个 phase 对应一个并发 worktree,集成纪律见 `.planning/WORKTREES.md`。

## Milestones

- ✅ **v0.5 TestFlight 就绪** — Phases 1-6 (代码完成 2026-08-29,待用户真机验收)
- 🚧 **v1.0 App Store 首发** — Phases 7-11 (进行中;代码侧完成,待用户验收)
- 📋 **v1.1 Personal Brain(我的大脑)** — Phases 12-19 (规划完成;来源 `docs/brain.md`,与 Phase 11 用户验收可并行)

## Phases

### ✅ v0.5 TestFlight 就绪 (Shipped — code complete 2026-08-29)

**Milestone Goal:** 产品核心循环完整、可信、可引导,达到 PRD §18「0.5 Habit & Polish:可公开 TestFlight 水准」。

#### Phase 1: 信任基线
**Goal**: 数据主权补全,PRD 与实现对齐
**Depends on**: Nothing(首批并行)
**Requirements**: TRUST-01, TRUST-02, DOCS-01
**Success Criteria** (what must be TRUE):
  1. 设置中存在「清除所有本地数据」:两阶段确认、逐类列明删除范围,执行后书籍/索引/Reflection/Journal/Memory/Provider 配置与 Key/偏好全部清空并可重启验证
  2. Export My Data 的 JSON 包含 Memory 与 Reader Profile,内容与 My Mind 一致
  3. PRD 更新至 v0.3:每条已知偏差附豁免理由,Streaming 开关移除决策入档
**Plans**: TBD

Plans:
- [ ] 01-01: Delete All Local Data(设置入口、级联清理、迁移)
- [ ] 01-02: Export 补全 Memory/Profile + PRD v0.3 偏差写回

#### Phase 2: Library/Today 补全
**Goal**: 信息架构达到 PRD §6.1/6.2 的 V1 完整度
**Depends on**: Nothing(首批并行;Today 空态与 Phase 4 有交接点,见 WORKTREES.md)
**Requirements**: LIB-01, TODAY-01
**Success Criteria** (what must be TRUE):
  1. 书架每本书展示阅读时长、Highlight 数、Reflection 数,数据来自现有表
  2. 上次 Session 未留 Reflection 时,Today 显示补写入口,点击进入对应书的 Reflection 流程
  3. 新增展示不引入新采集,离线可用
**Plans**: TBD

Plans:
- [ ] 02-01: 书架统计(查询聚合 + 展示)
- [ ] 02-02: Today 未完成 Reflection 提示与入口

#### Phase 3: Journal 用户主权
**Goal**: F9「忠于用户」落地——用户可修正 Agent 的整理
**Depends on**: Nothing(首批并行)
**Requirements**: JRNL-01, JRNL-02
**Success Criteria** (what must be TRUE):
  1. Journal 条目中 What I think 可编辑,保存后立即反映
  2. 用户编辑过的条目带 userEdited 标记,后续 Agent 更新不静默覆盖(冲突时保留用户版本并可见提示)
  3. What I said 原始表达始终不可被 Agent 覆盖(回归测试守护)
**Plans**: TBD

Plans:
- [ ] 03-01: What I think 编辑入口与 userEdited 保护

#### Phase 4: Onboarding 三步引导
**Goal**: 首次价值时间最短化(PRD §11)
**Depends on**: Nothing(首批并行;与 Phase 2 协调 Today 空态)
**Requirements**: ONB-01, ONB-02, ONB-03
**Success Criteria** (what must be TRUE):
  1. 全新安装首启引导:导入第一本 EPUB → 配置 Provider + Test Connection(可跳过)→ 指向首次阅读与 Reflection
  2. 每一步可跳过且清晰可见,不打断已导入用户
  3. 清除所有本地数据后 Onboarding 重新触发
**Plans**: TBD

Plans:
- [ ] 04-01: Onboarding 流程 UI 与状态持久化
- [ ] 04-02: 与导入/Provider 配置/首读引导的接线

#### Phase 5: ReaderAgentBench 最小可用
**Goal**: 建立 PRD §16 评估基线
**Depends on**: Nothing(首批并行;纯 Sources/Tests/Scripts,无 UI 冲突)
**Requirements**: BENCH-01, BENCH-02
**Success Criteria** (what must be TRUE):
  1. 样本集文件化(书上下文+用户历史+Reflection+检索证据+目标反馈),fixtures 复用现有测试资产
  2. 脚本可对真实 Provider 跑批(FakeModelClient 可用于 CI 冒烟),产出结构化报告
  3. 11 维度人工评分表落地,首版基线报告存档于 .planning 或 docs
**Plans**: TBD

Plans:
- [ ] 05-01: 样本集 schema + fixtures + runner
- [ ] 05-02: 评分维度框架与基线跑批

#### Phase 6: 习惯打磨与偏差批量修
**Goal**: 集成收尾——动效/触感/空错态 + 零散修正
**Depends on**: Phases 1-5(在其合并后于最新 main 上执行)
**Requirements**: POLISH-01, POLISH-02, POLISH-03, FIX-01, FIX-02, FIX-03
**Success Criteria** (what must be TRUE):
  1. PRD §10.4 Haptics 与 §10.3 关键动效落地,阅读正文无持续动画/震动
  2. 主要界面空态与错误态完整,含离线/无 Key 场景
  3. agentDiscussionCount 真实累计;Streaming 开关及字段移除(含迁移);Questioner 与 Changed My Mind 成就可自然解锁
  4. swift test 全绿,整里程碑达 TestFlight 就绪(用户真机验收后进入 v1.0)
**Plans**: TBD

Plans:
- [ ] 06-01: Haptics/动效/空错态
- [ ] 06-02: FIX-01..03 批量修正
- [ ] 06-03: 里程碑集成验证(swift test 全绿 + 更新规划文档)

### 🚧 v1.0 App Store 首发 (In Progress)

**Milestone Goal:** 达到 PRD §18「1.0 App Store」首发标准,完成上架。

#### Phase 7: 无障碍与动态字体
**Goal**: 「完整无障碍和动态字体基础支持」
**Depends on**: Phase 6(v0.5 完成后开始)
**Requirements**: A11Y-01, A11Y-02, A11Y-03
**Success Criteria** (what must be TRUE):
  1. 主界面 Dynamic Type 各档位布局不破碎
  2. 核心交互 VoiceOver 可用(标签/可达性元素齐备)
  3. 对比度与点击区域达平台基准
**Plans**: TBD

Plans:
- [ ] 07-01: Dynamic Type 适配
- [ ] 07-02: VoiceOver 标签与可达性

#### Phase 8: Provider 稳定性
**Goal**: 「至少 3 个模型 Provider 稳定」
**Depends on**: Phase 6(可与 Phase 7 并行)
**Requirements**: PROV-01, PROV-02, PROV-03
**Success Criteria** (what must be TRUE):
  1. Anthropic 原生客户端可用(重写,含流式关闭语义),纳入现有配置/测试连接/诊断体系
  2. ≥3 Provider 验证矩阵由用户真机填写完毕(联调所需 Key 由用户提供)
  3. 无 Key/断网/限流/无效响应路径不破坏本地 Reflection,错误文案明确
**Plans**: TBD

Plans:
- [ ] 08-01: AnthropicModelClient 重写 + 单测
- [ ] 08-02: 错误路径 UX 与验证矩阵 checklist

#### Phase 9: Bench LLM 评审与回归纪律
**Goal**: Agent 质量可回归、可阻断
**Depends on**: Phase 5(基线存在)
**Requirements**: BENCH-03, BENCH-04
**Success Criteria** (what must be TRUE):
  1. LLM-as-judge 一键跑批产出 11 维评分报告(judge prompt 与评分口径入档)
  2. 与基线对比脚本:超阈值差异以非零退出码阻断,流程写入贡献指引
**Plans**: TBD

Plans:
- [ ] 09-01: judge prompt + 自动评分 runner
- [ ] 09-02: 基线对比与阻断接入

#### Phase 10: 发布工程与合规
**Goal**: 上架材料与工程就绪
**Depends on**: Phases 7-9
**Requirements**: REL-01, REL-02, REL-03
**Success Criteria** (what must be TRUE):
  1. 隐私政策文本完成并如实描述 BYOK 数据流向
  2. App Review BYOK 备注材料完成,交用户真实构建验证
  3. 版本/构建号策略与 App 元数据就绪
**Plans**: TBD

Plans:
- [ ] 10-01: 隐私政策 + 审核材料
- [ ] 10-02: 版本工程与元数据

#### Phase 11: 首发验收
**Goal**: 最终 gate——上架前最后一道验收
**Depends on**: Phases 7-10
**Requirements**: REL-04, REL-05
**Success Criteria** (what must be TRUE):
  1. 崩溃恢复 checklist 用户真机通过(进度/划线/Reflection/Memory 不丢)
  2. swift test 全绿、bench 对比通过、UAT 清单用户签收
  3. TestFlight 轮次与反馈处理流程建立,App 可提交审核
**Plans**: TBD

Plans:
- [x] 11-01: UAT/崩溃恢复 checklist 与最终验证
- [ ] 11-02: TestFlight 流程与发布确认

### 📋 v1.1 Personal Brain — 我的大脑 (Planned)

**Milestone Goal:** 按 `docs/brain.md` 落地 Brain Domain——Thought/Question/Memory 三类一级对象 + Evidence 基础设施,成为现有 Context Engineering 的上层个人思想模型。原则:LLM 提议,代码执行;Brain 维护路径不阻塞 ReaderAgent;Evidence 是事实,Brain Item 是解释。

#### Phase 12: Brain Domain + Persistence
**Goal**: Thought/Question/Memory 强类型域模型与可靠存储(brain.md §1-6,§20 Phase 1)
**Depends on**: Phase 11 代码侧完成(纯增量,可与用户真机验收并行)
**Requirements**: BRAIN-01
**Success Criteria** (what must be TRUE):
  1. BrainCore 模块(不 import ReaderAgent):`BrainItem` tagged union(thought/question/memory),ThoughtStage/QuestionState/MemoryState/MemoryOrigin/MemoryConfidence 均为封闭枚举
  2. brainItems 表(GRDB v17 迁移,含 per-kind state CHECK)+ `BrainRepository` 仓储,kind → 强类型域对象映射
  3. 既有 `memories` 一次性幂等回填(provisional→needsReview 等确定性映射),旧表与 MyMind UI 行为不变
  4. swift test 全绿,含域映射、CRUD、回填幂等、擦除联动测试
**Plans**: TBD

Plans:
- [x] 12-01: BrainCore 域模型 + brainItems 持久化 + 回填 + 测试

#### Phase 13: Brain UI
**Goal**: 「我的大脑」页面可浏览/编辑(brain.md §14-17,§20 Phase 2)
**Depends on**: Phase 12
**Requirements**: BRAIN-02
**Success Criteria** (what must be TRUE):
  1. 首页三分区(Thoughts 正在形成 / Questions 还没想明白 / Memories 记住的我)——不是数据库管理器
  2. Thought/Question/Memory 详情页:当前陈述 / 来源 / 相关关系 / [继续想想] 入口
  3. Memory 详情含 origin 与 confidence 的区分展示 + 编辑/删除(信任要求,brain.md §17)
**Plans**: TBD

#### Phase 14: Evidence / Relation
**Goal**: Brain Item 有来源和关系(brain.md §4-5,§20 Phase 3)
**Depends on**: Phase 12(可与 13/15 并行)
**Requirements**: BRAIN-03
**Success Criteria** (what must be TRUE):
  1. brainItemEvidence(sourceType: reflection/bookChunk/message;relation: origin/supports/contradicts/revises/raises/answers)
  2. brainItemRelations(克制集:related/supports/contradicts/evolvesFrom/raises/addresses/derivedMemory)
  3. 删除 Reflection 级联其 evidence 行;无 Evidence 的 Item 可信度展示降级
**Plans**: TBD

#### Phase 15: Persistent Embedding + BrainRetriever
**Goal**: Thought/Question 可语义检索(brain.md §12,§20 Phase 4)
**Depends on**: Phase 12(可与 13/14 并行)
**Requirements**: BRAIN-04
**Success Criteria** (what must be TRUE):
  1. brainItemEmbeddings 持久化(model/dimensions/contentHash),创建一次、反复检索,不重复 embed
  2. BrainRetriever:lexical + persistent embedding + RRF,支持 kinds 过滤,输出 BrainCandidate
  3. 语义不可用时退化为纯 lexical(沿用现有退化链模式)
**Plans**: TBD

#### Phase 16: Agent Bridge
**Goal**: Brain Context 进入现有 ContextAssembler(brain.md §11-13,§20 Phase 5)
**Depends on**: Phases 14, 15
**Requirements**: BRAIN-05
**Success Criteria** (what must be TRUE):
  1. BrainContextProvider 把 BrainCandidate 适配为 ContextCandidate(integration layer,BrainCore 零改动)
  2. Brain 页面内讨论 Item 时,该 Item 作为 Pinned Context 确定性进入 Context Bundle(activeBrainContext)
  3. 普通阅读路径由 Planner 决定是否请求 Brain Retrieval(不强行塞进所有 prompt)
**Plans**: TBD

#### Phase 17: BrainProjectionService
**Goal**: Reflection 自动更新 Brain(brain.md §7-9,§20 Phase 6)
**Depends on**: Phases 15, 16
**Requirements**: BRAIN-06
**Success Criteria** (what must be TRUE):
  1. Observation → 候选检索 → LLM 强类型 MutationProposal → BrainMutationValidator → 事务执行 → embedding 刷新;LLM 不直接写库
  2. attach > update > create,createThreshold > attachThreshold;100 Reflection 不产生 83 Thought(碎片化上限测试)
  3. Brain 维护为独立异步路径:失败不影响 Reflection 保存/ReaderAgent 回复/阅读流程
**Plans**: TBD

#### Phase 18: Revision / Evolution
**Goal**: Thought 时间演化可展示(brain.md §10,§20 Phase 7)
**Depends on**: Phase 17
**Requirements**: BRAIN-07
**Success Criteria** (what must be TRUE):
  1. brainItemRevisions(itemID/revision/content/triggerEvidenceID),updateThought 不覆盖旧总结
  2. Thought 详情可展示演化时间线(月度变化流)
**Plans**: TBD

#### Phase 19: Evaluation / Observability
**Goal**: Brain 质量可验证(§20 Phase 8)
**Depends on**: Phases 17, 18
**Requirements**: BRAIN-08
**Success Criteria** (what must be TRUE):
  1. 投影提案验收率/碎片化率等指标可观测(复用 routingTraces 模式)
  2. Brain 质量评估样本与回归入口,文档更新至 ARCHITECTURE.md
**Plans**: TBD

## Progress

**Execution Order:**
v0.5: 1 ‖ 2 ‖ 3 ‖ 4 ‖ 5(并行)→ 6
v1.0: 7 ‖ 8(并行)+ 9(依赖 5)→ 10 → 11
v1.1: 12 → 13 ‖ 14 ‖ 15(并行)→ 16 → 17 → 18 → 19

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. 信任基线 | v0.5 | 2/2 | Complete | 2026-08-29 |
| 2. Library/Today 补全 | v0.5 | 2/2 | Complete | 2026-08-29 |
| 3. Journal 用户主权 | v0.5 | 1/1 | Complete | 2026-08-29 |
| 4. Onboarding 三步引导 | v0.5 | 2/2 | Complete | 2026-08-29 |
| 5. ReaderAgentBench 最小可用 | v0.5 | 2/2 | Complete | 2026-08-29 |
| 6. 习惯打磨与偏差批量修 | v0.5 | 3/3 | Complete | 2026-08-29 |
| 7. 无障碍与动态字体 | v1.0 | 2/2 | Complete | 2026-08-29 |
| 8. Provider 稳定性 | v1.0 | 2/2 | Complete | 2026-08-29 |
| 9. Bench LLM 评审与回归纪律 | v1.0 | 2/2 | Complete | 2026-08-29 |
| 10. 发布工程与合规 | v1.0 | 2/2 | Complete | 2026-08-29 |
| 11. 首发验收 | v1.0 | 1/2 | In progress | - |
| 12. Brain Domain + Persistence | v1.1 | 1/1 | Complete | 2026-08-29 |
| 13. Brain UI | v1.1 | 0/1 | Planned | - |
| 14. Evidence / Relation | v1.1 | 0/1 | Planned | - |
| 15. Persistent Embedding + BrainRetriever | v1.1 | 0/1 | Planned | - |
| 16. Agent Bridge | v1.1 | 0/1 | Planned | - |
| 17. BrainProjectionService | v1.1 | 0/1 | Planned | - |
| 18. Revision / Evolution | v1.1 | 0/1 | Planned | - |
| 19. Evaluation / Observability | v1.1 | 0/1 | Planned | - |

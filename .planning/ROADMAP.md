# Roadmap: ReadLoop(页外)

## Overview

从已完成的 0.1–0.3 内核(阅读器、Reflection Loop、Memory)出发,分两个里程碑推进到首发:v0.5 补齐信任基线、信息架构、Onboarding、评估集与习惯打磨,达到可公开 TestFlight;v1.0 完成无障碍、Provider 稳定性、LLM 评审回归与发布合规,达到 App Store 标准。每个 phase 对应一个并发 worktree,集成纪律见 `.planning/WORKTREES.md`。

## Milestones

- 🚧 **v0.5 TestFlight 就绪** — Phases 1-6 (进行中)
- 📋 **v1.0 App Store 首发** — Phases 7-11 (已规划)

## Phases

### 🚧 v0.5 TestFlight 就绪 (In Progress)

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

### 📋 v1.0 App Store 首发 (Planned)

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
- [ ] 11-01: UAT/崩溃恢复 checklist 与最终验证
- [ ] 11-02: TestFlight 流程与发布确认

## Progress

**Execution Order:**
v0.5: 1 ‖ 2 ‖ 3 ‖ 4 ‖ 5(并行)→ 6
v1.0: 7 ‖ 8(并行)+ 9(依赖 5)→ 10 → 11

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. 信任基线 | v0.5 | 0/2 | Not started | - |
| 2. Library/Today 补全 | v0.5 | 0/2 | Not started | - |
| 3. Journal 用户主权 | v0.5 | 0/1 | Not started | - |
| 4. Onboarding 三步引导 | v0.5 | 0/2 | Not started | - |
| 5. ReaderAgentBench 最小可用 | v0.5 | 0/2 | Not started | - |
| 6. 习惯打磨与偏差批量修 | v0.5 | 0/3 | Not started | - |
| 7. 无障碍与动态字体 | v1.0 | 0/2 | Not started | - |
| 8. Provider 稳定性 | v1.0 | 0/2 | Not started | - |
| 9. Bench LLM 评审与回归纪律 | v1.0 | 0/2 | Not started | - |
| 10. 发布工程与合规 | v1.0 | 0/2 | Not started | - |
| 11. 首发验收 | v1.0 | 0/2 | Not started | - |

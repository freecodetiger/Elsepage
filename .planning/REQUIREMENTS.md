# Requirements: ReadLoop(页外)

**Defined:** 2026-08-29
**Core Value:** 用户在读完书后愿意持续输出高质量 Reflection,并随时间累积成可回溯的个人思想档案

## v1 Requirements(首发范围)

分两个里程碑交付。每个需求映射到恰好一个 phase。

### Milestone v0.5 — TestFlight 就绪

#### 信任与数据主权

- [x] **TRUST-01**: 用户可在设置中一键清除所有本地数据(书籍与索引、Reflection、Journal、Memory、Provider 配置与 API Key、阅读偏好),带两阶段确认且逐类列明将删除的内容
- [x] **TRUST-02**: Export My Data 导出的 JSON 包含 Memory 与 Reader Profile 派生数据,与 My Mind 中可见内容一致

#### 文档对齐

- [x] **DOCS-01**: PRD 更新至 v0.3,逐条记录已知实现偏差及豁免理由(ASR 仅 Apple 系统、Journal 为 Agent 派生结构+用户编辑入口、移除 Streaming 开关、Model ID 手填等)

#### 信息架构补全

- [x] **LIB-01**: 书架每本书显示阅读时长、Highlight 数、Reflection 数(数据来自现有 sessions/annotations/reflections 表,不新增采集)
- [x] **TODAY-01**: Today 页在存在未完成 Reflection 机会时(如上次 Session 未留 Reflection)显示明确的补写入口

#### Journal 用户主权

- [x] **JRNL-01**: 用户可编辑/确认 Journal 中 Agent 整理的 What I think 条目
- [x] **JRNL-02**: 被用户编辑过的 What I think 条目标记 userEdited,后续 Agent 更新不得静默覆盖

#### Onboarding

- [x] **ONB-01**: 首次启动引导用户导入第一本 EPUB(Files/拖入),成功后进入下一步
- [x] **ONB-02**: Onboarding 内完成 Provider 选择、API Key 配置与 Test Connection,通过后进入下一步(可跳过)
- [x] **ONB-03**: 引导指向第一次阅读与第一次 Reflection;已 onboarded 用户不再看到流程,清数据后重新触发

#### ReaderAgentBench(最小可用)

- [x] **BENCH-01**: 固定评估样本集(书上下文+用户历史+Reflection+检索证据+目标反馈)与运行脚本,可对真实 Provider 跑批并产出基线报告
- [x] **BENCH-02**: 报告覆盖 PRD §16 的 11 个评审维度(人工评分记录),形成首版基线并存档

#### 习惯打磨与偏差修正

- [x] **POLISH-01**: PRD §10.4 列出的关键 Haptics 落地(长按录音、Reflection 完成、新成就、导入完成、关键卡片展开),翻页无震动
- [x] **POLISH-02**: PRD §10.3 列出的关键动效落地(阅读完成、Reflection 完成、Memory 更新、Streak 延续、成就、引用回跳),阅读正文无持续动画
- [x] **POLISH-03**: 各主要界面有空状态与错误状态(含离线/无 Key 时 Agent 不可用的明确文案)
- [x] **FIX-01**: Reading Session 的 agentDiscussionCount 真实累计(用户主动发起 Agent 讨论的次数)
- [x] **FIX-02**: 移除假的 Streaming 开关及相关持久化字段(迁移清理)
- [x] **FIX-03**: Questioner(首次明确质疑作者)与 Changed My Mind(主动修改旧观点)成就解锁逻辑接入现有判定信号

### Milestone v1.0 — App Store 首发

#### ReaderAgentBench(自动化)

- [x] **BENCH-03**: LLM-as-judge 自动评分接入样本集,一键产出 11 维度评分报告
- [x] **BENCH-04**: 回归纪律落地:Prompt/Model/Retrieval 大改时跑 bench 并与基线对比,差异超阈值阻断合并(流程写入贡献指引)

#### 无障碍

- [x] **A11Y-01**: 全部主界面支持 Dynamic Type(含阅读器外的 SwiftUI 界面),布局在大字号下不破碎
- [x] **A11Y-02**: 核心交互(阅读、划线、Reflection、Journal、My Mind)具备 VoiceOver 标签与可达性元素
- [x] **A11Y-03**: 对比度与最小点击区域符合平台无障碍基准

#### Provider 稳定性

- [x] **PROV-01**: Anthropic 原生 `/v1/messages` 客户端(按现状重写,非 OpenAI 兼容代理),与现有 Keychain/配置/测试连接体系一致
- [ ] **PROV-02**: 至少 3 个 Provider(含 OpenAI 兼容系 + Anthropic)由用户真机验证通过,形成验证矩阵记录
- [x] **PROV-03**: Provider 错误路径 UX 完整(无 Key/网络失败/限流/无效响应),不破坏本地 Reflection 保存

#### 发布工程与合规

- [x] **REL-01**: 隐私政策文本完成,如实描述 BYOK 数据流向(API Key 本地、上下文最小化发送)
- [x] **REL-02**: App Review BYOK 路径材料准备完毕(审核备注、Demo 说明),由用户用真实构建验证
- [x] **REL-03**: 版本号/构建号策略、App 图标与元数据就绪
- [ ] **REL-04**: 崩溃恢复验证:强杀/重启后进度、划线、Reflection、Memory 不丢失(用户真机 checklist)
- [ ] **REL-05**: 首发验收:swift test 全绿、bench 基线对比通过、用户按 UAT 清单真机验收、TestFlight 反馈处理流程建立

## v1.1 Requirements(Personal Brain — 我的大脑)

来源:`docs/brain.md`(Brain Domain 规范)。核心原则:Reflection 是原始思考记录,Thought/Question 是从多次 Reflection 中形成的思想结构,Memory 是 Agent 可长期依赖的稳定用户知识;Evidence 是事实,Brain Item 是解释;LLM 提议,代码执行。

- **BRAIN-01**: Brain Domain + Persistence — Thought/Question/Memory 强类型域模型(阶段/状态/来源用封闭枚举,非法状态不可表示),brainItems 表 + 仓储可靠存储,既有 memories 一次性幂等回填
- **BRAIN-02**: Brain UI — 「我的大脑」首页(最近的我 / Thoughts / Questions / Memories 分区)与三类 Item 详情页可浏览、可编辑
- **BRAIN-03**: Evidence / Relation — brainItemEvidence(sourceType/sourceID/relation/weight)与 brainItemRelations(克制的关系集:related/supports/contradicts/evolvesFrom/raises/addresses/derivedMemory)
- **BRAIN-04**: Persistent Embedding + BrainRetriever — brainItemEmbeddings 持久化,lexical + embedding + RRF,按 kinds 过滤,输出 BrainCandidate
- **BRAIN-05**: Agent Bridge — BrainContextProvider 把 Brain Item 适配为 ContextCandidate 进入现有 ContextAssembler;BrainCore 不 import ReaderAgent
- **BRAIN-06**: BrainProjectionService — Reflection 自动更新 Brain:Observation → BrainRetriever 候选 → LLM 强类型 Mutation Proposal → Validator → 事务执行;attach > update > create,createThreshold > attachThreshold;不阻塞 ReaderAgent 主链,Brain 失败不影响 Reflection/回复
- **BRAIN-07**: Revision / Evolution — brainItemRevisions 保留 Thought 演化历史,UI 可展示时间线
- **BRAIN-08**: Evaluation / Observability — Brain 质量可验证(投影提案的验收率、碎片化率),可观测

## v2 Requirements(首发后)

PRD P1/P2 长期功能,当前不在路线图内:

- **P1**: Weekly/Monthly Insight、Historical Recall、观点演变、自动跨书连接发现、30/90 天回顾、iCloud 可选同步、Reader Agent Style 精细化
- **P2**: Wisdom Layer(公版经典/授权知识包/provenance)、Personal Intellectual Graph、Idea Timeline、Year in Ideas
- **真流式输出**(SSE)与云端 ASR Provider 可选化
- 跨书连接专门浏览界面

## Out of Scope

| Feature | Reason |
|---------|--------|
| PRD §17 全部非目标(PDF/OCR/漫画/书城/盗版源/DRM/社交/排行/好友/复杂图谱 UI/多 Agent/Browser Automation/MCP/自建账号/自有推理服务器/自动读后感/复杂 SRS/百万书 RAG) | PRD 明确非目标,防止功能军备竞赛 |
| 真流式输出(SSE) | 本次决策:核心价值在反馈质量不在呈现速度;假开关直接移除 |
| 拉取 Provider 模型列表 | 与「做好而不是全兼容」一致,手填 Model ID 已可用 |
| 书架级全文搜索 | 书内搜索已完备,书架搜索按 PRD 仅书名/作者 |
| Today「今日一句历史回顾」 | PRD 标记 P1,不进首发 |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| TRUST-01 | Phase 1 | Pending |
| TRUST-02 | Phase 1 | Pending |
| DOCS-01 | Phase 1 | Pending |
| LIB-01 | Phase 2 | Pending |
| TODAY-01 | Phase 2 | Pending |
| JRNL-01 | Phase 3 | Pending |
| JRNL-02 | Phase 3 | Pending |
| ONB-01 | Phase 4 | Pending |
| ONB-02 | Phase 4 | Pending |
| ONB-03 | Phase 4 | Pending |
| BENCH-01 | Phase 5 | Pending |
| BENCH-02 | Phase 5 | Pending |
| POLISH-01 | Phase 6 | Pending |
| POLISH-02 | Phase 6 | Pending |
| POLISH-03 | Phase 6 | Pending |
| FIX-01 | Phase 6 | Pending |
| FIX-02 | Phase 6 | Pending |
| FIX-03 | Phase 6 | Pending |
| BENCH-03 | Phase 9 | Pending |
| BENCH-04 | Phase 9 | Pending |
| A11Y-01 | Phase 7 | Pending |
| A11Y-02 | Phase 7 | Pending |
| A11Y-03 | Phase 7 | Pending |
| PROV-01 | Phase 8 | Pending |
| PROV-02 | Phase 8 | Pending |
| PROV-03 | Phase 8 | Pending |
| REL-01 | Phase 10 | Pending |
| REL-02 | Phase 10 | Pending |
| REL-03 | Phase 10 | Pending |
| REL-04 | Phase 11 | Pending |
| REL-05 | Phase 11 | Pending |
| BRAIN-01 | Phase 12 | Pending |
| BRAIN-02 | Phase 13 | Pending |
| BRAIN-03 | Phase 14 | Pending |
| BRAIN-04 | Phase 15 | Pending |
| BRAIN-05 | Phase 16 | Pending |
| BRAIN-06 | Phase 17 | Pending |
| BRAIN-07 | Phase 18 | Pending |
| BRAIN-08 | Phase 19 | Pending |

**Coverage:**
- v1 requirements: 31 total
- v1.1 requirements: 8 total
- Mapped to phases: 39
- Unmapped: 0 ✓

---
*Requirements defined: 2026-08-29*
*Last updated: 2026-08-29 — added v1.1 Personal Brain milestone (docs/brain.md)*

# ReadLoop（工程代号）产品需求文档（PRD）

> 工程代号：**ReadLoop**  
> 正式产品名：**待定**（当前候选：余思 / 页外；正式命名前不要在代码中硬编码品牌名）  
> 产品定位：**以阅读为入口的 Personal Thinking Agent / Agent-native iOS Reader**  
> 文档版本：v0.3  
> 状态：长期主文档（Source of Truth）  
> 首发平台：iOS / iPhone  
> 首发内容格式：用户自导入的非 DRM EPUB  
> 核心 AI 形态：**BYOK（Bring Your Own Key）云端模型 + 本地 Agent Runtime**  
> 最后更新：2026-08-29

---

## 0. 文档使用约定

本 PRD 用于长期产品开发，不是一次性 brainstorm。后续任何新功能都应回答三个问题：

1. 它是否强化“阅读 → 思考 → 输出 → 反馈 → 沉淀 → 再阅读”的主循环？
2. 它是否让用户更愿意真正思考，而不是把思考外包给 AI？
3. 它是否破坏了“阅读时少打扰、本地优先、用户拥有数据、AI 可解释且可控”的产品原则？

若一个需求与本文的“产品不变量”冲突，应先修改 PRD 并记录理由，再改代码；不要让实现细节反向定义产品。

---

# 1. 产品愿景

## 1.1 一句话

**一个让阅读真正留下来的地方。**

ReadLoop 不以“读更多书”为终点，也不把自己定义成“一个带 AI 问答的 EPUB 阅读器”。

它真正要成为的是：

> **一个以阅读为入口、长期陪用户思考的 Personal Thinking Agent。**

传统阅读产品通常结束于：

`打开一本书 → 阅读 → 划线 → 读完`

大量 AI Reader 则增加：

`选中一段 → Ask AI → 解释 / 总结`

ReadLoop 要闭合的是另一条链：

`阅读 → 思考 → 表达 → Agent 反馈 → 追问 → 沉淀 → 连接过去 → 形成长期认知变化`

阅读器的意义，不只是“承载 EPUB”，而是让 Agent 和用户拥有同一份第一手阅读上下文；真正长期积累的产品资产则是用户自己的 Reflection、观点、问题、连接和思想变化。

---

## 1.2 用户真正购买的价值

用户不是为了“AI 总结一本书”安装 ReadLoop。

用户真正需要的是：

- 我读完后不要什么都忘了；
- 我希望有人愿意认真听我说刚刚读到了什么；
- 我希望得到有知识增量、但不卖弄的反馈；
- 我希望有人在合适的时候挑战我的理解，而不是永远夸我；
- 我希望几个月后还能重新找到当时的想法；
- 我希望 AI 越陪我读越懂我；
- 我希望看到自己的观点、知识和思考方式是如何变化的；
- 我希望养成“读完以后说出来/写出来”的习惯；
- 我希望这个过程足够轻松，不像做读书作业。

---

## 1.3 市场定位：不是 AI Reader，而是 Personal Thinking Agent

截至 2026-08-24 的 iOS 市场调研显示，相关产品已经形成几个清晰类别：

| 类别 | 已被验证的需求 | 市场状态 | ReadLoop 的判断 |
|---|---|---|---|
| EPUB / PDF Reader | 好用的移动阅读体验 | 成熟、拥挤 | 必须做到合格，但不是定位 |
| Reader + AI Explain/Summary | 解释、总结、问书 | 快速同质化 | 不作为核心卖点 |
| Reading Tracker / Streak | 坚持阅读、统计阅读 | 成熟 | 学行为设计，不做数据炫耀 |
| Highlight / Notes | 留下划线与笔记 | 成熟 | 是基础数据，不是终点 |
| AI Reading Journal | 读后记录、AI 整理 | 快速升温 | 核心近邻赛道 |
| Voice Reflection | 低成本输出思考 | 很早期 | 应成为 Hero Feature |
| Long-term Reader Memory | AI 记得过去怎么想 | 很早期 | 核心护城河 |
| Reader Profile | AI 理解“我是怎样的读者” | 非常早期 | 重要长期资产 |
| Personal Intellectual Timeline | 观点如何随时间变化 | 几乎空白 | 长期差异化 |
| Reflection Habit | 让“读后输出”成为习惯 | 明显空位 | 最核心行为闭环 |

因此 ReadLoop 的竞争坐标不是：

> “谁的 EPUB 阅读器支持更多格式、谁的 AI 总结更快。”

而是：

> **谁能最稳定地让用户在阅读后产生高质量输出，并让这些输出经过多年积累后成为一份真正有价值的个人思想档案。**

---

## 1.4 核心差异化

### D1. Reading 与 Thinking 在同一个上下文中

近邻产品常见形态：

`Kindle / Apple Books / 微信读书 → 导出 → AI App`

ReadLoop：

`Import → Read → Highlight → Reflect → Discuss → Remember`

减少 Context Switch，并允许 Agent 准确知道用户刚刚读过什么。

### D2. 关心“你怎么想”，而不是只关心“书讲了什么”

大量 AI Reader 的核心问题是：

> Ask your book.

ReadLoop 的核心问题是：

> **What did this book make you think?**

Ask-your-book 是工具能力；理解用户的思考过程才是产品能力。

### D3. 用户自己的思想是第一等数据

产品中最重要的数据优先级：

`User Reflection > User Highlight/Note > Agent Commentary > AI Summary`

长期要积累的是：

- 原始表达；
- Idea；
- Belief；
- Question；
- Changed Mind；
- Cross-book Connection；
- Reader Profile；
- 思想时间线。

### D4. Habit Loop 围绕 Thinking，而不是只围绕 Reading

传统产品奖励：

`读了多久 / 连续多少天 / 读完多少本`

ReadLoop 更关心：

`今天有没有真正输出 / 有没有形成问题 / 有没有建立连接 / 有没有修正旧观点`

核心连续指标是：

**Thinking Streak**

### D5. Agent 是长期关系，不是一次性 Chat

Agent 的价值随着用户历史增加而增加：

`更多 Reflection → 更准确的 Memory → 更相关的连接 → 更好的反馈 → 用户更愿意继续 Reflection`

这构成 ReadLoop 的长期复利。

---

## 1.5 重点竞品与学习对象（2026-08-24）

以下竞品用于产品 benchmark，不意味着逐项复制：

| 产品 | 值得学习 | ReadLoop 不应复制的方向 |
|---|---|---|
| **Avid** | Voice conversation、长期记忆、跨书连接、Weekly/Yearly insight | 阅读与思考仍分离；ReadLoop 应拥有原生阅读上下文 |
| **Canto** | Reader Profile / “Reader's DNA” | 不把画像做成静态标签，应保持 evidence-based、可修改 |
| **Coreader** | Session 后语音输出、Reflection workflow | 避免演化成泛知识工作台 |
| **EchoRead** | 中国用户的知识沉淀、跨书笔记关联 | 不把产品中心变成思维导图/AI 笔记生产 |
| **Quillet / ReadDeep** | 原生 Reader + AI 的产品完成度、BYOK 可行路径 | 避免停留在“Ask your book” |
| **Reeden** | 阅读器完成度、阅读目标与统计 | 不参与格式/云盘功能军备竞赛 |
| **Bookly / Bookmory** | Streak、Timer、低摩擦 Habit Loop | 不用阅读时长和 XP 替代真实思考 |
| **Highlighted** | “让读过的东西留下来”的清晰价值 | ReadLoop 要进一步把 Capture 升级成 Think |

### 竞品结论

ReadLoop 不应该追求“功能最多”，而应该成为：

> **Reader + Reflection Agent + Long-term Intellectual Memory + Thinking Habit 的最佳一体化体验。**

如果未来某项需求无法明显强化这四件事，应默认降级优先级。

# 2. 产品不变量

以下原则优先级高于具体 Feature。

## P1. Don't interrupt reading

**用户读的时候，Agent 默认安静。用户抬头的时候，Agent 在。**

禁止把阅读器做成充满 AI 弹窗、自动解释、自动问答的“智能教材”。

阅读过程中，Agent 的主要入口来自用户主动行为：

- 划线；
- 批注；
- 长按“聊聊这句”；
- 主动打开讨论；
- 主动结束阅读 Session。

主动介入主要发生在 **Session 结束后**。

---

## P2. User output before AI output

ReadLoop 不能把“用户没有思考”包装成“AI 帮用户总结了”。

默认流程应当是：

`用户先说/写 → Agent 再回应`

而不是：

`Agent 先总结 → 用户被动阅读总结`

用户的原始表达是产品最重要的数据资产之一。

---

## P3. Agent extends thinking, not replaces thinking

Agent 应该帮助用户：

- 澄清；
- 连接；
- 追问；
- 质疑；
- 补充背景；
- 回忆旧观点；
- 发现认知变化。

Agent 不应该默认替用户：

- 写读后感；
- 给出“标准感想”；
- 把所有章节总结成模板笔记；
- 为了“有用”而不断输出大量知识。

---

## P4. Wisdom without showing off

Agent 的目标不是“显得知道很多”，而是：

> 在此刻，为这个用户，补充最值得补充的一点。

博学感来自**关联精准**，而不是引用数量。

---

## P5. Local-first & user-owned data

以下数据默认保存在设备本地：

- 导入书籍；
- 阅读进度；
- Reading Session；
- Highlight；
- Note；
- Reflection；
- Agent 对话；
- Reader Profile；
- 长期 Memory；
- Retrieval Index；
- Agent Trace。

V1 不要求 ReadLoop 自有账号，也不要求 ReadLoop 后端服务器。

---

## P6. AI is BYOK, not Apple Intelligence dependent

中国大陆是首要使用场景之一，因此产品不能把核心 AI 能力建立在 Apple Intelligence、Foundation Models 或特定 Apple Intelligence 设备能力上。

用户自行配置第三方 AI 服务商 API Key。

核心产品必须支持：

- 无 ReadLoop 服务器；
- 用户 Key 仅保存在本机安全存储；
- App 直接与用户选择的 AI Provider 通信；
- 更换 Provider 不丢失个人阅读数据和 Agent Memory。

---

## P7. Memory must be visible and correctable

Agent 可以在后台形成读者画像，但不能形成“不可见的秘密画像”。

用户必须能：

- 查看 Agent 记住了什么；
- 查看记忆来自哪些原始证据；
- 标记“不准确”；
- 修改；
- 删除；
- 禁止某些内容进入长期记忆；
- 一键清除 Agent Memory。

---

## P8. Reading habit, not gamification addiction

学习 Duolingo 的是：

- 极低启动成本；
- 每次打开都有清晰下一步；
- 即时反馈；
- 连续行为强化；
- 成长可见；
- 中断后容易回来。

不要机械复制：

- 过度金币；
- 宝箱；
- 诱导排行；
- 高频通知；
- 让用户为了 XP 刷无意义行为。

我们奖励“思考行为”，不只是“阅读时长”。

---

## P9. Thinking is the product moat

阅读器、AI 解释、摘要、格式支持都很容易被复制。

ReadLoop 长期真正要积累的是：

1. 用户愿意持续 Reflection 的行为习惯；
2. 用户多年累积的原始思想档案；
3. Evidence-based Personal Intellectual Memory；
4. 能正确使用这些历史的 Reader Agent Policy；
5. “过去的我 ↔ 当前的我 ↔ 当前这本书”之间的高质量连接。

因此任何资源冲突时，优先级遵循：

`Reflection Quality > Memory Quality > Reader Agent Quality > Habit Loop > Reader Feature Breadth`

# 3. 目标用户

## 3.1 首批核心用户

优先服务：

- 18–35 岁；
- 有稳定阅读习惯或明确想建立阅读习惯；
- 经常使用 EPUB；
- 对 AI 有一定接受度；
- 希望把阅读转化为成长，而不仅是娱乐；
- 愿意在读后花 1–5 分钟说出自己的想法；
- 能接受 BYOK 作为早期产品门槛。

典型人群：

- 大学生；
- 研究生；
- 知识工作者；
- 程序员；
- 产品经理；
- 内容创作者；
- 长期阅读非虚构/文学/社科的读者。

---

## 3.2 暂不优先服务

V1 不针对：

- 主要阅读漫画的用户；
- 需要复杂 PDF 论文标注的科研用户；
- 只需要听书的用户；
- 想购买电子书内容的用户；
- 只想让 AI 替自己总结、不愿输出的用户。

---

# 4. 核心 Job-to-be-Done

## JTBD-1：阅读

> 当我获得一本 EPUB 时，我希望可以直接在一个体验优秀的 iOS 阅读器里长期阅读，并且进度、划线和批注都属于我自己。

## JTBD-2：输出

> 当我刚读完一段内容时，我希望能用最低成本把脑子里的想法说出来，而不是逼自己写一篇正式读书笔记。

## JTBD-3：获得高质量反馈

> 当我说出一个尚不成熟的想法时，我希望得到像一位博学但尊重我的读者一样的回应，让我往前多想一层。

## JTBD-4：被理解

> 当我长期使用后，我希望 Agent 记得我以前读过什么、说过什么、在哪些主题上经常思考，而不需要每次重新解释自己。

## JTBD-5：回看成长

> 当几个月或几年过去后，我希望看到自己的观点如何变化，而不是只看到“今年读了 37 本书”。

## JTBD-6：形成习惯

> 当我结束阅读时，我希望 App 自然推动我完成一次 1–3 分钟的输出，让“读完以后想一想”逐渐成为习惯。

---

## JTBD-7：形成个人思想档案

> 当我使用几个月或几年后，我希望这里保存的不是一堆 AI 总结，而是我自己真正说过、想过、质疑过、改变过的东西，并且能够重新回到当时的原始证据。

# 5. 核心产品循环

```text
导入一本书
    ↓
开始阅读
    ↓
Reading Session
    ├── 翻页
    ├── Highlight
    ├── Note
    └── 主动提问（可选）
    ↓
结束 Session
    ↓
低摩擦 Reflection
    ├── 语音
    └── 文字
    ↓
Agent 反馈
    ├── 理解
    ├── 点评
    ├── 知识补充
    ├── 跨书/历史连接
    └── 一个值得继续想的问题
    ↓
用户继续对话（可选）
    ↓
生成 Reading Journal
    ↓
长期 Memory / Reader Profile 更新
    ↓
未来阅读时重新利用
```

产品是否成立，最重要的验证点不是“Agent 回答是否很长”，而是：

> **用户读完 20 分钟后，会不会愿意再花 2 分钟输出，并且觉得这 2 分钟值得。**

---

# 6. 信息架构

V1 建议采用 4 个一级入口：

## 6.1 Today

今天真正需要做什么。

包含：

- 当前正在读的书；
- 今日阅读进度；
- Reading Streak；
- Thinking/Reflection Streak；
- 未完成的 Reflection；
- “继续阅读”主按钮；
- “聊聊刚才读的”主入口；
- 今日一句高质量历史回顾（P1）。

Today 不是数据 Dashboard，而是 Next Action 页面。

---

## 6.2 Library

用户拥有的书。

包含：

- 导入 EPUB；
- 封面；
- 作者；
- 进度；
- 最近阅读；
- 阅读时长；
- Highlight 数；
- Reflection 数；
- 搜索；
- 排序。

V1 不做线上书城。

---

## 6.3 Journal

不是普通 Notes List，而是用户的“阅读思想档案”。

一条 Journal Entry 应展示：

- 日期；
- 书籍；
- 阅读章节/位置；
- 本次阅读时长；
- 本次用户原始输出；
- Agent 整理出的核心观点；
- 有价值的 Agent Commentary；
- Agent Question；
- 用户后续回答；
- 本次关联的 Highlight；
- 关联的旧 Reflection；
- 形成/修改的 Memory。

---

## 6.4 My Mind

长期个人阅读档案与 Reader Profile。

V1/P1 包括：

- 读过的书；
- Reflection 历史；
- 主题兴趣；
- Agent 记忆；
- Agent 眼中的我；
- 可修改/删除记忆。

长期演化为：

- Idea Timeline；
- **Personal Intellectual Timeline**；
- Concept Graph；
- “Changed My Mind”；
- 跨书连接；
- 年度思想回顾；
- 某个主题上的观点演变；
- “哪些书真正改变过我”；
- “哪些问题我反复提出但一直没有解决”。

My Mind 的产品目标不是做另一份 Obsidian Graph，而是回答：

> **过去的我到底是怎么想的？今天的我哪里已经不一样了？**

---

# 7. V1 功能需求

---

## F1. EPUB 导入与书架

### 用户能力

用户可通过：

- Files；
- iCloud Drive；
- Share Sheet；
- AirDrop 后“用 ReadLoop 打开”；

导入非 DRM EPUB。

### 系统行为

导入时：

1. 校验文件可读取；
2. 计算内容指纹避免重复；
3. 解析 metadata；
4. 生成书籍记录；
5. 保存到 App Sandbox；
6. 后台建立全文索引；
7. 索引未完成也应允许先阅读。

### V1 不支持

- DRM 破解；
- 在线盗版书源；
- MOBI/AZW；
- PDF；
- 漫画；
- 在线书城。

---

## F2. 阅读器

V1 阅读器至少支持：

- 分页/滚动模式二选一时优先分页；
- 字号；
- 行高；
- 页边距；
- 明/暗主题；
- 章节导航；
- 阅读进度；
- Highlight；
- Note；
- 文本选择；
- 搜索；
- 跳转到 Highlight/Agent Citation；
- 恢复上次位置。

核心要求：**阅读器本身必须达到“长期愿意使用”的完成度，不能只是 Agent Demo 的容器。**

---

## F3. Reading Session

一次连续阅读形成一个 Session。

记录：

- bookID；
- start/end time；
- start/end locator；
- 阅读时长；
- 新增 Highlight；
- 新增 Note；
- 用户主动与 Agent 讨论的次数。

禁止 V1 默认记录过于侵入性的精细行为，例如每个段落精确停留时长。

未来若使用“返回某段、多次查看”等弱信号，应：

- 明确说明；
- 只用于提升本地体验；
- 提供关闭能力；
- 不把弱信号直接当作确定事实。

---

## F4. Session Ending

用户主动结束阅读，或退出长时间后，再回到 App 时可以触发 Session Ending。

推荐 UI：

```text
今天读了 24 分钟
进度 37% → 42%
留下 3 个高亮

有什么留下来了吗？

[ 按住说 ]
[ 写一点 ]
[ 今天先不了 ]
```

原则：

- 不制造负罪感；
- “跳过”始终清晰可见；
- 默认 Reflection 时间预期为 1–3 分钟。

---

## F5. Voice / Text Reflection

用户可：

- 长按录音；
- 点击开始/结束；
- 看到实时或准实时转录；
- 编辑转录；
- 使用纯文字输入。

保存：

1. 原始用户文本；
2. 可选的音频文件；
3. 时间；
4. 当前书籍上下文；
5. 当前 Session；
6. 关联 Highlight。

默认建议：

- 原始音频可由用户选择“不保存”；
- Transcript 是 Reflection 的核心持久数据。

---

## F6. Reader Agent Feedback

Agent 回应不是固定模板，但应符合以下内部教学策略。

### 第一步：判断用户当前行为

用户更接近：

- 复述；
- 理解；
- 联想；
- 质疑；
- 形成观点；
- 情绪反应；
- 提问；
- 应用到现实。

### 第二步：选择最有价值的动作

候选：

- 鼓励；
- 澄清；
- 补充；
- 举例；
- 连接；
- 反驳；
- 苏格拉底式追问；
- 提醒旧观点；
- 保持安静。

### 第三步：控制输出

默认一次回应：

- 先准确回应用户；
- 最多补充 1–2 个真正相关的知识连接；
- 最多提出 1 个值得继续思考的问题。

禁止：

- 一次列 8 个延伸知识；
- 永远“你思考得太深刻了”；
- 为了展示博学而引用大量作者；
- 频繁把简单情绪强行哲学化；
- 把用户每次表达都纠正成教科书答案。

---

### 第四步：判断“这次是否值得继续说”

Agent 不应默认每次都展开长讨论。

允许的高质量结果包括：

- 简短确认 + 一个精准追问；
- 指出用户仍在复述，没有形成自己的判断；
- 提供一个反例；
- 只补充一个背景事实；
- 明确表示“这里暂时不需要分析更多”；
- 对纯情绪体验给予空间，而不是强行知识化。

“少说但说得对”优先于“每次都显得很聪明”。

## F7. Book Context

Agent 在讨论当前阅读内容时，应优先获得：

- 用户刚刚阅读的章节/区间；
- 本 Session Highlight；
- 本 Session Note；
- 当前 Book 的全文检索结果；
- 本书已有 Reflection。

用户不需要重复粘贴上下文。

---

## F8. Personal Context

Agent 可检索：

- 用户过去 Reflection；
- 用户旧 Highlight/Note；
- Reader Profile；
- 长期 Memory；
- 过去对相同概念的观点。

当 Agent 使用旧记忆时，UI 应允许用户点击回到证据源。

例：

> “你在 6 月读《局外人》时曾经说过……”

点击可进入原 Reflection。

---

## F9. Reading Journal

每次 Reflection 完成后自动生成一条 Journal。

推荐结构：

### What I said

保留用户原始表达，不被 AI 覆盖。

### What I think

Agent 可将用户表达整理成 1–3 条短观点，但必须忠于用户。

### Our conversation

保存真正有价值的交流。

### Connections

可链接：

- 当前书原文；
- 过去 Reflection；
- 其他用户导入书籍；
- 外部知识来源。

### Question left open

本次仍值得继续想的问题。

---

## F10. Reader Memory

Memory 分为：

### Episodic

发生过什么。

例如：

> 2026-08-24 读《置身事内》时讨论了地方财政。

### Semantic

用户已经形成的稳定理解。

例如：

> 用户已理解“激励结构可以在没有恶意的情况下导致系统性结果”。

### Preference

讨论偏好。

例如：

> 用户更喜欢具体反例而不是抽象鼓励。

### Open Question

尚未解决但值得长期追踪的问题。

### Profile Trait

长期模式。

例如：

> 用户经常能进行跨领域类比，但有时对因果证据要求不足。

Memory 必须包含：

- claim；
- confidence；
- createdAt；
- updatedAt；
- evidence IDs；
- status；
- userEdited flag。

---

## F11. “AI 眼中的我”

用户可查看 Agent 当前形成的 Reader Profile。

UI 语言必须避免“心理诊断”感，定位为：

> “这是我目前从我们的阅读与讨论中形成的理解。”

每条支持：

- 准确；
- 不准确；
- 修改；
- 忘记；
- 查看依据。

禁止推断或展示不必要的敏感人格/健康/政治身份标签。

---

## F12. Habit Loop

V1 建议只做两个核心连续指标：

### Reading Streak

今天是否发生有效阅读。

### Thinking Streak

今天是否完成一次有效 Reflection。

Thinking Streak 是核心差异化。

---

## F13. Achievement

只奖励有意义的认知行为。

可选首批：

- First Reflection：第一次输出；
- Connector：第一次主动联系两本书；
- Questioner：第一次明确质疑作者；
- Changed My Mind：主动修改旧观点；
- Seven Days Thinking：连续 7 天 Reflection；
- Return to an Idea：重新讨论 30 天前的观点。

Achievement 不应影响 Agent 对内容质量的判断。

---

# 8. P1 / P2 长期功能

## P1：Memory & Growth

- Weekly Insight；
- Monthly Insight；
- “AI 眼中的我”成熟版；
- Historical Recall；
- 用户观点演变；
- 自动发现跨书连接；
- 一键回顾 30/90 天前想法；
- iCloud/CloudKit 可选同步；
- 更精细的 Reader Agent Style。

---

## P2：Wisdom Layer

引入受控的外部知识层：

- 公版经典作品；
- 合法授权知识包；
- 作者背景；
- 思想流派；
- 历史上下文；
- 哲学/经济/文学核心概念；
- 可追溯出处。

要求：

- 外部知识不是越多越好；
- 必须优先当前书和个人历史；
- 所有事实/引用尽可能具备 provenance；
- 现代版权作品不得未经授权直接打包全文。

---

## P2：Personal Intellectual Graph

图谱核心实体：

- Book；
- Author；
- Highlight；
- Reflection；
- Idea；
- Concept；
- Question；
- Belief；
- Memory。

典型查询：

- 我过去一年最常思考什么？
- 我对“自由”的理解发生了什么变化？
- 哪些书真正改变了我的观点？
- 哪些问题被我重复提出但还没有答案？
- 哪些作者的观点经常被我认同/反对？

---

# 9. Agent 人格规范

Agent 是：

> 一位读过大量作品、好奇、克制、尊重用户、不急于展示自己、愿意认真听人说话的长期阅读伙伴。

## Agent 应该

- 首先理解用户；
- 区分“情绪体验”和“事实判断”；
- 能承认不确定；
- 能提出反例；
- 能告诉用户“这里可能理解错了”；
- 能说“这次没有必要分析这么多”；
- 能记得过去；
- 能在引用历史时给出证据；
- 根据用户水平调整讨论深度；
- 逐渐形成稳定但可修改的个人化风格。

## Agent 不应该

- 过度恭维；
- 用长文压住用户；
- 每次强行给建议；
- 把所有内容都联系到哲学；
- 把模型预训练知识冒充书中原文；
- 把推测冒充用户稳定人格；
- 擅自代表用户写正式观点；
- 通过制造焦虑提高留存。

---

# 10. 高级交互与视觉原则

## 10.1 视觉目标

关键词：

- 高级；
- 安静；
- 温暖；
- 有触感；
- 有成长感；
- 不幼稚；
- 不像 ChatGPT Wrapper；
- 不像传统效率 Dashboard。

可以学习 Duolingo 的行为设计，但不能视觉抄袭。

---

## 10.2 Agent 不应被关在 Chat Tab

Agent 应该散布在整个体验中：

- Session Ending；
- Highlight 旁；
- Journal；
- My Mind；
- Weekly Insight；
- Historical Recall。

“聊天页”只是其中一个容器，不是产品本体。

---

## 10.3 动效

动效重点用在：

- 阅读完成；
- Reflection 完成；
- 思想沉淀；
- Memory 更新；
- Streak 延续；
- Achievement；
- 从 Agent Citation 跳回原文；
- Idea Timeline 展开。

不要用持续动画干扰阅读正文。

---

## 10.4 Haptics

建议用于：

- 长按开始录音；
- Reflection 完成；
- 新 Achievement；
- 书籍导入完成；
- 关键卡片展开。

避免每次翻页震动。

---

# 11. Onboarding

首轮 Onboarding 不应超过三个目标：

1. 导入第一本 EPUB；
2. 配置 AI Provider；
3. 完成第一次阅读 + Reflection。

建议流程：

```text
欢迎
↓
“把一本你正在读的书带进来”
↓
Import EPUB
↓
配置 AI
↓
Test Connection
↓
打开书
↓
阅读
↓
结束 Session
↓
第一次 60 秒 Reflection
↓
Agent 第一次反馈
```

**第一次感受到 Agent 价值的时间必须尽量短。**

---

# 12. AI Provider UX

用户需要提供自己的 API Key。

Settings 至少包括：

- Provider；
- Base URL（高级）；
- API Key；
- Model；
- Test Connection；
- Streaming 开关（调试/兼容）；
- 删除 Key；
- 查看本次请求使用了哪些阅读数据。

V1 推荐先支持少量 Provider，做好而不是全兼容：

1. OpenAI；
2. Anthropic；
3. Gemini；
4. DeepSeek / OpenAI-compatible。

产品中不要提供绕过 App Store 规则的外部数字服务购买流程；BYOK 的 App Store 审核路径需要在 TestFlight/首发前独立验证。

---

# 13. 隐私与信任

## 13.1 默认原则

- EPUB 原文件默认仅本地；
- Reading History 默认仅本地；
- Reflection 默认仅本地；
- Agent Memory 默认仅本地；
- Provider API Key 仅本地安全存储；
- 仅为完成当前 AI 请求发送“必要上下文”到用户选择的 Provider；
- 不把整本书默认上传给模型；
- 不上传与当前请求无关的历史。

---

## 13.2 AI 请求前的 Context Minimization

每次模型请求：

1. 本地检索；
2. 选择必要证据；
3. 本地组装上下文；
4. 仅发送选中的文本；
5. 记录本地 trace；
6. UI 可解释“这次使用了哪些内容”。

---

## 13.3 数据控制

提供：

- Export My Data；
- Delete Book & Index；
- Delete Reflection；
- Delete Memory；
- Reset Reader Profile；
- Delete All Local Data。

---

# 14. 离线行为

没有网络或没有 API Key 时，App 仍必须是一个完整 EPUB 阅读器。

可继续：

- 导入；
- 阅读；
- Highlight；
- Note；
- 阅读进度；
- 文字 Reflection；
- 查看历史。

不能进行：

- AI Feedback；
- AI Memory 提炼；
- 云端 ASR（如果当前 Transcription Provider 是云端）；
- Semantic Retrieval（若依赖远端 embedding）。

离线产生的数据待未来联网后再处理，但不能阻塞用户阅读。

---

# 15. 成功指标

由于 V1 local-first 且无自有服务器，产品指标首先应支持**本地统计和 TestFlight 用户自愿诊断导出**；后续是否加入遥测应单独做隐私决策。

## North Star

**Weekly Meaningful Reflections per Active Reader**

不是阅读时长，不是 Agent 消息数量。

---

## 激活

- 导入第一本书成功率；
- Provider 配置成功率；
- 首次打开书率；
- 首次完成 Reflection 率；
- Time to First Valuable Feedback。

---

## 核心循环

- Reading Session → Reflection 转化率；
- Reflection 平均时长；
- 用户回答 Agent 追问比例；
- 每周有效 Reflection 数；
- Reflection 7 日留存；
- Thinking Streak 形成率。

---

## Agent 质量

用户可轻量反馈：

- 有启发；
- 一般；
- 没理解我；
- 太啰嗦；
- 太爱夸；
- 事实有误。

长期核心指标：

- Relevant Knowledge Gain；
- Follow-up Rate；
- Memory Correction Rate；
- Citation Open Rate；
- “这个回应值得我停下来想一想”的主观评分。

---

# 16. ReaderAgentBench

为了让 Agent 真正“有智慧”，建立固定 Evaluation Harness。

每个样本包含：

- 当前书上下文；
- 用户历史；
- 当前 Reflection；
- 可用检索证据；
- 目标反馈。

评价维度：

| 维度 | 说明 |
|---|---|
| 理解用户 | 是否抓住用户真正表达的意思 |
| 理解书籍 | 是否尊重当前上下文 |
| 知识准确 | 是否出现错误事实/伪引用 |
| 知识增量 | 是否真的增加了值得知道的内容 |
| 连接质量 | 跨书/跨概念连接是否自然且相关 |
| 个性化 | 是否合理使用用户历史 |
| 追问质量 | 是否真的推动继续思考 |
| 克制 | 是否避免无意义扩写 |
| 恭维控制 | 是否避免“无脑夸” |
| 可追溯性 | 关键陈述能否指向证据 |
| 用户自主 | 是否仍然让用户自己形成观点 |

任何 Agent Prompt / Model / Retrieval 大改，都应跑回归集。

---

# 17. V1 非目标

竞品调研表明，“支持更多格式 / 更多云盘 / AI 摘要 / AI 翻译 / Mind Map”非常容易把产品拖进成熟 Reader 的功能军备竞赛。

为了保证首发质量，明确不做：

- PDF；
- OCR；
- 漫画；
- 在线书城；
- 盗版书源；
- DRM 绕过；
- 社交社区；
- 排行榜；
- 好友系统；
- 复杂知识图谱 UI；
- 多 Agent；
- Browser Automation；
- MCP 大生态；
- 自建账号系统；
- ReadLoop 自有推理服务器；
- 自动替用户生成完整读后感；
- 复杂间隔重复系统；
- “百万本书全文 RAG”。

---

# 18. 版本路线

## 0.1 Reader Foundation

目标：成为可用 EPUB Reader。

- Import；
- Library；
- Reader；
- Progress；
- Highlight；
- Note；
- Search。

---

## 0.2 Reflection Loop

目标：验证“读完后愿意输出”。

- Reading Session；
- Session Ending；
- Text Reflection；
- Voice Reflection；
- BYOK；
- Agent Feedback；
- Journal。

---

## 0.3 Memory

目标：验证“越用越懂我”。

- Long-term Memory；
- Reader Profile；
- “AI 眼中的我”；
- Evidence；
- Memory edit/delete；
- Personal Retrieval。

---

## 0.5 Habit & Polish

目标：达到可公开 TestFlight 水准。

- Today；
- Reading Streak；
- Thinking Streak；
- Achievement；
- Advanced animation；
- Haptics；
- Empty/error states；
- Agent evaluation。

---

## 1.0 App Store

首发标准：

- 阅读器可作为独立产品使用；
- Reflection Loop 稳定；
- 至少 3 个模型 Provider 稳定；
- API Key 安全；
- App 无 ReadLoop 后端依赖；
- Memory 可查看/修改/删除；
- AI 请求数据范围透明；
- 崩溃恢复；
- 隐私政策；
- EPUB 版权边界清晰；
- 完整无障碍和动态字体基础支持；
- App Review BYOK 路径已用真实构建验证。

---

## 1.x Wisdom

- Curated Knowledge Pack；
- Public Domain RAG；
- Better Cross-book Connections；
- Weekly/Monthly Insight；
- Historical Recall。

---

## 2.0 My Mind

- Intellectual Timeline；
- Concept/Idea Graph；
- Changed My Mind；
- Year in Ideas；
- Cross-device optional sync。

---

# 18.1 产品级竞品验收基准

V1 不要求在所有维度击败成熟阅读器，但必须做到：

### Reader

达到“用户愿意连续读一本完整 EPUB”的水平，而不是 Demo 水平。

### Reflection

比“打开独立 AI App 再聊”明显少步骤；结束阅读后 3 次交互以内进入语音/文字 Reflection。

### Agent

一次高质量反馈应明显区别于通用 ChatGPT：

- 知道刚才读了什么；
- 知道用户自己的表达；
- 需要时能引用旧历史；
- 不默认总结；
- 不机械恭维；
- 有明确知识增量或思考推动。

### Memory

用户使用一个月后，应开始出现：

> “它真的记得我以前怎么想。”

而不仅是：

> “它记得我读过哪些书。”

### Habit

Thinking Streak 的存在感不能弱于 Reading Streak。

如果用户只用它读书而几乎不输出，产品核心循环尚未成立。

# 19. V1 关键验收标准

## 阅读

- 用户可以导入一份合法 EPUB 并开始阅读；
- 重启 App 后准确恢复位置；
- Highlight/Note 不丢失；
- Agent Citation 能跳回对应原文位置。

## Reflection

- 用户可在结束 Session 后 3 次点击以内开始语音或文字输出；
- 用户原始表达永久优先展示；
- AI 出错不影响 Reflection 保存；
- 无网络时可先完成 Reflection。

## Agent

- Agent 能获得本次 Session 上下文；
- Agent 可检索当前书；
- Agent 可检索个人历史；
- 默认反馈不超过合理长度；
- 关键引用可以回到证据；
- Model Provider 可替换而不影响 Memory/Journal。

## Memory

- 新 Memory 有 Evidence；
- 用户可查看、修改、删除；
- 删除原 Reflection 后，其派生 Memory 应重新标记或删除；
- 重建 Index 不应改变用户原始数据。

## Privacy

- API Key 不以明文形式出现在数据库/日志；
- 不存在 ReadLoop 自有推理后端；
- 模型请求仅直连用户选择的 Provider；
- 用户能清除所有本地数据。

---

# 20. 最重要的产品判断

ReadLoop 最终不是要证明：

> AI 可以把一本书总结得多好。

也不是要证明：

> 我们可以再做一个功能更多的 EPUB Reader。

而是要证明：

> **AI 可以让一个人在读完之后多思考两分钟，并且这两分钟随着时间累积，逐渐形成一份真正属于自己的思想档案。**

产品真正的长期资产应该按这个顺序理解：

`原始 Reflection → Personal Intellectual Memory → Reader Agent Relationship → Thinking Habit`

阅读器、RAG、向量检索、知识库、Streak、年度回顾都是为了强化这个闭环。

如果用户愿意一直读，却不愿意在这里表达和思考，ReadLoop 只是一个 Reader。

如果用户愿意持续 Reflection，并开始因为 Agent 记得“过去的自己”而回来，产品才真正成立。

---

# 21. 实现偏差与豁免记录（v0.3）

以下偏差已在实现评审中接受并豁免。按 §0 约定先记录于本节，再做对应代码改动。每条包含偏差内容与豁免理由；后续版本如推翻某条豁免，应先修订本节再改代码。

## 21.1 ASR 仅 Apple 系统转写

- 偏差：§14 列出「云端 ASR（如果当前 Transcription Provider 是云端）」的条件分支；V1 没有云端 ASR Provider，语音输入只使用 Apple 系统 SFSpeechRecognizer。
- 豁免理由：首发闭环够用，系统转写本地优先，与 §13 隐私默认一致。云端 ASR Provider 可选化移至 v2。

## 21.2 Journal 为 Agent 派生结构

- 偏差：F9 的 Journal 中 What I think 当前由 Agent 结构化整理（JournalStructuredParser）派生，实现尚无用户编辑入口。
- 修订（F9 语义澄清）：What I think 由 Agent 起草、用户可改，用户编辑优先。用户编辑入口（含 userEdited 标记与防静默覆盖）在 v0.5 交付；What I said 原始表达始终不可被 Agent 覆盖。

## 21.3 移除 Streaming 开关

- 偏差：§12 设置项中的「Streaming 开关（调试/兼容）」不再提供。
- 豁免理由：流式非核心循环，回应长度由系统提示词约束；保留一个模拟流式的开关只会给用户错误预期。真流式输出（SSE）移至 v2。

## 21.4 Model ID 手填而非拉取模型列表

- 偏差：Provider 设置不拉取服务商模型列表，由用户按服务商控制台手填 Model ID。
- 豁免理由：与 §12「做好而不是全兼容」一致；手填已可用，列表拉取属于接口兼容性投入，暂无必要。

## 21.5 Reading Session 行为记录最小化

- 偏差：Reading Session 不记录 agentDiscussionCount 之外的精细行为（滚动、选中、检索触发等）。
- 豁免理由：精细行为采集暂无对应产品决策，不做无用途的数据积累。agentDiscussionCount 自 v0.5 起真实累计（用户主动发起 Agent 讨论的次数）。

## 21.6 书架级搜索仅书名/作者

- 偏差：书架级搜索仅匹配书名与作者，不做书架级全文搜索；书内全文搜索已支持。
- 豁免理由：书架级全文搜索与书内搜索能力重复且成本高，不进首发。

## 21.7 语音转写润色为默认增强

- 偏差：语音 Reflection 的转写润色（TranscriptPolishService）作为默认可用的增强提供；原始转写文本永久保留、优先展示，且可随时切换回原始版本。
- 豁免理由：与 P2「User output before AI output」一致——originalText 是唯一事实源，润色只是不覆盖原文的展示层。

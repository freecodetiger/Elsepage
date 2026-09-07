# ADR 0002: Client interaction-performance architecture（工作包 A–F）

> 定案（2026-09-05）：方向经产品负责人逐项确认。范围、档位与基线来源见文内 Decision；细节规格以 `docs/INTERACTION_PERFORMANCE_SPEC.md` 为准，进度以 `docs/exec-plans/active/client-interaction-performance.md` 为准。

Status: accepted
Date: 2026-09-05

## Context

用户报告客户端交互经常卡顿，集中在三处：**首次打开阅读器**、**首次唤起输入法**、**会话里长按做跨行文本选区**。

代码调研结论（证据索引见 spec 附录）：**不是 MVVM/MVC 架构模式选错，而是三类结构性原因的表现**：

1. **正文排版在主线程整串重算、且不缓存**——每个 Agent 消息是一个自报高度的 UIKit `UITextView`，`intrinsicContentSize` 每次被查询都对整段文本 `boundingRect` 量高；流式输出时每个 text delta 又对整串重跑 Markdown 解析 + 重建富文本 + 整串重测，单条长回复近似 O(n²)。
2. **首帧前串行执行大量可后置的工作**——阅读器把 `open(EPUB)`、DB 四连查、highlights/notes 加载全排在 `isPrepared` 门闩后；navigator 真正出第一页之前没有就绪信号或盖板。
3. **可观测性空白**——全仓无一处 `os_signpost`/MetricKit，也没有 UI 性能测试 target，"卡不卡"停留在体感层面。

同时确认了**已正确离主、不得回改**的部分：GRDB 仓库全走 `await db.writer.read/write` 异步重载（主线程不阻塞，仅冷启动迁移例外）；Agent 流式产出端在后台 executor，主 actor 只 `for await` 消费。

## Decision

按六个工作包推进（P1–P5 原则见 spec §2.3）：

- **A 文本/测量子系统**——统一 `MessageText` 组件族 + `TextMeasureCache` + `RichTextBuilder`；测量与富文本结构解析各做一次、其余查表。**迁移面 = 最小面：仅会话（ReflectionConversation）与档案（Thoughts 展开块）正文，含流式**。MyMind/Today/journal 预览与普通 `.textSelection` 短文本轮不迁。
- **B 流式增量输出**——消费端对 textDelta 做**去抖合并**后解析；剥 citation 块、`.completed` 清空切持久消息、自动滚动语义保持不变。**纯增量文本缓冲留二期**（默认不做）。
- **C 阅读器打开管线**——门闩改为 `open(EPUB) ∥ position+preferences`（highlights/notes/markOpened 揭盖后置）；就绪信号用**首次 `locationDidChange`**（Readium 无公开首帧回调）；Publication 按书缓存 + 后台预取。**解析移出主执行器为门控实验**：前置条件 `Publication`/`Asset` 并发安全（R1），不满足则保持主执行器解析 + 盖板兜底。
- **D 键盘/聚焦滚动**——聚焦与滚动解耦为**键盘 frame 驱动**的小范围滚动，去整树 `withAnimation scrollTo`；两处自动聚焦 sheet（`JournalThoughtEditor`、Reader `NoteEditor`）改为呈现完成后再聚焦；safe-area/keyboard 变化不使 A 的测量缓存失效。
- **E 主 actor 并发接缝**——五条红线规则落库（Model 无 >ms 级同步 CPU 段、最小失效面、首帧门闩只放硬依赖、UIKit 桥不做 O(n) 全量、禁止"整串×每事件"循环）；冷启动 DB 迁移离主为 P2，由阶段 0 基线决定是否本轮做。
- **F 性能回归护栏**——从零建：`PerfSignposts`（`os_signpost`）+ 里程碑指标表 + Diagnostics 屏打点扩展 + 确定性单测（缓存命中/去抖等价进 `swift test`）；可选 Xcode UI target。基线来源：**真机**配合采基线，阈值先采 2–4 周再定预算。

非目标（即便"不计成本"也不做）：不替换 MVVM 架构、不引 TCA/Redux、不把 SwiftUI 重写为 UIKit、不拆模块/每层加协议、不把会话改写为 UICollectionView 级复用、不动 `BrainDiscussionSheet`（当前无展示点的死路径）等——理由见 spec §2.2。

## Consequences

- 用户可见收益按阶段兑现：阶段 1–2（A+B）吃掉会话选区与流式 stutter，阶段 3（C）消掉阅读器首开假死，阶段 4（D）降键盘与聚焦抢道，阶段 5（E-P2）可再收启动。
- 阶段 0 必须先于 A–D：不埋点则收益无法量化、也无法防退化；回滚定义为移除打点（永久保留的护栏，不改变行为）。
- 各阶段可独立提交、可单阶段 git revert；交互/标注的 UI 语义不受影响（仍受 `docs/READER_EXPERIENCE_OPTIMIZATION_PLAN.md` 约束）。
- 新增确定性单测进入现有 `swift test` 体系；不引入 UI 测试作为唯一依赖（易 flaky）。

## Rejected alternatives

- **全站正文统一到 MessageText**：触及面与回归面过大，而 MyMind/Today 等并不在卡点热路径上；本轮拒，按需二期接入。
- **B 直接上纯增量缓冲**：需处理跨 delta 的 markdown 块（开标签在上一 chunk、闭标签在下一 chunk），复杂度与风险高；去抖合并已在阈值内达标签，拒到二期。
- **把 Readium 解析直接搬离主线程**：产物跨线程迁移的并发安全未证实（R1），不能以正确性赌手感；先做缓存/盖板，离主作为门控实验。
- **用 XCUITest 的 measure 作为唯一回归依赖**：UI 测试 flaky；护栏主力是真机 Instruments + app 内打点 + 确定性单测。
- **把键盘首次唤起总耗时当作 App 预算**：大头在系统键盘/IME 冷启动；D 的验收分系统/App 两段计量，App 只消"不抢道 + 不整树重排"。

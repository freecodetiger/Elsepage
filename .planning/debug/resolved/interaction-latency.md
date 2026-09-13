---
status: resolved
trigger: 用户感到输入法和长按多选文本启动延迟，要求增加埋点后自行手测
created: 2026-09-12
updated: 2026-09-13
---

## Current Focus
status: resolved
root_cause: 自定义 `keyboardDidChangeFrame` 处理在系统键盘动画完成后再次执行无动画 `scrollToBottom`，形成可见二次校正/回落。
fix: 移除晚到的强制滚动，保留底层键盘观测；system keyboard avoidance 与 `.defaultScrollAnchor(.bottom)` 接管布局。
verification: 修复后连续四次开关键盘无回落，用户确认 composer 正常；普通冷启动键盘无 ≥50ms 主队列阻塞。

## Symptoms / Evidence
- 用户截图：keyboard 2 次均 305ms 峰 435ms；textMeasure 88 次均 0.6ms 峰 3ms；存活视图 22。
- 手测由用户执行；App UIKit 路径不由 swift test 编译或验证。
- 本次目标仅构建反馈通道，不宣称定位或修复根因。
- 已补键盘分段、选区回调、布局/更新计时和最近 200 条事件复制；修正 dismantleUIView 存活计数回调。
- 验证：swift test 347 Swift Testing + 26 XCTest 全绿；App 构建及 UI 指标有效性待用户验证。
- 第二批证据：选区 732.9ms，触摸递送 190.3ms；键盘 Will→Did 1.7ms 与声明动画 383.3ms 不一致，不能据此推断实际动画。
- 可证伪方向：若滚动容器参与等待，应看到 delaysContentTouches 与触摸递送延迟；若主队列阻塞，应看到交互窗口探针超时；若响应者调用阻塞，应看到 responderAcquire 耗时。探针启动前的阻塞仍未覆盖。
- USB 实测：选区 790.8ms；触摸递送 196.5ms；depth=3 滚动容器 delays=true；输入框 becomeFirstResponder 62ms；主队列峰值 605ms 发生于选区回调之后，不能归为启动根因。
- 单变量修改：仅会话内容挂只读桥接视图，关闭最近可滚动祖先的 delaysContentTouches，卸载时恢复；保持 canCancelContentTouches、系统长按时长和键盘行为不变。可证伪预期：新日志出现 conversation.delaysContentTouches=false，触摸递送时间下降；若没有变化则不能宣称收益。
- 版本 5 USB 反馈：delays=false 已生效，首次触摸递送 379.9ms、选区1119.2ms；后续触摸26.8ms、选区528.7ms。未解决首次卡顿，不宣称关闭延迟有效。
- 键盘输入触摸→编辑163.7ms，becomeFirstResponder88.1ms，聚焦后触发整树snappy滚动。版本6仅改变此滚动路径（按ADR工作包D），等frame通知后下一主队列轮次无动画定位；不更改长按识别阈值。只读焦点计时用于区分首次响应者与其他系统等待。

- 版本6复测：初次触摸递送355ms，随后只读becomeFirstResponder107.3ms，但此触摸无selection.nonempty；后两次采样601.3/537.9ms不能冒充首次。选区回调之后主队列仍有615.4ms延迟。首次输入框becomeFirstResponder84.4ms，第二次23.3ms。frame驱动滚动已生效，未证明消除卡顿。当前计时不包含调用栈，不能判定UIKit或App具体耗时函数。原始报告暂存/tmp/readloop-perf-v6.json。

- Instruments证据：/Users/zpc/Downloads/Untitled.trace；Time Profiler，28.108729秒，目标由Instruments启动，含ReadLoop.debug.dylib。potential-hangs表0行（阈值250ms）。time-profile主线程累计采样权重2450ms，不代表连续阻塞。输入框becomeFirstResponder应用帧累计38ms、只读文本8ms、文本测量29ms，均为采样权重非精确单次时延。
- xctrace标准输出导出首次崩溃；使用--output成功，导出/tmp/readloop-trace-toc.xml、/tmp/readloop-time-profile.xml、/tmp/readloop-hangs.xml。当前trace不能解释此前615ms等待，未建立安装后首次与普通启动的同条件对照，不认定系统冷启动根因。
- v7 真机复测：连续三次键盘开关，用户每次观察到键盘升起后会话回落一次。事件序列稳定为 `keyboard.willShow` → 约 390-400ms 后 `keyboard.didShow` → 约 1ms 后 `composer.keyboardFrame.scrollToBottom`；该自定义滚动晚于键盘完成，是当前首要可证伪原因。
- 最小修复：移除 `.onReceive(keyboardDidChangeFrameNotification)` 中晚到的 `proxy.scrollTo("reflection-conversation-bottom")`，保留全局键盘 signpost。UI 路径不在 `swift test` 构建范围内，无合适包级回归 seam；由真机重复开关键盘闭环验证。
- v7 修复后真机复测：移除晚到滚动后，连续四次开关键盘未再观察到回落；事件中不再出现 `composer.keyboardFrame.scrollToBottom`。Phase D 的可见二次跳动回归解除。
- 修复后“普通冷启动（不重装）首次键盘”：触摸→编辑 130.6ms、becomeFirstResponder 49.9ms、WillShow 73.6ms；后续三次触摸→编辑 93.8-102.9ms、becomeFirstResponder 26.5-27.9ms、WillShow 34.9-37.3ms。主队列最大调度间隔 28.4ms，无 ≥50ms 阻塞。
- 结论更新：普通冷启动首次键盘比重复唤起多约 30-50ms App 侧准备时间，但无连续主线程阻塞；用户可感的约 0.5s 总时长主要由 383.3ms 系统声明键盘动画构成。重装后首次曾出现 226.1ms 主队列峰值，但普通冷启动未复现，不能归为稳定 App 回归。
- 下一步：继续验证长按/拖动选区路径与 `textMeasureCache` ceiling；键盘路径不再阻止 Phase D 验收。
- v7 选区复测：首次长按触摸递送 45.2ms、只读文本 becomeFirstResponder 9.7ms、触摸→非空选区 597.8ms（与系统约 0.5s 长按阈值重合），选区建立后主队列最大 137.7ms；后续手柄拖动主队列延迟 9-30ms。用户确认手柄跟手正常、无明显滞后。
- A/D 文本交互补充结论：键盘 safe-area 与长按选区均未新增 `textMeasure.cache.miss`（保持 22），未发生整串重测；缓存命中路径未被此场景触发，但“不变不重测”的验收条件成立。
- v7 流式实测：`streamDelta n=1`、单次 0.043ms；用户观察到回复一次性完整出现。源码确认 OpenAI-compatible 与 Anthropic Provider 均 `supportsStreaming=false`，只 yield 一个完整 `.textDelta`，符合 PRD §21.3“首发不做真流式”。因此当前 50ms 去抖没有可见收益，也不能把一次性展示归为 B 回归；Phase B 的真实验收延至 v2 SSE。
- 最终验收（2026-09-13）：用户确认键盘回落消失、拖动手柄正常、两处自动聚焦 sheet 无异常、普通冷启动无白屏/冻结。首次选区 597.8ms 与系统长按阈值一致，不再视为应用稳定回归。B 的一次性全文展示已确认来自非流式 Provider，当前阶段不适用。

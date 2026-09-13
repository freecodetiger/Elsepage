# ReadLoop DEBUG 测试闭环 v1

## 状态与适用范围

截至 2026-09-12：**可用的最小业务闭环，已通过真机验证；完整框架尚未完成。** 本文是所有 Agent 使用、扩展和维护本框架的主文档。

| 能力 | 状态与验证界限 |
|---|---|
| DEBUG 自启动、无令牌 USB 连接 | 已在真机验证；脚本按调用恢复转发，非持续设备管理守护进程 |
| Reflection 保存与空白拒绝、请求幂等 | 已通过真实 Model + 内存 GRDB 的设备场景 |
| 性能数据直读 | 已用于多轮键盘/选区排查；原始手势仍由用户执行 |
| Agent、Journal、Memory/Brain 业务场景 | 未接入；现有单测不等于设备场景覆盖 |
| 数据库磁盘重启恢复 | 未覆盖；内存数据库重读不能证明磁盘耐久性 |
| 全链路因果观测 | 部分：动作关联和结果快照已有，缺通用事务、Provider、后台任务事件 |
| UI 手势、像素、真实帧率 | 未自动化，需真机手测/专用工具 |
| 自动构建、安装、CI、多设备管理、MCP | 未实现；构建安装仍按项目分工由用户完成 |

完成标准按场景计算：真实动作入口、独立环境、状态与数据库/依赖断言、明确异步终态、失败证据、设备验证缺一不可。当前不能标为“全项目 E2E 完整覆盖”。

## Agent 使用与维护流程

1. **开始业务开发/修复前**：检查 `/status` 能力与本文范围，确定受影响流程是否已有场景。当前运行命令为 `python3 Scripts/debug_loop.py status`；设备不可用时继续可执行的代码与单测工作，并标注设备验收待完成。
2. **修改已覆盖的 Reflection 链路**：运行 `swift test`；用户装好新版后执行 `python3 Scripts/debug_loop.py save`。记录运行时版本、runID、命令、结果及证据位置；`build` 当前通常为 `1`，不是源码提交标识，必须另行核对安装版本。
3. **新增业务流程**：评估并在同一变更中补动作注册、状态投影、独立 fixture、场景和失败断言。场景调用 UI 使用的真实 Model/Service；只有 fixture 准备可以直接创建初始数据。暂不能接入时，在本表/执行计划记录具体缺口和替代验证。
4. **修改服务、协议或脚本**：同时更新本接口契约和对应测试；不兼容协议变更升级 `protocolVersion` 并同步客户端，新增性能观测升级 `instrumentationVersion`。Mac 脚本测试命令为 `python3 -m unittest discover -s Scripts -p test_debug_loop.py`。HTTP 解析/生命周期的修改仍须专项验证，现有五个 Python 测试不覆盖设备端网络实现。
5. **完成验收**：断言同时检查页面模型与数据库/依赖结果；事件用 runID/actionID 关联，读取时检查截断。失败用例应能先 FAIL 后 PASS，避免以 HTTP 200/202 或单一 UI 状态替代业务成功。异步副作用各自等待终态，尤其 Brain 投影独立于 Agent 回复完成。
6. **更新交接**：同一变更同步本文能力表、场景说明、验证记录和 GSD 计划。`/tmp` 是临时目录，需要跨 Agent/机器保留的证据，去除个人数据与凭据后写入仓库或交付持久路径。区分包测试、执行器测试、设备业务场景和手测结果。

交互性能问题先用 `perf` 获取实际运行数据；HTTP 时间线不能提供调用栈，必要时分析用户录制的 Instruments trace。分别记录安装后首次、普通冷启动和重复操作，避免混用基线。

## 实现导航

| 文件 | 职责 |
|---|---|
| `App/AppModel.swift` | DEBUG 自动启动入口 |
| `App/Performance/DebugHTTPServer.swift` | 通用 loopback HTTP 传输、限制与生命周期 |
| `App/Performance/DebugLoop.swift` | 业务动作注册、会话隔离、快照和事件 |
| `Sources/Persistence/ReflectionTestEnvironment.swift` | 真实 GRDB 隔离环境 |
| `App/Reflection/SessionReflectionSheet.swift` | 场景调用的真实 Reflection Model |
| `Scripts/debug_loop.py` | Mac 连接、场景执行、断言和证据输出 |
| `Scripts/test_debug_loop.py` | 执行器裁决与连接管理测试 |
| `Tests/ReadLoopCoreTests/ReflectionTestEnvironmentTests.swift` | fixture、数据库与保存服务验证 |
| `App/Performance/Perf.swift` | 交互性能采集；诊断页与 HTTP 共用 |

## 已实现

- DEBUG App 启动自动开启 HTTP 服务，只监听设备 loopback `127.0.0.1:18765`；按用户要求无令牌认证。诊断页仍可手动停止/启动。
- Mac 脚本读取实际运行 App 的性能报告、构建/协议版本；执行 Reflection 保存场景并输出 JSON / JSONL 证据。
- 业务测试装配 `ReflectionTestEnvironment`：独立内存 GRDB、固定书籍与阅读会话，实例化产品使用的 `SessionReflectionModel`，调用其 `submit()`。不会连接用户数据库、书籍文件、Keychain 或真实 Provider。
- 验证模型 saved、数据库原文与 ID、讨论计数、相同动作 ID 重试不重复写入、空白输入拒绝。每个新场景重建隔离环境。

这不是点击/键盘/长按自动化。`GET /perf` 读取现有手测数据；`GET /events` 是业务动作事件，不是性能事件的增量接口。Agent/Journal/Brain 场景、正式 UI 当前模型的远程操作、自动构建安装不属于 v1。

## 自动连接

1. USB 连接并信任 iPhone，通过 Xcode Run 安装并启动最新 DEBUG App，保持前台。
2. 在仓库根目录运行：

```sh
python3 Scripts/debug_loop.py status
python3 Scripts/debug_loop.py perf
python3 Scripts/debug_loop.py save
```

不需要开启开关或复制令牌。脚本发现本地端口未监听时，使用已安装的 `idevice_id` 和 `iproxy` 启动 USB 转发；转发后台保留供后续命令复用。多设备首次建转发可用 `--udid` 指定设备。已有转发会复用，要切换设备需先停止原转发进程。

Mac 工具已安装；其他机器首次使用运行 `brew install libimobiledevice`。脚本默认等待启动最多约 15 秒（单次网络请求另有 12 秒超时），可用 `--wait` 调整重试窗口。不自动重发业务动作。旧令牌构建返回 401 时，会明确提示安装新版本。

Xcode 覆盖安装并启动后服务自动恢复；仅安装而未启动、App 被终止或后台挂起时不能提供服务。脚本按调用恢复转发，不安装常驻监控或开机服务。结果默认写入 `/tmp/readloop-debug-runs/<UUID>/`。

无认证服务只能通过设备 loopback/USB 访问；能访问 Mac 转发端口的本地进程可读取性能报告和触发隔离环境测试。不得改为 LAN 监听。Release 不装配此服务。

## 接口契约

| 方法/路径 | 行为 |
|---|---|
| GET /status | protocolVersion、instrumentationVersion、build、runID、busy、能力列表 |
| GET /perf | 当前 App 的性能报告文本 |
| POST /session `{}` | 重建独立测试环境；操作执行期间返回 409 |
| GET /snapshot | 测试模型与数据库真值；执行中/读取期间状态变化返回 409 |
| POST /actions | `{id: UUID, name: "reflection.submit", text: string}`；202 表示接收，不表示业务完成 |
| GET /actions/{id} | running / completed / rejected；相同 ID 不重复执行，不同内容重用 ID 返回 409 |
| GET /events?after=N | 带 runID、actionID、递增 seq 的事件；检查 firstSequence 判断有无截断 |

新 session 清空动作及事件，runID 改变；事件最多保留 1000 条，动作最多 100 个。HTTP 最大正文 64KB，连接最多 8 个，单连接 10 秒超时。一请求一连接，不支持 chunked。操作与模型修改在 MainActor，业务异步数据库保持原实现。

`reflection.save.returned` 表示真实模型保存方法成功返回，不能单独冒充数据库事务探针；脚本额外从 GRDB 重读证明数据持久化。内存数据库能验证事务与重读，不能证明 App 重启后磁盘恢复。

## 验证证据与边界

- `swift test`：349 Swift Testing + 26 XCTest 通过。新测试验证真实 GRDB 保存、来源证据、幂等重试、环境隔离和空白拒绝。
- `python3 -m unittest discover -s Scripts -p test_debug_loop.py`：5 个执行器/连接管理测试通过，包含“页面成功但数据库文本错误”必须 FAIL。
- `xcodegen generate` 已完成；它只生成工程，不是构建。
- 2026-09-12：用户构建安装后，已在 iPhone 上运行 `save` 并 PASS；无令牌自启动版本也通过，protocolVersion=1、instrumentationVersion=5。保存、重试与空白拒绝的原始结果见 [设备验收证据](testing/debug-loop/2026-09-12-device-save.json)。后续 instrumentationVersion=6 已连接并读取性能数据；当前版本 7 增加文本缓存统计，但这不自动构成未来代码改动的回归通过。

## 后续扩展

按相同真实模型调用方式增加 Agent 失败/取消、Journal、Brain 测试。扩展前先补相应终态事件与关联 ID；Brain 投影完成不能借用 Agent 回复完成。首个场景无需重构所有 AppModel 装配或引入全局事件总线。

优先顺序：Reflection 后续发送/失败/取消 → Journal/Brain 持久化与后台完成 → 磁盘恢复场景 → 设备网络/协议故障回归。构建指纹、通用场景注册和多设备选择完善后，再评估 CI/MCP；这些是待办而非当前能力。

# 产品理解阶段：运行验证恢复记录

日期：2026-11-14，Asia/Shanghai。分支：`ui/ux-modernization`，起点 `9d761ca`。本记录补充原研究，不进入 UX 审计或 UI 实现阶段。

用户要求处理研究中的阻塞，尤其 computer use。本轮只维护既有测试源码与验证文档；没有改动 App、Sources、依赖、数据库结构或工程配置。

**最新进展（同日第二轮，GSD `261114-on4`）**：已补装 Codex GSD 1.42.3 的 33 个角色并校准项目 runtime；Device 通道的控件树、点击、文本输入、App 重启后读取均实际通过。新增只读快检脚本，默认 snapshot 15 秒、本地调用总等待 30 秒（另有约 1 秒退出清理），不自动重试。下文第1–4节保留第一次恢复尝试的历史状态，当前结果以 [第5节](#5-gsd-补装与设备交互恢复第二轮) 为准。没有开始产品/UI实现；本轮额外变更仅为 GSD 配置和验证工具。

## 1. 第一次恢复尝试的结果与证据边界

| 项目 | 状态 | 实际结果 |
| --- | --- | --- |
| iOS 集成测试编译阻塞 | Implemented / 已修复并运行验证 | 原错误已复现，修正测试中的旧类型/API 引用后，ReadiumIntegrationTests 的 13 个测试通过，exit0 |
| 全量 portable package tests | Implemented / 本次运行通过 | `swift test --skip-update --jobs 2`，411 个 Swift Testing / 15 suites + 28 个 XCTest，0 失败，exit0 |
| 新设备通道的打开与截图 | Implemented / 本次观察通过 | T3 Device 工具打开既有模拟器中的 App，返回 1206×2622 PNG；观察到“我的”空态、连续阅读/思考与成就区域 |
| 新设备通道的控件树、点击与输入 | Partial / 仍阻塞 | snapshot 两次均在 90 秒请求时限后失败；没有获得控件树，没有执行点击或文本输入 |
| 原 CUA `cgWindowNotFound` | Unknown / 未修复 | 本次采用设备原生通道，未重试或修改原 Mac 窗口控制提供方；不能声称原故障消失 |
| 非空笔记、正式 Reflection、档案与重启恢复 | Unknown / 本次仍未运行 | 交互通道未通过，未用 HTTP 模型动作或数据库写入冒充 UI 验证 |
| 真实 AI、引用、Embedding、Brain、录音 | Unknown / 本次仍未运行 | 没有配置/读取真实 Key；设备交互、真机语音与样书条件仍不足 |

截图是设备工具直接返回的图像，未另存为本轮本地 PNG；不要把旧 P01–P16 当作本轮截图。原研究证据保持原义。

## 2. 设备通道调查

遵循当前设备工具约定，使用 `device_list` → `device_open` → 返回的设备专用 `agent-device` 命令，而非依赖 Mac Simulator 窗口句柄。设备为 `local / C380BC09-F7BE-4A18-B856-10E516F9EB3C`，iPhone 17 Pro / iOS 26.5。工具报告 hub 0.22.1、agent-device 0.21.36 已安装。

实际执行：

```sh
/Users/zpc/.t3/userdata/device/targets/t3-4d400ff7f48d0f72933ce4f7/agent-device open com.readloop.reader
/Users/zpc/.t3/userdata/device/targets/t3-4d400ff7f48d0f72933ce4f7/agent-device snapshot -i
/Users/zpc/.t3/userdata/device/targets/t3-4d400ff7f48d0f72933ce4f7/agent-device snapshot -i --debug
```

`open` 返回成功；另一次 `device_screenshot` 返回实际 App 画面。以上专用命令仅属于本线程本次设备会话，T3 重启后可能失效；后续必须重新使用 `device_open` 获取命令，不能复制为永久工具路径。

两次 snapshot 都返回：

```text
Error (COMMAND_FAILED): Daemon request timed out
timeoutMs: 90000
reason: daemon_transport_timeout
```

首次失败的诊断 ID 为 `mwg7andj-9d93f818`。按工具建议带 `--debug` 重试一次，第二次诊断 ID 为 `mwg7dlcg-df25fa5a`，请求于 17:29:46 结束。随后只读日志观察到：

```text
** BUILD INTERRUPTED **
** TEST BUILD SUCCEEDED **
2026-11-14 17:30:40.917419+0800 AGENT_DEVICE_RUNNER_LISTENER_READY
```

这支持“首次 XCTest 自动化运行器冷编译超出请求窗口”的判断：第二次请求结束约 55 秒后运行器才报告监听就绪。它不是点击/输入已成功的证据；目前也没有证据表明是 App 崩溃或授权令牌失效。同期存在 App 测试构建，尚未通过串行复测排除资源竞争，不能把冷编译认定为唯一根因。

设备工具明确要求：按建议重试一次仍失败就停止设备操作。因此本轮未继续发第三次请求、未切换私有手势/SSH/simctl 输入，也没有复用或关闭其他设备会话。后续验证应在运行器构建完成、没有并行 Xcode 测试时，重新建立本线程的设备会话，先验收一次控件树、点击、文本输入与重启，再恢复业务路径。**该步骤尚未执行，不能提前标为已恢复。**

证据：

- [设备结果清单](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14-runtime-recovery/device-verification.json)
- [运行器构建与监听信号](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14-runtime-recovery/device-runner-signals.txt)
- [首次失败的脱敏诊断](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14-runtime-recovery/2026-11-14T09-27-28-936Z-mwg7andj-9d93f818.ndjson)
- [重试失败的脱敏诊断](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14-runtime-recovery/2026-11-14T09-29-46-326Z-mwg7dlcg-df25fa5a.ndjson)

## 3. iOS 测试修复

旧测试 [ReadiumPublicationIntegrationTests.swift](/Users/zpc/projects/elsepage/Tests/ReadiumIntegrationTests/ReadiumPublicationIntegrationTests.swift) 的四个草稿测试仍使用 `ReflectionDraft` 与 `canSend`。当前公开实现是 [ReflectionTextDraft](/Users/zpc/projects/elsepage/Sources/ReflectionCore/ReflectionTextDraft.swift:9) 与 `canSubmit`。测试缺少 `import ReflectionCore`。本轮只修正这些引用，原始文本/优化文本隔离、编辑使旧优化失效、快照恢复、发送后清空与下一段编辑的断言全部保留，没有添加产品侧兼容别名或跳过测试。

修复前重新运行同一 iOS 集成测试目标，编译阶段 exit65，明确报 `cannot find 'ReflectionDraft' in scope`。修复后：

```text
Executed 13 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

运行命令：

```sh
xcodebuild -project ReadLoop.xcodeproj -scheme ReadLoop \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=C380BC09-F7BE-4A18-B856-10E516F9EB3C' \
  -derivedDataPath /tmp/elsepage-design-20261114/DerivedData \
  -resultBundlePath /Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14-runtime-recovery/ReadiumAfter.xcresult \
  -only-testing:ReadiumIntegrationTests -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
```

13 个测试包含真实 EPUB 打开、Publication 缓存失效、幂等导入、内容提取/FTS 与编辑策略断言；不是 XCUITest，也不证明正式页面交互通过。工程中的 ReadLoopCoreTests 在本命令中参与编译，但未作为执行目标运行。

证据：[修复前日志](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14-runtime-recovery/xcode-before.log)、[修复后日志](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14-runtime-recovery/xcode-after.log)、[测试结果 bundle](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14-runtime-recovery/ReadiumAfter.xcresult)。完整参数另存 `xcode-before-command.txt` / `xcode-after-command.txt`，各有独立 exit 文件。

另运行 `swift test --skip-update --jobs 2`：411 个 Swift Testing / 15 suites 与 28 个 XCTest 全部通过、exit0。[包测试日志](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14-runtime-recovery/swift-test.log)。`--skip-update` 收到弃用警告，不影响本次通过结果。两份 tracked Package.resolved 与起点相同，未引入依赖漂移。

## 4. 剩余验证

当前未完成项仍以 [研究入口的阻塞清单](README.md#阻塞与未完成运行验证) 和 [重构风险](00-refactor-risks.md) 为准。尤其不能因 13 个集成测试通过，就关闭真实 Provider、复杂 EPUB、真实 UI 保存、语音、强杀/磁盘恢复或故障注入的验收项。

本轮没有触碰不可达功能接线、索引恢复矛盾或成就注入差异。这些属于独立产品/业务问题，仍停留在研究发现状态。

## 5. GSD 补装与设备交互恢复（第二轮）

### GSD 安装

用户明确授权补装。使用本机已有 1.42.3 安装器运行 `node /opt/homebrew/lib/node_modules/get-shit-done-cc/bin/install.js --codex --global`，没有升级到其他版本。安装生成 33 份角色 Markdown、33 份角色 TOML、67 个技能入口与 Codex hooks。

原配置备份位于 [/Users/zpc/.codex/backups/gsd-codex-20261114-174535](/Users/zpc/.codex/backups/gsd-codex-20261114-174535)，目录权限 0700；含原 config.toml、hooks.json、存在性清单与安装日志。备份可能包含私密配置，仅保留本机，不进仓库。

安装后用安装器的 TOML parser 对比：原有配置键值全部保持，仅新增 agents 配置；原 hooks 条目全部保留；shuorenhua/SKILL.md 的 SHA256 未变。项目通过 `gsd-sdk query config-set runtime codex` 校准，`.planning/config.json` 只新增 `runtime: codex`。随后 SDK 检测 `agents_installed: true`、`missing_agents: []`。这证明安装与文件检测通过；当前已运行的 harness 没有执行命名角色分派，不把磁盘安装等同于角色调用验收。

### 超时阶段与恢复

本轮没有并行运行 Xcode 项目构建，先使用 device_open 获取本线程命令，再 open → prepare → snapshot → fill → snapshot → press → relaunch → snapshot。

| 操作 | 整个本地调用耗时 | 观察与独立核对 |
| --- | --- | --- |
| open | 6.013 秒 | App 成功打开；daemon startup 23ms |
| prepare ios-runner | 0.424 秒 | 健康检查成功，runnerMainThreadBusy=false；当前 prepare durationMs=54、healthCheckMs=4 |
| snapshot | 0.374 秒 | 21 个元素；daemon request 135ms |
| fill 书架搜索 | 4.394 秒 | 输入 tooling-check-20261114；后续独立 snapshot 确认搜索值、键盘和“未找到”状态 |
| press 关闭搜索 | 2.326 秒 | 搜索词清除、键盘消失、fixture 书籍恢复显示 |
| App relaunch | 4.134 秒 | 退出/重新打开 App，随后 snapshot 0.398 秒成功返回书架 21 元素 |

prepare 还报告了历史 `buildMs: 147125` 和 `artifact: rebuilt`，但其当前 totalMs 只有 54；这些字段包含缓存的准备记录，不能相加冒称本轮又执行了 147 秒构建。结合上一轮 runner.log 的“请求90秒先超时、运行器随后就绪”时间线，证据定位到 **XCTest 运行器首次构建/准备超过命令等待窗口**。本轮健康连接、控件读取和交互已通过，支持通过复用已构建运行器、串行预热恢复工作。没有重新清缓存做冷构建对照，无法量化并行构建对当时 147 秒的贡献，也不能保证更新运行器后的首次构建不再超时。

这恢复的是 **T3 Device → agent-device → XCTest 的模拟器交互通道**。原 Mac CUA 提供方的 cgWindowNotFound 没有被修复或重新验收。没有修改 T3/agent-device 的供应商源码，没有重启 T3 主程序、终止其他会话或改变 App 实现。

### 缩短等待的实际设置

0.21.36 的命令超时语义不同：snapshot 的 `--timeout 15000` 将传输等待从默认 90000ms 降到 15000ms；prepare 的 `--timeout 30000` 是内部准备预算，传输层仍可能保留 270000ms；press/fill 配合 `--settle` 的 timeout 主要限制稳定等待，不能当成整体15秒上限。

为避免把这些参数误当统一全局开关，新增 [Scripts/device_snapshot.py](/Users/zpc/projects/elsepage/Scripts/device_snapshot.py)，只做只读 snapshot：

- snapshot 请求预算默认 15000ms；局部 daemon startup 配置 10000ms。
- 本地调用 watchdog 默认 30秒，另有最多约1秒退出清理。超时先 SIGTERM 再 SIGKILL，仅处理本次调用新建的本地进程组，返回124；不结束共享daemon或其他会话。
- 不自动预热、重试、重启、接管或换设备；命令路径不存在返回2，要求重新 device_open。远端请求取消未验证，不能声称关闭本地CLI等于取消远端工作。

使用方法（先按设备工具约定获取命令并 open App）：

```sh
python3 Scripts/device_snapshot.py \
  --agent-device '<本线程 device_open 返回的绝对命令路径>' --debug
```

首次冷准备必须作为独立准备动作观察，不在快检中偷偷加入多分钟构建；不要与项目 xcodebuild 并行，也不要在失败后循环调用。失败仍遵守设备工具的建议重试/停止规则。

实际验证包括：

- 临时把 snapshot 预算设1ms：预期 exit1 / daemon_transport_timeout，整次调用0.229秒；恢复15000ms并按建议带debug重试后，0.285秒成功。
- 快检脚本连接真实设备：0.467秒返回21个元素，exit0。
- 本地假客户端模拟挂死，设置1.5秒watchdog：1.554秒返回124，父子进程均消失；假客户端不涉及设备。首次0.5秒fixture启动不足未取得PID，未当成通过，改用可启动的1.5秒窗口完成验证。
- 失效/相对路径与非法预算校验：exit2，不启动其他命令。原 DEBUG 执行器 `python3 -m unittest discover -s Scripts -p test_debug_loop.py`：26个测试、3.093秒、OK，结果记录在证据目录。

证据目录：[/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14-tooling-repair](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14-tooling-repair)。含每个阶段的命令、耗时、exit与日志、GSD检测、watchdog结果及实际 [书架截图](/Users/zpc/Library/Caches/ElsepageDesignResearch/2026-11-14-tooling-repair/bookshelf-after-smoke.png)。截图为1206×2622，fixture数据。

**范围仍有限**：工具恢复不等于正式Reflection/笔记保存、数据重启恢复、真实AI、引用、语音与复杂EPUB已经运行验收；这些任务没有在此次工具修复中补跑。本轮只复验 App 进程重启后仍能操作，没有断言业务数据耐久性。

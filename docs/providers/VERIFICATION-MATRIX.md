# Provider 验证矩阵（PROV-02，用户真机填写）

> 目标（ROADMAP Phase 8 / PRD §12 BYOK）：至少 3 个模型 Provider 在真机上稳定可用——
> OpenAI 兼容系 ≥1 + Anthropic 原生 ≥1，并覆盖错误路径。
> 本文件是**用户手工填写的验收清单**：联调所需 API Key 由用户提供，自动化测试无法替代真机验证。
> 填写方式：直接在下方矩阵的「结果」列写 ✅/❌ 与备注，或在本文件末尾的「执行记录」追加日期、构建号与现象。

## 自动化测试已覆盖（无需重复手工验证）

以下路径已由 `swift test` 全绿覆盖（`Tests/AgentProviderTests/AnthropicModelClientTests.swift`、
`ModelClientRoutingTests.swift`、`Tests/ReadLoopCoreTests/AnthropicProviderPersistenceTests.swift`，
全部基于 URLProtocol 桩，无真实网络）：

- Anthropic 原生 `/v1/messages` 请求形态：`x-api-key` + `anthropic-version: 2023-06-01` 头、
  `system` 顶层参数、`max_tokens` 必填、**不含任何 `stream` 字段**
- 响应解析：content 文本块拼接、`stop_reason: max_tokens → length`（截断语义）、usage 统计
- 错误分类与 OpenAI 客户端一致：401→认证失败、429→限流、5xx→服务不可用、坏 JSON→无效响应、
  超时→网络失败；AgentExecutor 归一化后 UI 文案路径不变
- 工厂路由：Anthropic 预设 → 原生客户端；其余预设与自定义地址 → OpenAI 兼容客户端；
  SQLite 中既有配置行（provider 仍为 `openAICompatible`）无需迁移即可路由正确
- 本地 Reflection 持久化在任何 Provider 错误（无 Key/断网/限流/无效响应）下都不受影响

**自动化测试不能覆盖的**：真实网络下的握手与配额、真实 Key 的有效性、真机 UI 流程与引用跳转。
这正是下表要填的内容。

## 真机验证矩阵（≥3 个 Provider）

前置：真机安装包含 Phase 8 的构建；每行验证前在 **设置 → AI 模型与连接 → 聊天模型**
选择对应「服务商」预设（Base URL 会自动填充官方地址）、按服务商控制台填写「模型」与「API Key」，
点「保存配置」。列含义与判定标准见表格下方说明。

| # | Provider（预设） | 模型（示例） | ① 测试连接 | ② Agent 回应流程 | ③ 引用跳转 | ④ 错误路径（飞行模式 + 错误 Key） | 结果 / 日期 |
|---|---|---|---|---|---|---|---|
| 1 | DeepSeek | `deepseek-chat` | ☐ | ☐ | ☐（有引用时） | ☐ | ☐ 待填（曾通过 bench 冒烟，见下） |
| 2 | Anthropic Claude | `claude-sonnet-4`（或你持有的其他 Claude 模型） | ☐ | ☐ | ☐（有引用时） | ☐ | ☐ 待填（需用户提供真实 Key） |
| 3 | OpenAI / Moonshot / 智谱 任选其一 | 各家控制台的聊天模型名 | ☐ | ☐ | ☐（有引用时） | ☐ | ☐ 待填 |

> ①②③④ 的判定标准与逐步操作：

### ① 测试连接
1. 设置 → 聊天模型，选预设、填模型与 API Key（Key 只进本机 Keychain）。
2. 点「保存配置」，再点「测试连接」。
3. **通过标准**：出现绿色「连接成功」。失败时记录 alert「操作失败」里的具体文案。

### ② Agent 回应流程（Reflection 主链路，PRD P9 最高优先级）
1. 打开一本书，选中一段文字 → 写一条 Reflection 并保存。
2. 等待 Agent 回应出现（首次回应包含上下文准备，可能有数秒延迟）。
3. 点回应输入框追加一句追问，确认多轮对话仍正常。
4. **通过标准**：回应文本完整、不重复用户原文、无乱码；追问有上下文连贯的回应。

### ③ 引用跳转（仅当该模型真的引用了证据时验证；引用不出现在正文时此格可标 N/A）
1. 在 ② 的回应中确认 `[E1]` 式标记与回应下方的来源区（附近原文 / 书内段落 / 过去的思考）。
2. 点来源区的「回到原文」。
3. **通过标准**：跳回阅读器对应位置；`---CITATIONS---` 技术块不出现在可见正文里。

### ④ 错误路径（每个 Provider 都要做两件事）
1. **飞行模式**：开飞行模式 → 写一条新 Reflection → 等待 Agent 失败提示
   （预期文案类似「现在网络不可用，表达仍已保存在本机。」）→ 关闭飞行模式，
   确认这条 Reflection 仍在、可重新触发回应。
2. **错误 Key**：设置里填一个故意错误的 API Key →「测试连接」（预期「API Key 无效或没有访问权限。」）
   → 再触发一次 Agent 回应（预期失败提示且本地表达仍保存）。
3. **通过标准**：两种情况下本地 Reflection/表达都不丢失；失败文案明确指向原因，而非空白或卡死。

### 各行当前状态说明

- **DeepSeek**：仓库 bench 已用真实 Key 跑过冒烟（`docs/bench/runs/<日期>-smoke.json`，BENCH-02），
  证明 OpenAI 兼容协议层可用；但 ①–④ 的**真机 UX 路径**仍需按下表走一遍。
- **Anthropic**：客户端为 Phase 8 新写的原生 Messages API 实现，已通过桩测试；
  真实 Key 联调必须由用户执行。Base URL 必须保持预设默认 `https://api.anthropic.com/v1`。
- **第 3 行（OpenAI/Moonshot/智谱任选）**：同为 OpenAI 兼容协议，选一家持有 Key 的即可；
  Moonshot `https://api.moonshot.cn/v1`、智谱 `https://open.bigmodel.cn/api/paas/v4`。

## 执行记录（由用户追加）

```
日期 / 构建：
Provider 1 (DeepSeek)：
Provider 2 (Anthropic)：
Provider 3 (________)：
异常与备注：
```

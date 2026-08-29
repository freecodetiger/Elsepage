# App Review BYOK 审核备注材料(REL-02)

> 用途:提交 App Review 时,复制「审核备注(App Review Notes)」栏与必要的附件说明。
> 主语言中文 + 英文摘要(审核团队以英文为主,提交时建议两段都粘贴)。
> 提交前必须由用户用**真实构建**走一遍本文件的演示路径(ROADMAP Phase 10 验收要求;REL-02 明确"由用户用真实构建验证")。
> 占位符:`[APP_NAME]`(正式名待定,见 APP-STORE-METADATA.md)、`[REVIEWER_DEMO_KEY]`(提交时填入临时演示 Key)。

---

## 一、审核备注(中文版,粘贴至 App Store Connect「审核备注」)

**应用概述**

[APP_NAME] 是一款本地优先的 EPUB 阅读器与个人思考工具。用户导入自己拥有的非 DRM EPUB 进行阅读、划线、写批注与读后反思;可选地配置**用户自己的** AI 服务商 API Key(BYOK)以获得 AI 反馈。

**1. 不配置任何 AI 即可完整使用的阅读器**

AI 不是解锁其他功能的前置条件。审核员无需任何账号或 API Key 即可完整使用:

- 从「文件」导入 EPUB(可使用任意自有 EPUB 或我们提供的测试文件);
- 阅读(翻页/滚动、字号、主题、进度恢复、书内搜索、目录);
- 划线与批注;
- 文字反思(Reflection);
- 查看历史(书架、日志、记忆列表)。

以上功能全部离线可用、本地存储。语音反思使用 Apple 系统语音识别(需系统授权,不配置 AI 也可用)。

**2. AI 功能为 BYOK(Bring Your Own Key)**

AI 反馈需要用户在 App 内「设置 → AI 模型与连接」自行选择服务商(OpenAI、Anthropic、DeepSeek、Gemini 等预设,或任意 OpenAI 兼容地址)、手填模型名并粘贴**自己的 API Key**。Key 仅保存在本机 iOS Keychain(ThisDeviceOnly),数据库与日志中不保存 Key。请求由设备**直接**发往该服务商,本 App 没有任何自有服务器或中转。

**3. 无后端、无账号、无订阅/内购**

- 不需要注册账号,没有登录;
- 应用不含任何订阅、内购或外部购买流程;
- 不含广告、统计或追踪 SDK。

**4. 演示账号:不适用(本地优先应用)**

本应用无账号体系,无法提供演示账号。如需测试 AI 功能,请在设置中任选服务商并填入你自己的 API Key;若不便使用你方 Key,我们会在提交时的「审核备注」栏提供一个**临时演示用 API Key**及对应服务商与模型名,审核结束后即作废。你可以用「删除配置和 API Key」或「清除所有本地数据」一键删除该 Key。

**5. 数据流(文字图)**

```
[用户设备]
  书籍/进度/划线/反思/记忆/画像/索引  ── 全部仅存本机(SQLite + 沙盒文件)
  API Key ── 仅存本机 iOS Keychain
        │
        │  仅当用户主动触发 AI 请求时:
        │  本地检索 → 选取必要证据(有预算上限,不发送整本书、不附带无关历史)
        ▼
[用户自己选择的服务商 API,如 api.openai.com / api.anthropic.com]
        │
        ▼
  回应返回设备,Reflection/记忆照常本地保存
(全程不经过本应用开发者的任何服务器;开发者无服务器)
```

**6. 权限说明**

- 麦克风:仅用于录下读后感并在本机转写(系统弹窗文案已注明);
- 语音识别:Apple 系统转写,转写文本保存在本机。

**7. 版权边界**

应用不提供任何书籍内容下载或书城;仅打开用户自行导入的非 DRM EPUB 文件,等同文件管理器打开用户自有文档。

---

## 二、App Review Notes(English summary)

**Overview:** [APP_NAME] is a local-first EPUB reader and personal thinking tool. Users import their own non-DRM EPUB files to read, highlight, annotate, and write post-reading reflections. AI feedback is optional and BYOK (Bring Your Own Key).

**1. Fully functional without any AI configuration.** No account or API key is needed to use the app: import EPUBs from Files, read (pagination, themes, progress restore, in-book search, TOC), highlight, annotate, write text reflections, and browse history — all offline, stored locally. Voice reflection uses Apple's system speech recognition.

**2. AI is BYOK.** To enable AI feedback the user picks a provider preset (OpenAI, Anthropic, DeepSeek, Gemini, or any OpenAI-compatible endpoint), enters the model name and **their own API key** in Settings. The key is stored only in the iOS Keychain (this-device-only) — never in the database or logs. Requests go **directly from the device to the user's chosen provider**; the app has no backend of any kind.

**3. No backend, no account, no subscription/IAP, no ads, no analytics SDKs.**

**4. Demo account: not applicable (local-first app, no accounts).** Reviewers may test AI by entering their own API key in Settings; alternatively, a **temporary demo API key** (with provider and model name) is provided below at submission time and revoked after review. The key can be removed in one tap via "Delete configuration and API Key" or "Clear All Local Data".

**5. Data flow:** All user data (books, progress, highlights, reflections, memories, profile, index) stays on device (SQLite + sandbox files); API key in iOS Keychain only. On each user-initiated AI request the app locally retrieves a small budgeted set of relevant excerpts (never the whole book, never unrelated history) and sends it straight to the user's chosen provider. The developer operates no servers.

**6. Permissions:** Microphone — recording reflections for on-device transcription; Speech recognition — Apple system transcription, transcript stored locally.

**7. Copyright:** No book store, no downloads; the app only opens EPUB files the user imports themselves (non-DRM), like a file manager opening the user's own documents.

---

## 三、提交时检查清单(提交前由用户逐项执行)

| # | 事项 | 状态 |
|---|---|---|
| 1 | 用真实构建(Xcode Archive 或 TestFlight 包)按上述「1. 无 AI 完整可用」路径自测:导入 → 阅读 → 划线 → 文字反思 → 历史 | ☐ |
| 2 | 在「设置 → AI 模型与连接」用真实 Key 完成 Test Connection 与一次 Agent 反馈(至少 2 个服务商,见 docs/providers/VERIFICATION-MATRIX.md) | ☐ |
| 3 | 准备临时演示 Key(低额度、可随时作废),提交时连同服务商/模型名填入「审核备注」,本文件占位符 `[REVIEWER_DEMO_KEY]` 同步替换;**不要把 Key 写进任何入库文件** | ☐ |
| 4 | App Privacy 营养标签勾选 **Data Not Collected**(见下) | ☐ |
| 5 | 隐私政策 URL 已托管并填入(App Store Connect「隐私政策网址」) | ☐ |
| 6 | 审核演示材料:可提供一个示例 EPUB(自有版权或公版),或注明审核员可用任意自有 EPUB | ☐ |
| 7 | 分级、类别(建议 Books / Productivity)、年龄问卷按「无收集、无用户生成内容公开分享」作答(反思与日志仅本地,无社交/UGC 公开功能) | ☐ |

## 四、App Privacy「营养标签」建议

**结论:Data Not Collected(未收集数据)。**

依据(与代码核对,详见 `PRIVACY-CLAIMS-EVIDENCE.md`):

- 全仓库 `URLSession` 仅存在于 `Sources/ModelProviders/` 的 5 个 Provider 客户端,Base URL 一律来自用户配置;请求直连用户选择的服务商;
- 无统计/遥测/广告/崩溃 SDK(`Package.swift` 三方依赖仅 GRDB;`project.yml` 仅 Readium + GRDB);
- 无账号系统、无设备标识采集、无跨 App 追踪;
- API Key 仅存 Keychain(`Sources/ModelProviders/SecretStore.swift`),数据库只存引用。

App Store Connect 填写路径:App Privacy → 各数据类型一律不勾选;若表单强制要求说明,可按第三方服务商直连场景在「Contact Info / Other Data」保持"not collected"并在审核备注引用本节。

## 五、PRD 依据

- §12(AI Provider UX,BYOK 与审核路径需独立验证)、§13(隐私与信任)、§14(离线行为:无网络/无 Key 时仍是完整阅读器)、§18「1.0 App Store」(API Key 安全、无后端依赖、AI 请求数据范围透明)、§19 Privacy(请求仅直连用户选择的 Provider、可清除所有本地数据)。

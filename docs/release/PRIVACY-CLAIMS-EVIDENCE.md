# 隐私政策声明与代码证据对照表(REL-01 附件)

> 用途:`PRIVACY-POLICY.zh-Hans.md` / `PRIVACY-POLICY.en.md` 中每一条数据流向声明,在代码中的落点。
> 政策文本内不放文件路径(面向用户),本文件面向维护者与审核准备。政策更新时同步核对本表。
> 基线:branch `main` @ c982138,Phase 8 合并后。后续大改请重跑本表。

## 1. 「所有用户数据仅存本机」

| 声明 | 证据 |
|---|---|
| 书籍/进度/高亮/笔记/Session/Reflection/Journal/Memory/画像/索引/偏好仅本地 | 本地 SQLite(GRDB):`Sources/Persistence/AppDatabase.swift`(建表与各仓储);书文件存 App Sandbox:`Sources/ReaderCore/BookFileStore.swift`(经 `App/Settings/DataSettingsModel.swift` 的两阶段删除流程引用) |
| 无自有服务器、请求仅直连用户选择的 Provider | 全仓库 `URLSession` 使用仅存在于 `Sources/ModelProviders/`:`AnthropicModelClient.swift`、`OpenAICompatibleModelClient.swift`、`OpenAICompatibleEmbeddingProvider.swift`、`SiliconFlowReranker.swift`、`ConfiguredModelClientFactory.swift`;Base URL 全部来自用户配置(`Sources/ModelProviders/ProviderConfiguration.swift`,预设见 §5) |
| 无遥测/分析/崩溃 SDK | 全仓库 grep `telemetry|analytics|firebase|sentry|umeng|appcenter|mixpanel|posthog|crashlytics` 无命中;`Package.swift` 三方依赖仅 GRDB,`project.yml` 仅 Readium 3.3.0 + GRDB 7.11.1 |
| 路由追踪仅本地自查 | `App/Settings/DiagnosticsModel.swift`(聚合本地 routing traces,`RoutingTraceRepository`) |

## 2. 「API Key 仅存 Keychain」

| 声明 | 证据 |
|---|---|
| Key 只进 Keychain,属性 ThisDeviceOnly + 解锁时可用 | `Sources/ModelProviders/SecretStore.swift` → `KeychainSecretStore.save`:`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`;类注释明确「never writes a key to UserDefaults, SQLite, or logs」 |
| 数据库只存引用不存 Key | `Sources/Persistence/ProviderConfigurationRepository.swift`(仅 `embeddingSecretReference` / `rerankerSecretReference` 等引用列) |
| 可单独删 Key / 随全清删除 | `App/Settings/SettingsView.swift`(「删除配置和 API Key」);`SecretStore.removeAllSecrets()` |

## 3. 「Context Minimization:不发整本书、不发无关历史」

| 声明 | 证据 |
|---|---|
| 每次请求仅发送必要上下文 | `Sources/ContextRouting/ContextPlanValidator.swift`:按意图校验计划并施加预算(当前实现:单次总量 6,000 字符;书内证据 1–4 条;过往想法 1 条;记忆 ≤4 条) |
| 预算打包、去重、截断 | `Sources/ContextEngineering/ContextCandidateRanker.swift`(per-source caps,`prefix(take)` 截断)、`Sources/ContextEngineering/ContextAssembler.swift`(dedup → rank → budget-pack) |
| 请求透明:「这次用了哪些内容」 | 反思证据在 UI 呈现(`App/Thoughts/ThoughtsView.swift`);本地请求追踪可查(`App/Settings/DiagnosticsModel.swift`) |
| PRD 依据 | `ReadLoop_PRD.md` §13.1/§13.2(默认原则与请求前最小化流程) |

## 4. 「语音转写为 Apple 系统能力」

| 声明 | 证据 |
|---|---|
| 仅使用 Apple SFSpeechRecognizer,无云端 ASR Provider | `Sources/SpeechCore/SystemSpeechTranscriptionProvider.swift`;PRD §21.1 偏差记录(云端 ASR 移至 v2) |
| 权限用途文案 | `App/Info.plist`:`NSMicrophoneUsageDescription`、`NSSpeechRecognitionUsageDescription`(均为本机转写表述) |

## 5. 「服务商预设列表」

`Sources/ModelProviders/ProviderConfiguration.swift`(`canonicalBaseURL`):OpenAI、DeepSeek、Anthropic(原生 Messages API,`Sources/ModelProviders/AnthropicModelClient.swift`)、Gemini、OpenRouter、Groq、Mistral、xAI、SiliconFlow、Moonshot、阿里云百炼、智谱;另支持任意 OpenAI 兼容 Base URL。

## 6. 「数据控制权」

| 声明 | 证据 |
|---|---|
| Export My Data:含 Memory 与画像,不含 Provider 配置/Key | `Sources/ReflectionCore/PersonalDataExporter.swift`(结构体注释明确排除 provider 配置、密钥引用与 routing traces);导出文件 `elsepage-my-data.json` + ShareLink:`App/Settings/DataSettingsModel.swift` |
| 删除单本书(级联 + 文件) | `App/Settings/DataSettingsModel.swift` → `deleteAllBooks`(FK cascade + 沙盒文件两阶段删除) |
| 清除所有本地数据(两阶段确认、逐类列明) | UI:`App/Settings/SettingsView.swift`(「数据与隐私」区,两级确认弹窗,列出将删除的各类数据);服务:`Sources/Persistence/LocalDataWipeService.swift`(DB 全表事务清除 + `removeAllSecrets`)与 `App/Settings/DataSettingsModel.swift` → `wipeAllLocalData`(另清书文件与 UserDefaults) |

## 7. 政策落地待办(用户/集成者)

1. 渲染并托管两份政策(中文 URL 可与英文同域路径区分),拿到公网 URL;
2. 填写生效日期与联系邮箱(政策中为占位符);
3. App Store Connect「隐私政策网址」填中文/主 URL;审核备注可附英文 URL;
4. App Privacy「营养标签」按 `APP-REVIEW-NOTES.md` 建议勾选 **Data Not Collected**。

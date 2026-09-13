# Voice Reflection 交付水准

## 已完成

- 新增 `ReflectionTextDraft`，用户编辑后的原文成为提交事实源；优化版独立保存，旧优化不会覆盖新原文。
- 新增 `AudioFileStore`，提供草稿、正式文件、staging、trash 和启动恢复。
- 用户主动开始录音后默认保存 AAC/M4A，可在录音前关闭；打开页面不会自动开麦；移除对 MP3 编码能力的假设。
- 多段续录在提交时合并为一个 M4A。
- 保存成功后不再因 View `onDisappear` 删除正式音频。
- 会话内提供紧凑音频管理器：播放/暂停、当前时间/总时长、拖动 seek、删除录音但保留文字；缺失或损坏文件降级为提示。
- 新增 `AudioFileMetadata`（时长、大小、格式、SHA-256）与 `AudioStorageSummary`；数据与隐私页显示录音段数和占用空间，并支持一键清理全部录音。
- 新增 `voice.saveAudioByDefault` 持久化偏好，设置页可控制未来录音是否默认保存。
- 删除 Reflection、删除书、清除全部数据均纳入音频文件清理。
- 导出 JSON 内嵌已保存音频的 Base64。
- 处理录音失败回退、3 秒停止兜底、后台切换、audio session 中断和旧音频路由断开。
- PRD §21.8 记录 V1 默认保存且可关闭的音频保留策略。

## 验证

- `swift test`：368 tests 全部通过。
- 新增 4 个 `ReflectionTextDraft` 测试。
- 新增 8 个 `AudioFileStore` 测试，覆盖提升/回滚、trash 恢复、孤儿清理、多段 M4A 合并、旧扩展名、元数据和存储统计。
- 新增导出音频 Base64 回归测试，以及“仅删除录音、保留 Reflection 文字”的持久化回归测试。
- `git diff --check` 和 App Swift 语法解析通过。

## 待用户真机验收

见 `docs/testing/voice/2026-09-13-delivery-checklist.md`。Xcode 构建、模拟器、真机权限、录音、播放和强杀恢复均由用户完成。

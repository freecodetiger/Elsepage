# Voice Reflection 交付水准

## 已完成

- 新增 `ReflectionTextDraft`，用户编辑后的原文成为提交事实源；优化版独立保存，旧优化不会覆盖新原文。
- 新增 `AudioFileStore`，提供草稿、正式文件、staging、trash 和启动恢复。
- 音频统一为 AAC/M4A；移除对 MP3 编码能力的假设。
- 多段续录在提交时合并为一个 M4A。
- 保存成功后不再因 View `onDisappear` 删除正式音频。
- 支持音频播放；缺失或损坏文件降级为提示。
- 删除 Reflection、删除书、清除全部数据均纳入音频文件清理。
- 导出 JSON 内嵌已保存音频的 Base64。
- 处理录音失败回退、3 秒停止兜底、后台切换、audio session 中断和旧音频路由断开。
- PRD §21.8 记录 V1 音频保留策略偏差。

## 验证

- `swift test`：365 tests 全部通过。
- 新增 4 个 `ReflectionTextDraft` 测试。
- 新增 7 个 `AudioFileStore` 测试，覆盖提升/回滚、trash 恢复、孤儿清理、多段 M4A 合并和旧扩展名。
- 新增导出音频 Base64 回归测试。
- `git diff --check` 和 App Swift 语法解析通过。

## 待用户真机验收

见 `docs/testing/voice/2026-09-13-delivery-checklist.md`。Xcode 构建、模拟器、真机权限、录音、播放和强杀恢复均由用户完成。

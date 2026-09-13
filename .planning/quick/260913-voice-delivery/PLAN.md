# Quick Task: Voice Reflection 交付水准

## Goal

把现有语音 Reflection 从“主流程可演示”修到可交付：用户原文永不丢失；可选音频具备完整文件生命周期；删除、清空、导出与数据库保持一致；运行时失败可恢复；完成自动化与真机验收门禁。

## Locked Decisions

- 继续使用 Apple `SFSpeechRecognizer`，不引入云端 ASR 或新依赖。
- 音频统一为 AAC `.m4a`；不再依赖未被 iOS 可靠保证的 MP3 编码。
- 默认不保存音频；显式开启后永久保存，直到删除 Reflection、删除书或清除全部本地数据。
- 多次续录归属于同一 Reflection，最终音频合并为一个文件。
- 不实现 PRD §18 的“每次询问”模式；在 PRD §21 记录 V1 取舍。
- 音频导出继续使用单一 JSON：已保存音频以 Base64 内嵌，避免引入 ZIP 依赖或不可移植目录分享。

## Workstreams

### 1. Source of Truth

- 用显式草稿状态管理未优化原文、优化文本和当前展示版本。
- 用户编辑原文后，提交必须使用编辑后的原文。
- 语音后清空并改纯文字，保存类型为 `.text`，内容为新文字。
- 续录和优化失败不能回退到旧 `rawTranscript`。
- 纯状态逻辑可在包测试中覆盖。

### 2. Audio Lifecycle

- 新增 `AudioFileStore`：草稿、正式、回收站三个区域。
- 录制写入草稿；提交成功后提升；取消删除草稿；删除操作走可恢复回收站。
- 保存成功后不得因 View `onDisappear` 删除已提升文件。
- 文件写入失败必须可见，且不能阻塞文字 Reflection 保存。
- 启动时清理未引用草稿与孤儿正式文件。

### 3. Data Control

- 删除 Reflection 删除对应音频。
- 删除书籍删除该书 Reflection 音频。
- 清除所有本地数据删除全部音频。
- 个人数据 JSON 导出内嵌已保存音频的 Base64。
- UI 展示音频已保存状态并提供播放/删除入口。

### 4. Runtime Hardening

- 权限、输入路由、格式和转写错误可恢复。
- audio session 中断与路由变化安全收尾。
- 录音中禁止误保存，提交先停止并提升音频。
- 保持长按触感、VoiceOver 和 Dynamic Type 行为。

### 5. Verification

- 扩展 voice 状态、提交幂等、文件提升、删除和孤儿清理测试。
- `swift test`、`git diff --check`、执行器测试全绿。
- 用户真机验证权限、长按、部分转写、优化后编辑、音频播放、删除、清空、强杀恢复。

## Commit Order

1. `spec(voice): lock delivery policy and PRD deviation`
2. `fix(voice): preserve user-edited transcript as source of truth`
3. `feat(voice): add transactional audio file store`
4. `fix(privacy): delete and export voice audio with user data`
5. `fix(voice): harden recording lifecycle and interruptions`
6. `test(voice): cover editing, file lifecycle, deletion and recovery`

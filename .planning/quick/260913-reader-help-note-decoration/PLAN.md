# Quick Task: Reader Help 保存笔记的正文视觉反馈

## Goal

“存为笔记”成功后，在阅读器正文中对对应 locator 显示轻量视觉反馈，而不是只在 help sheet 内显示状态。

## Scope

- Readium 增加独立的 notes decoration group。
- 无 Highlight 的 Note 使用 underline decoration。
- 已有 Highlight 的 Note 继续只显示 Highlight，避免双重装饰。
- 点击 note underline 可打开对应 Note editor。
- 保留 Help sheet 的保存中/已保存反馈。
- 不改变 Note 数据模型和持久化。

## Verification

- App Reader 文件语法解析通过。
- `swift test` 全绿。
- 真机验证保存后正文出现下划线、点击可打开注记。

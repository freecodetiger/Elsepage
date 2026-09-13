# Reader Help Citation 返回体验修复完成

## 已完成

- 点击 Reader Help citation 不再 dismiss sheet。
- 点击后 sheet 自动收起到 184pt compact detent，并跳回对应原文。
- 当前回答、追问历史和 help thread 保留，可重新展开。
- 可见标签从内部 marker `E1/E2` 改为：
  - `原文`
  - `书中`
  - `过去`
- 内部 evidence/citation 协议不变，Reflection Agent 的持久化合同不变。

## 验证

- App 文件纯语法解析通过。
- `swift test` 全绿。
- 真机需确认来源标签点击、原文跳转和面板重新展开。

# Quick Task: Agent Markdown v3 渲染与 Reader Help 长回答

## Goal

让 Agent 输出更长、更有结构的 Markdown，并在用户视角渲染为阅读级排版：标题、段落、列表、引用、分隔线、代码块和 Citation 来源均有明确层级，而不是把 Markdown 压平成纯文本。

## Scope

- 扩展 `makeSelectableMarkdown`，映射 Foundation Markdown block intent。
- 支持标题、无序列表、有序列表、引用块、分隔线、代码块和段落间距。
- 为 Citation 提供上标渲染与底部来源列表。
- 降低 Reader Help 操作按钮和来源说明的视觉权重。
- Reader Help Prompt 升级为更长、结构化的 Markdown 输出契约。
- 提高 Reader Help 输出 token 预算，避免长回答被截断。
- 不使用表格；模型输出表格时安全退化为文本。
- 不引入新依赖。

## Verification

- App Markdown 文件纯语法解析通过。
- `swift test` 全绿。
- 真机验证标题、列表、引用、代码、Citation、长回答滚动和追问。

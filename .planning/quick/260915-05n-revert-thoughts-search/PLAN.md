# Quick Task 260915-05n: 撤回想法页搜索改造

## 目标

恢复搜索改造前的稳定性，不继续试探系统或自定义 morphing。

## 恢复内容

- `ThoughtsView` 恢复为标题下方的系统常驻 `.searchable`。
- 删除自定义搜索控件、FocusState 和展开动画。
- 恢复工具栏仅保留“更多”菜单。
- 恢复 `THOUGHTS_UI_REDESIGN_SPEC.md` 中搜索改造前的描述。
- 保留此前已经交付的其他书架、想法列表和详情改动。

## 验证

- 对比恢复点 `2d1f1c4`，确认两个目标文件无差异。
- Swift parse、diff check、swift test。

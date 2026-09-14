# Quick Task 260915-037: 想法页 Toolbar Search Morphing

## 确认后的交互

- 搜索按钮位于“更多”按钮左侧。
- 点击搜索按钮后，它本身向左展开成搜索框。
- 展开后搜索框撑满顶部可用空间，左右边距对称。
- “更多”按钮位置不变。
- 收起时原路缩回搜索按钮。
- 不在页面内容区新增搜索行。

## 实现

1. 删除 `safeAreaInset` 自定义搜索抽屉。
2. 删除显式自定义工具栏搜索按钮和 FocusState。
3. 使用系统 `searchable(placement: .toolbar)`，让系统完成 toolbar 内的 morphing。
4. 仅保留右侧“更多”菜单作为显式工具栏项。
5. 更新 Spec，明确禁止搜索框在内容区另起一行。

## 验证

- Swift parse、diff check、swift test。
- Xcode 真机确认展开起点、横向撑满和更多按钮保持不动。

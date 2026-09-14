# Quick Task 260915-00w: 想法页自定义搜索抽屉

## 目标

彻底取消常驻搜索条。默认只显示右上角搜索按钮；点击后从右侧展开玻璃搜索框。

## 实现

1. 删除 `searchable` 及其 `isPresented` 状态。
2. 右上角保留显式 `magnifyingglass` 按钮；展开时变为关闭按钮。
3. 在导航内容顶部加入 `safeAreaInset` 搜索抽屉，使用 `.ultraThinMaterial` 玻璃胶囊。
4. 抽屉从右侧移动并淡入，输入框自动聚焦。
5. 关闭抽屉时清空搜索并恢复完整列表。
6. Reduce Motion 下取消展开动画，保持功能。
7. 记录流、分组和详情页不变。

## 验证

- Swift parse、diff check、swift test。
- Xcode 真机确认默认无搜索条及展开动画。

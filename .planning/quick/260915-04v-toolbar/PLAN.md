# Quick Task 260915-04v: 自定义 Toolbar 伸缩搜索

## 背景

系统 `searchable(placement: .toolbar)` 在当前 iOS 导航栏结构中仍显示常驻搜索条，且没有稳定暴露搜索按钮，无法实现确认后的交互。

## 目标

搜索按钮和搜索框属于同一个 toolbar 控件。按钮位于“更多”左侧，点击后原地向左展开，右侧“更多”不移动。

## 实现

1. 删除系统 `searchable`。
2. 在 `ToolbarItemGroup(.topBarTrailing)` 中依次放置自定义搜索控件和更多菜单。
3. 折叠态仅显示 44pt 玻璃搜索按钮。
4. 展开态使用同一控件位置，宽度向左增长并显示输入框与关闭按钮。
5. 输入框自动聚焦；关闭时清空搜索并缩回。
6. 高度保持 44pt，避免 toolbar 跳动。
7. Reduce Motion 下取消宽度动画。
8. 更新 Spec，记录系统 searchable 不满足该场景。

## 验证

- Swift parse、diff check、swift test。
- Xcode 真机确认展开起点、左侧增长和更多按钮不动。

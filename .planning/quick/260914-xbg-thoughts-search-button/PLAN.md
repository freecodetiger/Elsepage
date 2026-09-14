# Quick Task 260914-xbg: 想法页显式搜索按钮

## 目标

让「想法」页的搜索按钮位置确定，不依赖系统根据 toolbar placement 自动推断。

## 修复

- 在右上角工具栏显式加入 `magnifyingglass` 按钮。
- 保留原有“更多”菜单，排在搜索按钮之后。
- 点击搜索按钮后，通过 `isPresented` 展开系统搜索抽屉。
- 页面卡片、分组、详情和底部导航保持不变。

## 验证

- Swift parse、diff check、swift test。
- Xcode 真机确认右上角搜索按钮与搜索抽屉。

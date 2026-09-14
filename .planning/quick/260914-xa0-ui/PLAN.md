# Quick Task 260914-xa0: 想法页搜索入口收起

## 目标

只调整「想法」页搜索入口，其他页面、卡片、分组和详情体验保持不变。

## 任务

1. 移除标题下方常驻搜索框。
2. 使用系统 `searchable(isPresented:placement: .toolbar)`，在右上角显示搜索按钮。
3. 点击右上角搜索按钮后再展开系统搜索体验。
4. 保留右侧更多菜单及其分组、设置入口。
5. 同步更新想法页 Spec 中关于搜索位置的描述。

## 验证

- Swift parse、diff check、swift test。
- Xcode 真机构建与搜索按钮位置验收由用户完成。

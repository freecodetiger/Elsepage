# Readium Selection Range Bridge 完成

## 已完成

- 使用 Readium 公开的 `evaluateJavaScript` 读取浏览器原生 `Range`。
- 计算选区 start/end progression。
- 生成真实 `AnnotationRange(startLocator, endLocator)`。
- 新 Highlight 和 Note 使用精确 Range。
- 精确 Range 存在时，重叠判断使用严格区间相交。
- JS 查询失败时回退单 Locator heuristic，不阻塞选区菜单。
- 不修改 Readium dependency 或 DerivedData。

## 验证

- 新增精确区间 overlap 测试。
- `swift test`：388 tests 全绿。
- App Reader 文件纯语法解析通过。

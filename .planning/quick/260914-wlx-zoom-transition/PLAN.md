# Quick Task 260914-wlx: 书架打开阅读器的连续过渡

## 目标

把“书脊/封面 → Reader”从三段断裂转场改成一次连续的对象移动，并确保 EPUB 准备阶段不跳回空白加载页。

## 任务

1. **建立共享 transition source**
   - 在 `LibraryView` 建立 `Namespace`。
   - 当前阅读封面、书脊和封面模式分别注册 `matchedTransitionSource`。
   - source ID 使用 `BookID`，同一时刻只注册当前可见的那一种书籍形态。

2. **使用 iOS 18 原生 zoom transition**
   - 书架 `navigationDestination` 的 `ReaderScreen` 使用 `.zoom(sourceID:in:)`。
   - Reduce Motion 开启时不注册 zoom transition。
   - 不用第三方依赖，不手写 3D 翻书。

3. **取消人为断点**
   - 删除书脊打开前 `140ms` 的固定等待。
   - 点击松手即触发 Haptic 并开始导航。
   - 保留按压态按钮反馈，不保留异步延迟。

4. **连续化 Reader 准备态**
   - `ReaderScreen` 接收可选封面并显示纸张底色 + 封面占位。
   - Reader 内容准备好后与占位交叉淡入。
   - 无封面调用仍提供非空白 fallback。
   - Reader 不可提前解析封面时不阻塞首帧。

5. **同步规范与验证**
   - 更新书架 spec 的打开转场要求。
   - 运行 Swift parse、diff check、swift test；完成后恢复 Package.resolved。

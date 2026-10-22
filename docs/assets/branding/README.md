# 品牌素材

这里保存独立于 App 构建的 Logo 源素材与导出版本。2026-10-22 从仓库根目录迁入，文件内容未改动。

| 文件 | 用途 |
| --- | --- |
| [logo-vector.svg](logo-vector.svg) | 可编辑的矢量素材 |
| [logo.png](logo.png) | 原始 PNG 导出 |
| [logo-transparent.png](logo-transparent.png) | README 使用的透明背景版本 |
| [logo-transparent-1024.png](logo-transparent-1024.png) | 1024 版本 |
| [logo-transparent-4k.png](logo-transparent-4k.png) | 高分辨率版本；保留用于设计与导出 |

正式 App 图标位于 [AppIcon.appiconset](../../../App/Assets.xcassets/AppIcon.appiconset/Contents.json)。原根目录 `logo-fullbleed.png` 与其中的 [1024 市场图标](../../../App/Assets.xcassets/AppIcon.appiconset/AppIcon-ios-marketing-1024x1024-1x.png) 逐字节相同，已删除重复副本。Asset catalog 中即使图片内容重复，文件名仍被 `Contents.json` 引用，应一并保留。

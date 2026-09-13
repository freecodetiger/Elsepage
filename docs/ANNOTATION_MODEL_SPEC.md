# ReadLoop Annotation Model Refactor Spec

> 状态：Implemented（代码完成，2026-09-13；App 构建与真机验收待用户）
> 分支：`codex/reader-help-spec`
> 适用范围：阅读器 Highlight、Note、下划线、TextAnnotation 的领域模型、交互、迁移和验收
> 核心结论：**Range 是唯一身份；Highlight 和 Note 是彼此独立的标注层。**

---

## 1. 决策摘要

当前模型把笔记作为高亮的附属对象：

```text
Highlight
└── Note(highlightID: HighlightID)
```

这导致：

- 高亮和笔记同时拥有 locator，身份来源重复；
- Note 可以独立，也可以依附 Highlight；
- 高亮菜单曾经包含笔记入口；
- 删除高亮与保留 Note 的关系不清晰；
- 重叠命中依赖 Readium decoration group 顺序；
- UI 需要 conflict picker 临时消歧。

目标模型：

```text
TextAnnotation
├── Range（唯一身份）
├── HighlightLayer?（独立视觉层）
└── NoteEntry[]（独立内容层）
```

Highlighter 不再拥有笔记附属语义。高亮只负责背景色和删除；笔记只负责下划线和内容管理。两者即使落在同一个 Range，也仍然是两个独立的交互层。

---

## 2. 已锁定决策

### Q1：Note 是否允许交叉？

**决定：B。**

- Note 可以部分交叉。
- 不同 start/end 永远属于不同 TextAnnotation。
- 视觉重叠时，使用选择器让用户选择具体 Note。
- Note 不建立父子嵌套语义。

### Q2：同一 Range 同时有 Highlight 和 Note 时如何显示？

**决定：A。**

- 高亮背景和下划线同时显示。
- Highlighter 不再有 Note 附属语义。
- 高亮菜单只包含：
  - 更换颜色；
  - 删除高亮。
- 笔记独立通过下划线进入 Note Sheet。
- 点击重叠区域时使用选择器：
  - 高亮；
  - 笔记。

### Q3：用户尝试创建交叉高亮时怎么处理？

**决定：A。**

- 拒绝创建。
- 给出温柔、明确的提示。
- 不自动合并、扩展或覆盖已有高亮。
- 不破坏已存在的用户数据。

### Q4：同一 Range 的 Note 是单份还是多条历史？

**决定：B。**

- 同一 Range 的笔记使用数组。
- 每次追加笔记创建新的 NoteEntry。
- 已有 NoteEntry 可以独立编辑或删除。
- Range 的下划线只表示“这里存在笔记”，不表示笔记数量。

### Q5：历史交叉高亮如何处理？

**决定：C。**

- 迁移时按高亮更新时间保留较新的高亮。
- 删除较旧的高亮。
- 迁移必须：
  - 在单事务内执行；
  - 生成迁移统计；
  - 保留旧表用于回滚和审计；
  - 不删除任何 Note。

---

## 3. 核心不变量

1. `Range` 的 start/end 完全相同，视为同一个 `TextAnnotation`。
2. start 或 end 不完全相同，视为不同 `TextAnnotation`。
3. 一个 Range 最多有一个 HighlightLayer。
4. 一个 Range 可以有多个 NoteEntry。
5. 高亮和笔记没有父子关系。
6. 高亮是纯视觉层，不包含笔记内容。
7. 笔记是纯内容层，不拥有 `highlightID`。
8. 高亮范围不允许交叉。
9. 相同 Range 再次高亮只更新颜色，不创建第二个高亮对象。
10. Note 允许交叉，但不同 Range 的 Note 永远是不同 TextAnnotation。
11. 点击时如果出现多个可操作层，使用选择器。
12. 无冲突时直接进入唯一的层。

---

## 4. 目标领域模型

### 4.1 AnnotationRange

```swift
public struct AnnotationRange: Hashable, Codable, Sendable {
    public let bookID: BookID
    public let resourceHref: String
    public let startLocator: BookLocator
    public let endLocator: BookLocator
}
```

要求：

- start/end 必须可序列化。
- 同一个 Range 的 resource 必须一致。
- 跨 resource 范围在 v1 不允许创建。
- 旧数据缺少 endLocator 时，使用 legacy 标记，不伪装成精确 Range。

### 4.2 TextAnnotation

```swift
public struct TextAnnotation: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let range: AnnotationRange
    public var highlight: HighlightLayer?
    public var notes: [NoteEntry]
    public let createdAt: Date
    public var updatedAt: Date
}
```

职责：

- Range 是业务身份。
- `id` 是持久化对象 id。
- `highlight` 和 `notes` 是独立层。
- 删除 HighlightLayer 不影响 NoteEntry。
- 删除最后一个 NoteEntry 不影响 HighlightLayer。
- 两层都为空时，删除 TextAnnotation。

### 4.3 HighlightLayer

```swift
public struct HighlightLayer: Hashable, Codable, Sendable {
    public var color: HighlightColor
    public let createdAt: Date
    public var updatedAt: Date
}
```

职责：

- 只管理高亮颜色。
- 渲染为背景色 decoration。
- 不允许交叉。
- 不包含、不访问、不管理 Note。

### 4.4 NoteEntry

```swift
public struct NoteEntry: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public var body: String
    public let createdAt: Date
    public var updatedAt: Date
}
```

职责：

- 一条独立笔记内容。
- 多个 NoteEntry 可以属于同一个 TextAnnotation。
- 渲染为 underline 层。
- 不拥有 highlightID。
- 可以独立编辑和删除。

### 4.5 RangeKey

```text
bookID + resourceHref + canonical(startLocator) + canonical(endLocator)
```

RangeKey 用于：

- 判断两个范围是否完全一致；
- 事务化 upsert TextAnnotation；
- 高亮交叉检测；
- Note 与 Highlight 的同 Range 合并。

---

## 5. 行为规则

### 5.1 Range 身份

| 情况 | 结果 |
|---|---|
| start/end 完全相同 | 同一个 TextAnnotation |
| start 或 end 不同 | 不同 TextAnnotation |
| 同一 resource 部分重叠 | 不同对象；允许 Note，不允许 Highlight |
| 跨 resource | v1 不允许 |
| endLocator 缺失的旧数据 | legacy 模式，使用保守匹配 |

### 5.2 Highlight 创建与更新

1. 按 RangeKey 查询既有 TextAnnotation。
2. 相同 Range 已有 HighlightLayer：
   - 不创建第二个高亮；
   - 更新颜色；
   - 更新 `updatedAt`。
3. 与其他 HighlightLayer 部分交叉：
   - 拒绝；
   - 显示温柔提示，例如“这里和已有高亮部分重叠，先保留原来的高亮吧”；
   - 提供“打开已有高亮”作为可选操作。
4. 完全不相交：
   - 创建新的 TextAnnotation 和 HighlightLayer。
5. HighlightLayer 永远不因为 Note 的存在而被禁用；是否共用同一个 TextAnnotation 只由 Range 决定。

### 5.3 Note 创建与追加

1. 按 RangeKey 查询 TextAnnotation。
2. 没有 TextAnnotation：
   - 创建 TextAnnotation。
   - 创建第一条 NoteEntry。
3. 已有 TextAnnotation：
   - 追加新的 NoteEntry；
   - 不修改 HighlightLayer；
   - 不把 NoteEntry 变成 Highlight 的 child。
4. 相同 Range 有多个 NoteEntry：
   - underline 只渲染一次；
   - 点击进入 Note Sheet；
   - Sheet 展示该 Range 的 NoteEntry 列表。
5. 不同 Range 的 Note：
   - 永远属于不同 TextAnnotation；
   - 即使视觉范围部分交叉，也不合并。
6. Note Sheet 允许：
   - 新增一条 NoteEntry；
   - 编辑单条 NoteEntry；
   - 删除单条 NoteEntry；
   - 删除整个 Range 的所有 NoteEntry。

### 5.4 点击与选择器

当点击点只对应一个可操作层：

- HighlightLayer → 打开高亮菜单。
- NoteEntry → 打开 Note Sheet。

当点击点对应多个可操作层：

- 高亮和笔记同时覆盖 → 显示“高亮 / 笔记”选择器。
- 多个不同 TextAnnotation 的 Note 覆盖 → 显示 Note 选择器。
- 多个 Highlight 理论上不应存在；若旧数据出现，显示冲突选择器并标记 legacy conflict。

选择器要求：

- 只在真实重叠时出现。
- 无冲突时不出现。
- 选项标题必须明确说明操作对象。
- 选择后进入对应的层 UI，不重新创建对象。

### 5.5 高亮菜单

高亮菜单只保留：

- 更换颜色；
- 删除高亮。

不再包含：

- 笔记入口；
- 笔记内容；
- 把笔记绑定到高亮的动作。

### 5.6 Note Sheet

Note Sheet 负责：

- 展示当前 Range 的 NoteEntry 列表；
- 新建 NoteEntry；
- Markdown 预览；
- 编辑单条 NoteEntry；
- 删除单条 NoteEntry；
- 删除整个 Range 的笔记层。

视觉规则：

- NoteLayer 统一使用 underline。
- 不因 NoteEntry 数量改变 underline 样式。
- NoteEntry 内容使用 Markdown 预览和编辑双态。

### 5.7 删除语义

| 操作 | 结果 |
|---|---|
| 删除高亮 | 只删除 HighlightLayer，保留所有 NoteEntry |
| 删除单条笔记 | 只删除该 NoteEntry |
| 删除全部笔记 | 保留 HighlightLayer |
| 两层都为空 | 删除 TextAnnotation |
| 删除书籍 | 级联删除所有 TextAnnotation 和 NoteEntry |
| 清除所有数据 | 删除所有标注、索引和派生关系 |

---

## 6. 持久化与迁移

### 6.1 推荐表结构

```sql
CREATE TABLE textAnnotations (
  id TEXT PRIMARY KEY,
  bookID TEXT NOT NULL,
  resourceHref TEXT NOT NULL,
  startLocatorJSON BLOB NOT NULL,
  endLocatorJSON BLOB NOT NULL,
  rangeKey TEXT NOT NULL,
  highlightColor TEXT,
  createdAt DATETIME NOT NULL,
  updatedAt DATETIME NOT NULL,
  legacyConflict INTEGER NOT NULL DEFAULT 0
);

CREATE UNIQUE INDEX textAnnotationsRange
ON textAnnotations(bookID, rangeKey);

CREATE TABLE annotationNotes (
  id TEXT PRIMARY KEY,
  annotationID TEXT NOT NULL REFERENCES textAnnotations(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  createdAt DATETIME NOT NULL,
  updatedAt DATETIME NOT NULL
);
```

### 6.2 迁移策略

1. 创建 `textAnnotations` 和 `annotationNotes`。
2. 对每个旧 Highlight：
   - 创建 TextAnnotation；
   - 保留颜色；
   - 生成 RangeKey。
3. 对每个旧 Note：
   - 如果是依附 Note，优先尝试匹配 Highlight Range；
   - 精确同 Range → 追加到该 TextAnnotation 的 NoteEntry；
   - 不同 Range → 创建独立 TextAnnotation，并记录 legacy relation；
   - 独立 Note → 创建 Note-only TextAnnotation。
4. 旧高亮交叉：
   - 按 `updatedAt`（旧数据可用 `createdAt`）保留较新的高亮；
   - 删除较旧的高亮；
   - 保留全部 NoteEntry；
   - 生成迁移统计和审计文件。
5. 旧表保留只读一个版本周期，作为回滚和审计来源。
6. 新代码不再写入 `notes.highlightID`。
7. Reader Help 保存 Note 时只追加 NoteEntry，不尝试挂到 Highlight。

### 6.3 数据控制

- Export 输出 TextAnnotation、HighlightLayer 和 NoteEntry。
- Delete Book 级联删除新表和旧表。
- Wipe All Data 清除新表、旧表、缓存和索引。
- Reflection 对旧 Highlight 的引用通过 legacy mapping 保持可解析。

---

## 7. 范围判断

### 7.1 Exact Range

```text
canonical(resource, start, end) 完全相同 -> 同一个 TextAnnotation
```

### 7.2 Highlight Intersection

高亮创建前，必须在同一事务内检查：

- 是否存在 exact Range；
- 是否存在部分交叉；
- 是否存在 legacy 不可判定范围。

处理：

- exact → update color；
- partial overlap → reject；
- legacy uncertain → reject new crossing creation，提示用户先整理旧标注。

### 7.3 Note Overlap

Note 允许交叉，因此：

- 不同 Range 不合并；
- 点击出现重叠时使用 selector；
- 同一个 Range 的多个 NoteEntry 聚合在同一个 Note Sheet 中；
- Note 不会影响 Highlight 的创建合法性。

---

## 8. 测试计划

### Domain

- 相同 start/end → 同一个 TextAnnotation。
- start 或 end 不同 → 不同 TextAnnotation。
- 同 Range 添加多个 NoteEntry → 数组增长，不创建新 TextAnnotation。
- 同 Range 再次高亮 → 更新颜色，不创建第二个 HighlightLayer。
- 删除 HighlightLayer → NoteEntry 保留。
- 删除单条 NoteEntry → 其他 NoteEntry 保留。
- 删除最后一条 NoteEntry → HighlightLayer 保留。

### Persistence

- RangeKey 稳定，JSON key 顺序不影响 identity。
- `UNIQUE(bookID, rangeKey)` 生效。
- 旧 Highlight + 依附 Note 正确合并到同一 Range。
- 不同 Range 的依附 Note 被拆成独立 TextAnnotation。
- 旧交叉高亮保留较新者并记录迁移统计。
- Export / Delete Book / Wipe All Data 覆盖新表。

### UI

- Highlight 菜单只显示颜色和删除。
- Note Sheet 显示 NoteEntry 列表并允许追加。
- 同一 Range 的 Highlight + Note 点击时显示选择器。
- 不同 Range 的 Note 交叉时显示 selector。
- 无冲突时不得出现 selector。
- 高亮交叉创建显示温柔提示，不修改旧数据。

### Compatibility

- Reader Help 保存 Note 不依赖 Highlight 是否已存在。
- Reflection Citation / Jump 仍能定位。
- 旧数据升级后可读取、导出和删除。
- 旧表回滚路径可验证。

---

## 9. 实施阶段

### Phase 1：Domain

- 新增 `AnnotationRange`、`TextAnnotation`、`HighlightLayer`、`NoteEntry`。
- 实现 RangeKey canonicalization。
- 实现 highlight intersection / note overlap 判定。
- 增加纯单元测试。

### Phase 2：Persistence

- 新增 `textAnnotations`、`annotationNotes`。
- 实现事务化 upsert。
- 实现数据迁移和旧表 legacy mapping。
- 增加迁移、删除、导出测试。

### Phase 3：Reader Model

- ReaderModel 以 TextAnnotation 为中心。
- Highlight 菜单只管理颜色/删除。
- Note Sheet 改为 NoteEntry 列表和追加编辑。
- 移除 `Note.highlightID` 的领域语义。
- 保留兼容 API shim。

### Phase 4：Readium UI

- HighlightLayer → highlight group。
- NoteLayer → underline group。
- 多层的重叠点击进入选择器。
- 同一 Note Range 的多个 NoteEntry 只渲染一次 underline。
- 旧数据 crossing conflict 只通过 selector 兼容。

### Phase 5：真机验收

- 同 Range 高亮与笔记。
- 多个 NoteEntry 追加。
- Note 交叉。
- 高亮交叉拒绝。
- 删除单层。
- 旧数据迁移。
- Reader Help 保存笔记。
- Reflection / Citation / Export / Wipe。

---

## 10. 非目标

- 不实现 Note 父子嵌套。
- 不实现任意多 HighlightLayer。
- 不实现跨 resource 连续标注。
- 不实现云端同步。
- 不重写 Readium。
- 不把笔记继续作为 Highlight 的隐藏字段。

---

## 11. 最终验收定义

```text
相同 Range = 一个 TextAnnotation
不同 Range = 不同 TextAnnotation
一个 Range 最多一个 HighlightLayer
一个 Range 可有多条 NoteEntry
高亮禁止交叉
笔记允许交叉
高亮只管理颜色和删除
笔记统一下划线归属
重叠点击显示选择器
无冲突点击直接进入对应层
```

Highlighter 保持纯粹；Note 不再依附 Highlight；Range 成为唯一且稳定的身份锚点。


---

## 12. 实现记录（2026-09-13）

### Domain

- 新增 `AnnotationRange`、`TextAnnotation`、`HighlightLayer`、`NoteEntry`。
- 新增 `TextAnnotationRepository`。
- `AnnotationRange.rangeKey` 使用 canonical locator identity。
- 同一 Range 合并，不同 Range 分对象。
- NoteEntry 支持数组追加。

### Persistence

- 新增 migration `v28_text_annotations`。
- 新增 `textAnnotations` 和 `annotationNotes`。
- 旧 Highlight / Note 自动迁移：
  - 同 Range 的依附 Note 合并为 NoteEntry。
  - 独立 Note 保持独立 Range。
  - 历史交叉 Highlight 按较新者保留，旧表同步清理。
- 新 repository 写入时镜像旧表，保证 Session / Journal / Export / Stats 兼容。
- 旧表保留用于回滚和审计。

### Reader

- ReaderModel 以 TextAnnotation 为中心。
- `highlights` / `notes` 变为兼容投影。
- Highlighter 菜单只保留换色和删除。
- NoteEntry 支持追加和切换。
- 同一 Range 同时有 Highlight 和 Note 时显示“高亮 / 笔记”选择器。
- 不同 Range 的 Note 交叉仍保留为不同对象。
- Readium notes group 每个 Range 只渲染一次 underline。

### Verification

- `swift test`：387 tests 全绿。
- 新增 TextAnnotation repository roundtrip 测试。
- 新增 v27→v28 迁移测试。
- 新增历史交叉 Highlight 保留较新者测试。
- App Reader 文件纯语法解析通过。



---

## 13. Readium Range 适配

已在 App 本地通过 Readium 公开的 `evaluateJavaScript` 读取浏览器原生 `Range`，计算 selection 的 start/end progression，并生成真实 `AnnotationRange`。

- 不修改 Readium dependency 或 DerivedData。
- 读取失败时回退到单 Locator 的保守模式。
- 新 Highlight / Note 使用精确 start/end。
- 两层都有精确 progression 时，范围相交使用严格区间判断。
- Readium selection 仍是单 Locator 的公开 Swift API，但 App 通过 JS bridge 补齐 range。

# ReadLoop Annotation Model Refactor Spec

> 状态：Draft / 待决策（2026-09-13）
> 分支：`codex/reader-help-spec`
> 适用范围：阅读器 Highlight、Note、下划线、TextAnnotation 的领域模型、交互、迁移和验收
> 核心结论：**Range 是唯一身份；Highlight 和 Note 是同一标注对象上的独立视觉层。**

---

## 1. 决策摘要

当前模型把笔记作为高亮的附属对象：

```text
Highlight
└── Note(highlightID: HighlightID)
```

这导致高亮、笔记和它们各自的 locator 同时参与身份判断，最终产生：

- 同一段文字既像一个 Highlight，又像一个 Note；
- Note 可以独立存在，也可以依附 Highlight；
- 两者部分重叠时，点击命中依赖 Readium decoration group 顺序；
- 删除 Highlight 与保留 Note 的关系不清晰；
- 代码需要通过 conflict picker 临时解决视觉歧义；
- “高亮”和“笔记”的语义边界不稳定。

本 spec 决定把模型改成：

```text
TextAnnotation
├── Range（唯一身份）
├── HighlightLayer（可选）
└── NoteLayer（可选）
```

### 核心不变量

1. `Range` 的 start/end 完全相同，视为同一个 `TextAnnotation`。
2. start 或 end 不完全相同，视为不同 `TextAnnotation`。
3. 高亮和笔记不再是父子关系。
4. 高亮是纯视觉层，不包含笔记内容。
5. 笔记是纯内容层，不再拥有 `highlightID`。
6. 同一 Range 最多有一个 HighlightLayer 和一个 NoteLayer。
7. 高亮范围不允许交叉；相同范围只能复用或更新。
8. 笔记可以没有高亮，高亮也可以没有笔记。
9. 同一 Range 同时有高亮和笔记时，点击进入同一个标注详情面板，不再做“二选一”。
10. 旧数据不得静默删除；历史交叉数据需要迁移或显式标记。

---

## 2. 当前实现证据

### 2.1 Domain

- `Sources/ReaderCore/BookLocator.swift`
  - `Highlight` 只有一个 `locator`。
  - `Note` 有 `highlightID: UUID?` 和独立 `locator`。
- `Sources/ReaderCore/ReaderCoordination.swift`
  - 高亮使用 locator identity 去重。
- `App/Reader/ReaderModel.swift`
  - `saveNote(for highlight:)` 创建依附 Note。
  - `deleteHighlightWithUndo` 会把关联 Note 脱钩为独立 Note。
  - Reader Help 保存 Note 时会主动挂到相同 anchor 的 Highlight。
  - 当前冲突选择器在 `handleHighlightActivation` / `handleNoteActivation` 中临时消歧。

### 2.2 Persistence

- `Sources/Persistence/AppDatabase.swift`
  - `highlights` 与 `notes` 是两张表。
  - `notes.highlightID` 可空，并带 `onDelete: .setNull`。
- `Sources/Persistence/Repositories.swift`
  - `save(highlight:note:)` 强制校验 `note.highlightID == highlight.id`。
  - `deleteHighlight` 会让 Note 与 Highlight 脱钩。
- 现有数据结构缺少明确的 `startLocator` / `endLocator`，无法精确判断两个文本范围是否完全一致或部分交叉。

### 2.3 UI / Readium

- Highlight 和 Note 使用不同的 decoration group。
- Note underline 与 Highlight 重叠时，Readium 的命中结果依赖 group 创建顺序。
- 当前 conflict picker 是过渡方案，不是长期领域模型。

---

## 3. 目标领域模型

### 3.1 TextRange

```swift
public struct TextRange: Hashable, Codable, Sendable {
    public let bookID: BookID
    public let resourceHref: String
    public let startLocator: BookLocator
    public let endLocator: BookLocator
}
```

要求：

- start/end 都必须可序列化。
- resource 必须一致；跨 resource 的范围在当前版本不允许创建。
- start/end 用于范围判断，而不是只依赖 `textHighlight` 或一个 progression。
- 旧数据缺少 endLocator 时，迁移层使用 legacy 标记，不伪装成完整 Range。

### 3.2 TextAnnotation

```swift
public struct TextAnnotation: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let range: TextRange
    public var highlight: HighlightLayer?
    public var note: NoteLayer?
    public let createdAt: Date
    public var updatedAt: Date
}
```

语义：

- `id` 是持久化对象 id。
- `range` 是业务身份。
- `highlight` 和 `note` 都是可选层。
- 删除一层不删除另一层。
- 两层都为空时，删除整个对象。
- 一个 Range 不允许产生两个 TextAnnotation；数据库需要唯一约束或事务级 upsert。

### 3.3 HighlightLayer

```swift
public struct HighlightLayer: Hashable, Codable, Sendable {
    public var color: HighlightColor
    public let createdAt: Date
    public var updatedAt: Date
}
```

职责：

- 只表达视觉高亮。
- 不存储笔记内容。
- 不允许跨范围交叉。
- 相同 Range 的高亮操作只更新颜色或复用已有层。

### 3.4 NoteLayer

```swift
public struct NoteLayer: Hashable, Codable, Sendable {
    public var body: String
    public let createdAt: Date
    public var updatedAt: Date
}
```

职责：

- 只表达能力/内容。
- 渲染为 underline，而不是 Highlight 的附属 UI。
- 不再有 `highlightID`。
- 同一 Range 默认只有一个 NoteLayer。

### 3.5 AnnotationRangeKey

范围身份建议使用规范化 key：

```text
bookID + resourceHref + canonical(startLocator) + canonical(endLocator)
```

规范化要求：

- JSON key 排序稳定；
- 忽略无意义的 JSON 顺序差异；
- 不把 `textBefore` / `textAfter` 当作身份的一部分；
- 同一 Range 的文本变更不应产生新对象，除非 start/end 确实变化。

---

## 4. 核心规则

### 4.1 范围身份

| 情况 | 结果 |
|---|---|
| start/end 完全相同 | 同一个 TextAnnotation |
| start 或 end 不同 | 不同 TextAnnotation |
| 同一 resource 但范围部分重叠 | 不同对象，进入冲突/边界政策 |
| 跨 resource | v1 不允许 |
| endLocator 缺失的旧数据 | legacy 模式，不能当作精确 Range |

### 4.2 高亮规则

1. 一个 Range 最多一个 HighlightLayer。
2. 创建高亮时先按 RangeKey 查询。
3. 相同 Range 已存在高亮：
   - 不创建第二个高亮对象；
   - 更新颜色或返回已有对象。
4. 部分交叉：
   - 拒绝创建；
   - 不自动拆分或覆盖用户已有高亮；
   - UI 提供打开已有高亮或取消。
5. 完全不相交：
   - 创建新的 TextAnnotation。
6. 高亮禁止交叉，包括：
   - A 包含 B；
   - A 与 B 部分重叠；
   - 两端交叉但没有完全包含。

### 4.3 笔记规则

1. 相同 Range 已有 TextAnnotation：
   - 已有 NoteLayer 则编辑；
   - 没有 NoteLayer 则追加。
2. 相同 Range 已有 HighlightLayer：
   - 不把 Note 当作 Highlight 的 child；
   - 将 NoteLayer 追加到同一个 TextAnnotation。
3. 不同 Range：
   - 创建新的 TextAnnotation，即使视觉上相邻或部分重叠。
4. 一个 Range 默认只保留一份 NoteLayer，不建立多条笔记历史。
5. 笔记的 visual 归属是 underline，不是 highlight。
6. 笔记是否允许与另一笔记/高亮部分交叉，见待决问题 Q1。

### 4.4 点击与选择

新模型下：

- 点击 HighlightLayer：打开对应 TextAnnotation 详情。
- 点击 NoteLayer underline：打开对应 TextAnnotation 详情。
- 同一 Range 同时存在两层：打开同一个详情面板。
- 不再回答“这是高亮还是笔记”。
- 仅当两个不同 Range 的真实范围重叠时，才显示二次选择器。
- conflict picker 保留为迁移兼容和真正的跨 Range 冲突兜底。

### 4.5 删除

| 操作 | 结果 |
|---|---|
| 删除高亮 | 只删除 HighlightLayer，保留 NoteLayer |
| 删除笔记 | 只删除 NoteLayer，保留 HighlightLayer |
| 两层都删除 | 删除 TextAnnotation |
| 删除书籍 | 级联删除该书的 TextAnnotation |
| 清除所有数据 | 删除全部 TextAnnotation 及派生索引 |

---

## 5. 视觉和交互

### 5.1 Layer 渲染

```text
HighlightLayer
  -> 背景色 decoration

NoteLayer
  -> underline decoration

同一 TextAnnotation 两层
  -> 背景 + underline 同时渲染
  -> 点击任一层进入同一详情面板
```

### 5.2 Annotation Detail Sheet

建议统一为：

```text
这段文字的标注

高亮：黄色
[调整颜色]

笔记：
<Markdown 预览>

[编辑笔记] [删除高亮] [删除笔记]
```

只有高亮时：

```text
高亮：黄色
[调整颜色] [删除高亮]
```

只有笔记时：

```text
笔记：
<Markdown 预览>
[编辑笔记] [删除笔记]
```

### 5.3 选区工具栏

建议保持两个语义明确的操作：

- `高亮`：创建或更新 HighlightLayer。
- `笔记`：创建或编辑 NoteLayer。

如果同一 Range 两种层都存在，按钮分别表示当前层的状态，不新增第三个“专属高亮笔记”概念。

---

## 6. 持久化方案

### 6.1 推荐结构

新增 `textAnnotations` 聚合表：

```sql
CREATE TABLE textAnnotations (
  id TEXT PRIMARY KEY,
  bookID TEXT NOT NULL,
  resourceHref TEXT NOT NULL,
  startLocatorJSON BLOB NOT NULL,
  endLocatorJSON BLOB NOT NULL,
  rangeKey TEXT NOT NULL,
  highlightColor TEXT,
  noteBody TEXT,
  createdAt DATETIME NOT NULL,
  updatedAt DATETIME NOT NULL,
  legacyConflict INTEGER NOT NULL DEFAULT 0
);
```

索引：

- `UNIQUE(bookID, rangeKey)`
- `INDEX(bookID, resourceHref, startProgression, endProgression)`
- `INDEX(bookID, updatedAt)`

说明：

- `highlightColor` 为空表示没有高亮层。
- `noteBody` 为空表示没有笔记层。
- 两层都为空时删除行。
- 不新增笔记历史表；若未来需要版本历史，另建派生表。

### 6.2 兼容迁移

1. 创建 `textAnnotations`。
2. 对每个旧 Highlight 创建/复用 TextAnnotation。
3. 对每个旧 Note：
   - 若有 `highlightID` 且 locator 与对应 Highlight 为同一 Range：合并为同一 TextAnnotation 的 NoteLayer。
   - 若有 `highlightID` 但 locator 不同：创建独立 TextAnnotation，并记录 legacy relation。
   - 若无 `highlightID`：创建 Note-only TextAnnotation。
4. 旧 Highlight / Note 表保留至少一个迁移周期，作为只读回滚/审计来源。
5. 新代码不再写入 `notes.highlightID`。
6. 旧交叉高亮：
   - 不静默删除；
   - 标记 `legacyConflict`；
   - 新规则生效后不再创建新的交叉高亮；
   - 提供后续整理入口。

### 6.3 数据控制

- Export 需要输出统一 `TextAnnotation` 结构，同时保留兼容字段。
- Delete book / Wipe all data 必须级联到聚合表和旧表。
- Reflection 对旧 Highlight 的引用需要迁移映射到 TextAnnotation id 或保留 legacy highlight id 映射。

---

## 7. 范围判断与冲突

### 7.1 Range 相等

```text
canonical(start/end/resource) 完全相同 -> 同一对象
```

### 7.2 高亮交叉检测

创建或修改高亮前：

1. 查询同 resource 的所有高亮范围。
2. 精确相同：复用。
3. 部分交叉：拒绝。
4. 完全不相交：允许。

由于旧数据可能缺少 endLocator，legacy 高亮只能使用 conservative fallback：

- 同一 `BookLocator` identity；
- 相同 resource + 相同 normalized text + progression 接近；
- 不确定时不自动合并，标记为 legacy conflict。

### 7.3 Note 交叉

待决：

- 允许不同 Range 的 Note 部分交叉；
- 允许 Note 与 Highlight 部分交叉；
- 或对所有 annotation 统一禁止交叉。

如果允许交叉，必须保留按 TextAnnotation 的 selector 或统一的详情入口，不能依赖 decoration group 顺序。

---

## 8. 测试计划

### Domain

- 相同 start/end -> 同一 TextAnnotation。
- start 不同或 end 不同 -> 不同 TextAnnotation。
- 同 Range 添加 Note -> 追加 NoteLayer，不创建第二个对象。
- 同 Range 再次添加 Highlight -> 更新/复用，不创建第二个对象。
- 删除一层保留另一层。
- 两层都删除才删除对象。

### Persistence

- RangeKey 稳定，JSON key 顺序不影响 identity。
- `UNIQUE(bookID, rangeKey)` 生效。
- 旧 Highlight + 依附 Note 合并。
- 独立 Note 正确迁移。
- 旧交叉 Highlight 不丢失并标记。
- Export / delete book / wipe all data 覆盖新表。

### UI

- Exact same Range 的 Highlight + Note 只出现一个详情入口。
- Highlight 与 Note 不同 Range 部分重叠时才出现 selector。
- 高亮交叉创建被拒绝。
- 同一范围不会出现两个高亮 decoration。
- Note underline 与 Highlight 点击不再依赖 group 创建顺序。

### 兼容

- Reader Help 保存 Note 不依赖 Highlight 是否已存在。
- Reflection citation / Jump 到原文仍能定位。
- 旧 Highlight 删除、Note 脱钩和 undo 行为迁移一致。
- 旧数据升级后没有静默丢失。

---

## 9. 实施阶段

### Phase 1：Range 与聚合 Domain

- 新增 `TextRange`、`TextAnnotation`、`HighlightLayer`、`NoteLayer`。
- 新增 RangeKey canonicalization。
- 明确 equality、overlap 和 legacy 行为。

### Phase 2：Persistence + Migration

- 新增 `textAnnotations`。
- 迁移 Highlight 与 Note。
- 保持旧表只读兼容。
- 加入 DB 唯一约束和交叉测试。

### Phase 3：Reader Repository / Model

- `ReaderModel` 以 TextAnnotation 为中心。
- 移除 `saveNote(for highlight:)` 的领域语义。
- `Highlight` / `Note` UI 通过 layer API。
- 保留旧 API shim 直到迁移完成。

### Phase 4：Readium UI

- HighlightLayer → highlight group。
- NoteLayer → underline group。
- 同一 TextAnnotation 的两层点击进入同一详情面板。
- 冲突 selector 只处理 legacy 或不同 Range 的真实重叠。

### Phase 5：迁移验收

- 真机验证：
  - 同 Range 追加笔记
  - 高亮禁止交叉
  - 删除单层
  - 旧数据迁移
  - Reader Help 保存笔记
  - Reflection / Citation / Export / Wipe

---

## 10. 非目标

- 不实现跨 resource 的连续标注。
- 不实现任意多高亮层叠加。
- 不实现笔记历史版本流。
- 不实现云端同步。
- 不重写 Readium 本身。
- 不把笔记变成高亮的隐藏字段。

---

## 11. 待用户决策问题

### Q1. Note 是否允许交叉？

- A：Note 也禁止交叉，和 Highlight 一样严格。
- B：Note 可以部分交叉，但不同 Range 仍是不同对象，使用 selector 消歧。
- C：Note 可以包含另一个 Note，形成父子层次。

推荐：A 或 B；如果目标是彻底消除点击歧义，推荐 A。

### Q2. 同一 Range 同时有 Highlight 和 Note，如何显示？

- A：背景高亮 + 下划线同时显示，详情面板统一编辑。
- B：添加 Note 后移除 Highlight，只保留下划线。
- C：只允许二选一，存在其中一层时禁止添加另一层。

推荐：A。它符合“Highlighter 纯粹、Note 归属 underline”，同时不丢失已有高亮。

### Q3. 用户尝试创建交叉高亮时怎么处理？

- A：直接拒绝，提示已有高亮。
- B：弹出操作：打开已有高亮 / 修改范围 / 取消。
- C：自动合并或扩展旧高亮。

推荐：B。A 信息太少，C 会隐式修改用户数据。

### Q4. 同一 Range 的 Note 是单份还是可以追加多条历史？

- A：单份 NoteLayer，再次保存覆盖/更新正文。
- B：一个数组，保留每次追加内容。
- C：单份正文，但保留本地修订历史。

推荐：A。当前产品需要稳定语义，不需要把简单笔记演化成时间线。

### Q5. 历史交叉高亮如何处理？

- A：保留全部数据，标记冲突，让用户在标注列表逐条整理。
- B：按创建时间合并为较大范围。
- C：按更新时间保留较新高亮，删除较旧高亮。

推荐：A。它避免迁移阶段静默破坏用户数据。

---

## 12. 最终验收定义

完成后应满足：

```text
同一段文字 = 一个 TextAnnotation
高亮 = 可选 HighlightLayer
笔记 = 可选 NoteLayer
相同 Range = 合并
不同 Range = 不同对象
高亮禁止交叉
笔记不再依附高亮
点击任一层 = 同一标注详情
```

这样高亮的语义保持纯粹，笔记统一下划线归属，冲突选择器不再是主流程，只作为旧数据和真正跨 Range 冲突的兼容机制。

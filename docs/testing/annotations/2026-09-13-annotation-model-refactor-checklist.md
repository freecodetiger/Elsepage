# Annotation Model Refactor 真机验收清单

> 状态：待用户执行
> 分支：`codex/reader-help-spec`
> 迁移：`v28_text_annotations`

## 1. 迁移

- [ ] 使用包含旧 Highlight / Note 的数据库升级后，书籍、Highlight、Note 均未丢失
- [ ] 依附 Note 与同 Range Highlight 合并到同一 TextAnnotation
- [ ] 独立 Note 仍保持独立 Range
- [ ] 历史交叉 Highlight 只保留较新的一个
- [ ] 旧表与新表内容一致
- [ ] 清除所有本地数据后 `textAnnotations`、`annotationNotes` 和旧表均为空

## 2. Highlight

- [ ] 高亮只提供换色和删除
- [ ] 高亮菜单不再出现笔记入口
- [ ] 相同 Range 再次高亮只更新颜色
- [ ] 部分交叉的高亮被拒绝并出现温柔提示
- [ ] 删除高亮不会删除同 Range 的 NoteEntry

## 3. Note

- [ ] 同一 Range 可以追加多条 NoteEntry
- [ ] 多条 NoteEntry 只显示一次 underline
- [ ] Note Sheet 可以切换不同 NoteEntry
- [ ] 编辑一条 NoteEntry 不影响其他条目
- [ ] 删除一条 NoteEntry 不影响 Highlight 和其他 NoteEntry
- [ ] 不同 Range 的 Note 可以部分交叉且保持不同对象

## 4. 重叠交互

- [ ] 同一 Range 有 Highlight 和 Note 时，点击出现“高亮 / 笔记”选择器
- [ ] 选择“高亮”进入换色/删除菜单
- [ ] 选择“笔记”进入 Note Sheet
- [ ] 无冲突区域不显示选择器
- [ ] 旧数据冲突仍可通过 selector 打开目标对象

## 5. 兼容

- [ ] Reader Help 保存 Note 时追加 NoteEntry
- [ ] Reflection Citation 跳回原文正常
- [ ] Session 的 Highlight / Note 数量正确
- [ ] LibraryStats 的 Highlight / Note 数量正确
- [ ] Export 包含新标注结构和旧兼容字段
- [ ] Delete Book / Wipe All Data 正确清理新表和旧表

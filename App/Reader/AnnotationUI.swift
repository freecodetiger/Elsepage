import AppInfrastructure
import ReaderCore
import SwiftUI
import UIKit

// MARK: - Shared color mapping

extension HighlightColor {
    /// Swatch used in annotation toolbars. Tints differ from the reader's
    /// translucent highlight decorations: these must stay visible on material.
    var annotationColor: Color {
        switch self {
        case .yellow: Color(red: 0.96, green: 0.78, blue: 0.24)
        case .green: Color(red: 0.36, green: 0.72, blue: 0.43)
        case .blue: Color(red: 0.32, green: 0.56, blue: 0.90)
        case .pink: Color(red: 0.90, green: 0.42, blue: 0.61)
        }
    }

    var displayName: String {
        switch self {
        case .yellow: "黄色"
        case .green: "绿色"
        case .blue: "蓝色"
        case .pink: "粉色"
        }
    }

    var accessibilityName: String {
        switch self {
        case .yellow: "黄色高亮"
        case .green: "绿色高亮"
        case .blue: "蓝色高亮"
        case .pink: "粉色高亮"
        }
    }
}

// MARK: - Overlay container

/// Full-screen overlay hosting the in-place annotation UI: the selection
/// toolbar, the highlight menu, and the transient undo/copy pill.
///
/// The container expands beyond the safe area so its coordinates line up 1:1
/// with the Readium navigator frames that anchor everything. It never
/// participates in the reader's layout (zero layout shift).
struct ReaderAnnotationOverlays: View {
    let model: ReaderModel
    /// Keeps transient feedback above a collapsed sheet so "已回到原文" is
    /// visible at the moment the citation jump lands.
    var noticeBottomInset: CGFloat = 0
    private static let margin: CGFloat = 12
    fileprivate static let gap: CGFloat = 10
    fileprivate static let menuSizeEstimate = CGSize(width: 340, height: 56)

    /// Safe-area insets from the key window. The overlay's GeometryReader
    /// ignores the safe area so its coordinates match the navigator's
    /// full-screen frames 1:1 — which also means the insets it would report
    /// itself are zero, so the authoritative values come from UIKit.
    private static var windowInsets: EdgeInsets {
        let insets = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
        return EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
    }

    var body: some View {
        GeometryReader { proxy in
            let insets = Self.windowInsets
            let fullSize = proxy.size
            // Clamping bounds keep menus inside the safe area plus a margin.
            let safeBounds = CGRect(
                x: insets.leading + Self.margin,
                y: insets.top + Self.margin,
                width: max(0, fullSize.width - insets.leading - insets.trailing - Self.margin * 2),
                height: max(0, fullSize.height - insets.top - insets.bottom - Self.margin * 2)
            )

            ZStack {
                if case .selection(let context) = model.annotationMenu {
                    SelectionCatcher(
                        selectionFrame: context.frame,
                        fullSize: fullSize,
                        insets: insets
                    ) {
                        model.dismissSelectionMenu()
                    }
                }

                switch model.annotationMenu {
                case .selection(let context):
                    AnchoredMenu(anchor: context.frame, container: safeBounds) {
                        SelectionToolbar(
                            onSelectColor: { model.createHighlightFromSelection(with: $0) },
                            onNote: { model.beginNoteFromSelection() },
                            onAsk: { model.askAgentFromSelection() },
                            onCopy: { model.copySelection() }
                        )
                    }
                case .conflict(let conflict):
                    AnchoredMenu(anchor: conflict.anchor, container: safeBounds) {
                        AnnotationConflictMenu(
                            onNote: { model.chooseNoteFromConflict(conflict) },
                            onHighlight: { model.chooseHighlightFromConflict(conflict) }
                        )
                    }
                case .highlight(let id, let anchor):
                    AnchoredMenu(anchor: anchor, container: safeBounds) {
                        HighlightMenu(
                            model: model,
                            highlightID: id,
                            onSelectColor: { model.changeHighlightColor(id, to: $0) },
                            onNote: { model.openNote(forHighlightID: id) },
                            onDelete: { model.deleteHighlightWithUndo(id) }
                        )
                    }
                case nil:
                    EmptyView()
                }

                if let notice = model.transientNotice {
                    TransientNoticePill(notice: notice, onUndo: { model.undoNotice() })
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, insets.bottom + 14 + noticeBottomInset)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(width: fullSize.width, height: fullSize.height)
            .position(x: fullSize.width / 2, y: fullSize.height / 2)
            .animation(ElsepageTheme.Motion.quick, value: model.annotationMenu)
            .animation(ElsepageTheme.Motion.quick, value: model.transientNotice)
        }
        .ignoresSafeArea()
    }
}

/// Measures the menu it hosts, then places it near the anchor in full-screen
/// coordinates (which match the navigator space the anchors come from).
private struct AnchoredMenu<Menu: View>: View {
    let anchor: CGRect?
    let container: CGRect
    @ViewBuilder let menu: Menu
    @State private var size = CGSize.zero

    var body: some View {
        let effectiveSize = size == .zero ? ReaderAnnotationOverlays.menuSizeEstimate : size
        let origin = AnnotationMenuPlacer.origin(
            anchor: anchor,
            menuSize: effectiveSize,
            container: container,
            margin: 0,
            gap: ReaderAnnotationOverlays.gap
        )
        menu
            .fixedSize()
            .background(
                GeometryReader { measured in
                    Color.clear
                        .onAppear { size = measured.size }
                        .onChange(of: measured.size) { _, newSize in size = newSize }
                }
            )
            .position(
                x: origin.x + effectiveSize.width / 2,
                y: origin.y + effectiveSize.height / 2
            )
    }
}

// MARK: - Selection toolbar

/// Replaces the system text-selection menu. The color dots create a highlight
/// in one tap; a long-press selection never needs a second step before the
/// highlight exists.
///
/// One row instead of two: the old stacked bar was ~104pt tall and covered the
/// paragraph the reader had just selected. Icon + label keeps every action
/// readable at ~52pt while fitting the four swatches and three tools.
struct SelectionToolbar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let onSelectColor: (HighlightColor) -> Void
    let onNote: () -> Void
    let onAsk: () -> Void
    let onCopy: () -> Void

    /// At accessibility sizes the three labelled tools no longer fit beside
    /// four swatches on a phone. Drop the visible labels; the accessibility
    /// labels stay unchanged.
    private var showsToolLabels: Bool {
        !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        HStack(spacing: ElsepageSpacing.xxs) {
            ForEach(HighlightColor.allCases, id: \.self) { color in
                Button {
                    onSelectColor(color)
                } label: {
                    Circle()
                        .fill(color.annotationColor)
                        .frame(width: 26, height: 26)
                        .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 1))
                        // A11Y-03: the swatch rides in a 44pt hit target.
                        .frame(width: ElsepageSpacing.touchTarget, height: ElsepageSpacing.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.accessibilityName)
                .accessibilityHint("创建这个颜色的高亮")
            }

            Divider()
                .frame(height: 24)
                .padding(.horizontal, ElsepageSpacing.xxs)

            toolButton("笔记", systemImage: "note.text", label: "添加笔记", action: onNote)
            toolButton("问 AI", systemImage: "sparkles", label: "就这段问 AI", action: onAsk)
            toolButton("复制", systemImage: "doc.on.doc", label: "复制", action: onCopy)
        }
        .foregroundStyle(ElsepageColor.textPrimary)
        .padding(.horizontal, ElsepageSpacing.sm)
        .padding(.vertical, ElsepageSpacing.xxs)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.14), radius: 16, y: 7)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("标注工具")
    }

    private func toolButton(
        _ title: String,
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                if showsToolLabels {
                    Text(title)
                        .font(ElsepageFont.caption2)
                }
            }
            .frame(minWidth: 48, minHeight: ElsepageSpacing.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// While the selection toolbar is open, a tap anywhere on the content closes
/// it. The zones occupied by the system selection handles are punched out so
/// the selection can still be adjusted; adjusting re-fires the selection
/// callback and re-anchors the toolbar.
private struct SelectionCatcher: View {
    let selectionFrame: CGRect?
    let fullSize: CGSize
    let insets: EdgeInsets
    let onDismiss: () -> Void

    private var holes: [CGRect] {
        guard let selectionFrame else { return [] }
        let container = CGRect(origin: .zero, size: fullSize)
        return AnnotationMenuPlacer.selectionHandleZones(around: selectionFrame, container: container)
    }

    var body: some View {
        let holes = holes
        let shape = SelectionCatcherShape(bounds: fullSize, holes: holes)
        shape
            .fill(.clear)
            .contentShape(shape, eoFill: true)
            .onTapGesture { onDismiss() }
            .accessibilityHidden(true)
    }
}

private struct SelectionCatcherShape: Shape {
    let bounds: CGSize
    let holes: [CGRect]

    var fillStyle: FillStyle { FillStyle(eoFill: true) }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(CGRect(origin: .zero, size: bounds))
        for hole in holes {
            path.addRect(hole)
        }
        return path
    }
}

// MARK: - Annotation conflict

/// Shown only when a standalone Note and a Highlight overlap at the tapped
/// location. Choosing an option resolves the ambiguity explicitly.
struct AnnotationConflictMenu: View {
    let onNote: () -> Void
    let onHighlight: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            toolButton("笔记", systemImage: "note.text", action: onNote)
            Divider().frame(height: 24)
            toolButton("高亮", systemImage: "highlighter", action: onHighlight)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.14), radius: 16, y: 7)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("重叠标注选择")
    }

    private func toolButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ElsepageColor.textPrimary)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开\(title)")
    }
}

// MARK: - Highlight menu

/// Single-row menu anchored to a tapped highlight: recolor, note, delete.
struct HighlightMenu: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let model: ReaderModel
    let highlightID: UUID
    let onSelectColor: (HighlightColor) -> Void
    let onNote: () -> Void
    let onDelete: () -> Void

    private var highlight: Highlight? {
        model.highlights.first { $0.id == highlightID }
    }

    var body: some View {
        if let highlight {
            HStack(spacing: 6) {
                ForEach(HighlightColor.allCases, id: \.self) { color in
                    Button {
                        onSelectColor(color)
                    } label: {
                        Circle()
                            .fill(color.annotationColor)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 1))
                            .overlay {
                                if highlight.color == color {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.black.opacity(0.65))
                                }
                            }
                            // A11Y-03: the 28pt swatch rides in a 44pt hit target.
                            .frame(width: AccessibilityMetrics.minimumTapTargetSide, height: AccessibilityMetrics.minimumTapTargetSide)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.accessibilityName)
                    .accessibilityAddTraits(highlight.color == color ? .isSelected : [])
                }

                Divider()
                    .frame(height: 26)

                toolButton("笔记", systemImage: "note.text", action: onNote)
                toolButton("删除", systemImage: "trash", destructive: true, action: onDelete)
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.14), radius: 16, y: 7)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("高亮菜单")
        }
    }

    private func toolButton(
        _ title: String,
        systemImage: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .foregroundStyle(destructive ? AnyShapeStyle(Color.elsepageDanger) : AnyShapeStyle(ElsepageColor.textPrimary))
            .padding(.horizontal, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .buttonStyle(.plain)
        .accessibilityHint(title == "删除" ? "删除这个高亮，可在短时间内撤销" : "")
    }
}

// MARK: - Transient notice

/// Bottom pill for instant, non-blocking feedback: "已复制", or a deletion
/// with one-tap undo. Auto-dismisses after a few seconds.
struct TransientNoticePill: View {
    let notice: ReaderTransientNotice
    let onUndo: () -> Void

    private var label: String {
        switch notice.kind {
        case .copied: "已复制"
        case .highlightOverlap: "这里和已有高亮部分重叠，先保留原来的高亮吧"
        case .deletedHighlight: "已删除高亮"
        case .deletedNote: "已删除笔记"
        case .returnedToSource: "已回到原文"
        }
    }

    private var canUndo: Bool {
        switch notice.kind {
        case .copied, .returnedToSource, .highlightOverlap: false
        case .deletedHighlight, .deletedNote: true
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(ElsepageColor.textPrimary)
            if canUndo {
                Button("撤销", action: onUndo)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.elsepageInteractive)
            }
        }
        .padding(.horizontal, ElsepageTheme.Spacing.medium)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.14), radius: 16, y: 7)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(label)，\(canUndo ? "可以撤销" : "通知")")
        // A11Y-02: the pill is transient, so VoiceOver users get the same
        // feedback as a spoken announcement.
        .onAppear {
            UIAccessibility.post(notification: .announcement, argument: "\(label)，\(canUndo ? "可以撤销" : "通知")")
        }
    }
}

// MARK: - Note editor

/// A focused writing surface for one highlight's note: excerpt on top, editor
/// below, live-saving as the user types. No save/cancel buttons — the note
/// always reflects what is in the editor, so user words are never lost
/// (PRD P2). An emptied note is removed, with undo offered by the reader.
struct NoteEditorSheet: View {
    private enum Mode {
        case preview
        case edit
    }

    @Environment(\.dismiss) private var dismiss
    let model: ReaderModel
    let target: ReaderNoteEditorTarget

    @FocusState private var editorFocused: Bool
    @State private var mode: Mode = .preview
    @State private var activeTarget: ReaderNoteEditorTarget?
    @State private var text = ""
    @State private var loadedTarget: ReaderNoteEditorTarget?
    @State private var saveTask: Task<Void, Never>?
    @State private var finished = false

    private var effectiveTarget: ReaderNoteEditorTarget {
        activeTarget ?? target
    }

    private var highlight: Highlight? {
        guard case .highlight(let id) = effectiveTarget else { return nil }
        return model.highlights.first { $0.id == id }
    }

    private var note: Note? {
        switch effectiveTarget {
        case .highlight: nil
        case .note(let id): model.notes.first { $0.id == id }
        }
    }

    private var excerpt: String? {
        highlight?.locator.textHighlight ?? note?.locator.textHighlight
    }

    private var relatedNotes: [Note] {
        guard let note else { return [] }
        return model.notes
            .filter { $0.locator.canonicalKey == note.locator.canonicalKey }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var currentNoteIndex: Int? {
        guard let note else { return nil }
        return relatedNotes.firstIndex { $0.id == note.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
            HStack {
                Text("笔记")
                    .font(.system(.headline, design: .serif))
                Spacer()
                if case .note = effectiveTarget {
                    if relatedNotes.count > 1, let index = currentNoteIndex {
                        Menu("第 \(index + 1) 条") {
                            ForEach(Array(relatedNotes.enumerated()), id: \.element.id) { offset, item in
                                Button("笔记 \(offset + 1)") {
                                    activeTarget = .note(item.id)
                                    text = item.body
                                    mode = .preview
                                }
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                    }

                    Button("追加") {
                        guard let id = note?.id, let appendedID = model.appendNoteEntry(after: id) else { return }
                        activeTarget = .note(appendedID)
                        text = ""
                        mode = .edit
                        editorFocused = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .disabled(note == nil)
                }

                if !trimmedText.isEmpty {
                    Button(mode == .preview ? "编辑" : "预览") {
                        mode = mode == .preview ? .edit : .preview
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .accessibilityLabel(mode == .preview ? "编辑笔记" : "预览笔记")
                }

                Button("完成") { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }

            if let excerpt {
                ScrollView {
                    Text(excerpt)
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 92)
            }

            if mode == .preview {
                ScrollView {
                    if trimmedText.isEmpty {
                        ContentUnavailableView("还没有笔记", systemImage: "note.text")
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        AgentMarkdownText(content: previewText, textStyle: .body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityLabel("笔记预览")
            } else {
                TextEditor(text: $text)
                    .focused($editorFocused)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: ElsepageRadius.card, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if trimmedText.isEmpty {
                            Text("写下你的想法…")
                                .font(ElsepageFont.body)
                                .foregroundStyle(ElsepageColor.textTertiary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel("笔记内容")
            }
        }
        .padding(ElsepageTheme.Spacing.medium)
        .presentationDetents([.height(340), .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            guard loadedTarget != target else { return }
            loadedTarget = target
            activeTarget = target
            text = note?.body ?? ""
            // A fresh note should be a writing surface immediately; the old
            // preview-first default forced an extra tap before typing. Existing
            // notes still open read-first so they can be reviewed without the
            // keyboard covering the excerpt.
            let hasBody = !(note?.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            mode = hasBody ? .preview : .edit
            editorFocused = false
            if !hasBody {
                Task { @MainActor in editorFocused = true }
            }
        }
        .onChange(of: mode) { _, mode in
            editorFocused = mode == .edit
        }
        .onChange(of: text) { _, _ in
            scheduleSave()
        }
        .onDisappear {
            finalize()
        }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var previewText: String {
        trimmedText
            .replacingOccurrences(
                of: #"\[E[0-9]+\]"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: "  ", with: " ")
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            persist()
        }
    }

    /// Live-save: creates the note on first content, keeps it in sync after.
    private func persist() {
        let trimmed = trimmedText
        switch effectiveTarget {
        case .highlight:
            break
        case .note(let noteID):
            if let note = model.notes.first(where: { $0.id == noteID }), note.body != trimmed {
                model.update(note: note, body: trimmed)
            }
        }
    }

    /// Runs on every dismissal path (完成 button and interactive swipe).
    /// Non-empty text is flushed to the store; an emptied existing note is
    /// deleted with an undo pill rather than silently lost.
    private func finalize() {
        guard !finished else { return }
        finished = true
        saveTask?.cancel()
        editorFocused = false
        if trimmedText.isEmpty {
            if let note {
                let doomed = note
                Task {
                    // Let any in-flight note writes land before deleting, so a
                    // pending empty-body save cannot resurrect the note row.
                    await model.flushNoteSaves()
                    model.deleteNoteWithUndo(doomed)
                }
            }
        } else {
            persist()
            Task { await model.flushNoteSaves() }
        }
    }
}

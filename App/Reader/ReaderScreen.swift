import ReaderCore
import SwiftUI

struct ReaderScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State var model: ReaderModel
    @State private var presentedSheet: ReaderSheet?
    @State private var reflectionPrompt: SessionReflectionModel?
    @State private var dismissAfterReflection = false
    let onReflectionSaved: () -> Void

    init(
        model: ReaderModel,
        achievements: AchievementModel? = nil,
        onReflectionSaved: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: model)
        model.achievements = achievements
        self.onReflectionSaved = onReflectionSaved
    }

    var body: some View {
        ZStack {
            themeBackground.ignoresSafeArea()

            if model.isPrepared {
                ReadiumReaderView(
                    model: model,
                    preferences: model.preferences,
                    highlights: model.highlights,
                    jumpTargetJSON: model.jumpTargetJSON,
                    colorScheme: colorScheme
                )
                    .ignoresSafeArea()
            } else {
                ProgressView("正在打开…").controlSize(.large)
            }

            if model.isPrepared, model.showsControls {
                readerChrome.transition(.opacity)
            }

        }
        .animation(ElsepageTheme.Motion.quick, value: model.showsControls)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(model.isPrepared && !model.showsControls)
        .task { await model.prepare() }
        .onChange(of: model.selectedHighlightID) { _, id in
            guard let id else { return }
            presentedSheet = .annotationDetail(.highlight(id, startNoteEditing: model.shouldStartNoteEditing))
        }
        .sheet(item: $presentedSheet, onDismiss: {
            model.clearSelectedHighlight()
        }) { sheet in
            switch sheet {
            case .contents: ContentsSheet(model: model)
            case .search: ReaderSearchSheet(model: model)
            case .annotations:
                ReaderAnnotationsSheet(model: model) { highlight in
                    model.jump(to: highlight.locator)
                    if let highlight = highlight.highlight {
                        model.selectHighlight(highlight.id)
                    } else if let note = highlight.note {
                        presentedSheet = .annotationDetail(.note(note.id))
                    }
                }
            case .appearance: ReaderAppearanceSheet(model: model)
            case .annotationDetail(let target):
                ReaderAnnotationDetailSheet(model: model, target: target)
            }
        }
        .sheet(item: $model.contextReflection) { reflection in
            SessionReflectionSheet(model: reflection, onSaved: { _ in }) { evidence in
                if let locator = evidence.locator { model.jump(to: locator) }
            }
        }
        .sheet(item: $reflectionPrompt, onDismiss: {
            if dismissAfterReflection { dismiss() }
        }) { reflection in
            SessionReflectionSheet(model: reflection, onSaved: { _ in onReflectionSaved() }) { evidence in
                if let locator = evidence.locator { model.jump(to: locator) }
            }
        }
        .alert("无法完成操作", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            model.savePreferences()
            Task {
                await model.flushPosition()
                await model.flushPreferences()
            }
        }
        .onDisappear {
            model.savePreferences()
            Task {
                await model.flushPosition()
                await model.flushPreferences()
            }
        }
    }

    private var readerChrome: some View {
        VStack(spacing: ElsepageTheme.Spacing.small) {
            HStack(spacing: ElsepageTheme.Spacing.medium) {
                ElsepageIconButton(systemName: "chevron.left", accessibilityLabel: "读到这里并返回") {
                    finishReading()
                }
                if model.canNavigateBack {
                    ElsepageIconButton(systemName: "arrow.uturn.backward", accessibilityLabel: "返回跳转前位置") {
                        model.navigateBack()
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.book.title)
                        .font(.system(.subheadline, design: .serif, weight: .semibold))
                        .lineLimit(1)
                    if let chapter = model.currentChapterTitle {
                        Text(chapter).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                ElsepageIconButton(systemName: "magnifyingglass", accessibilityLabel: "搜索正文") { presentedSheet = .search }
                ElsepageIconButton(systemName: "textformat", accessibilityLabel: "阅读设置") { presentedSheet = .appearance }
            }
            .padding(.horizontal, ElsepageTheme.Spacing.medium)
            .padding(.vertical, ElsepageTheme.Spacing.small)
            .background(ElsepageTheme.MaterialToken.chrome)

            Spacer()

            HStack(spacing: ElsepageTheme.Spacing.large) {
                Button { presentedSheet = .contents } label: {
                    Label("目录", systemImage: "list.bullet.indent").labelStyle(.iconOnly)
                }
                Button { presentedSheet = .annotations } label: {
                    Label("标注", systemImage: "highlighter").labelStyle(.iconOnly)
                }
                Button { finishReading() } label: {
                    Label("读到这里", systemImage: "bookmark")
                }
                ProgressView(value: model.progress)
                    .tint(.elsepageAccent)
                    .accessibilityLabel("阅读进度")
                    .accessibilityValue(Text(model.progress, format: .percent.precision(.fractionLength(0))))
                Text(model.progress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .font(.body)
            .buttonStyle(.plain)
            .padding(.horizontal, ElsepageTheme.Spacing.large)
            .padding(.vertical, ElsepageTheme.Spacing.medium)
            .background(ElsepageTheme.MaterialToken.chrome)
        }
        .foregroundStyle(.primary)
    }

    private func finishReading() {
        Task {
            guard let summary = await model.endReadingSession(),
                  let locator = summary.session.endLocator else {
                dismiss()
                return
            }
            guard summary.shouldOfferReflection else {
                dismiss()
                return
            }
            dismissAfterReflection = true
            reflectionPrompt = SessionReflectionModel(
                book: model.book,
                summary: summary,
                locator: locator,
                linkedHighlightIDs: model.highlights(in: summary.session).map(\.id),
                reflectionRepository: model.reflectionRepository,
                readerAgent: model.readerAgent,
                makePolishService: model.makePolishService,
                achievements: model.achievements
            )
        }
    }

    private var themeBackground: Color {
        switch model.preferences.theme {
        case .system: colorScheme == .dark ? Color(uiColor: .black) : .elsepageBackground
        case .light: Color(uiColor: .systemBackground)
        case .dark: Color(uiColor: .black)
        case .sepia: .elsepageReaderSepia
        }
    }
}

private enum ReaderSheet: Identifiable {
    case contents, search, annotations, appearance
    case annotationDetail(ReaderAnnotationTarget)

    var id: String {
        switch self {
        case .contents: "contents"
        case .search: "search"
        case .annotations: "annotations"
        case .appearance: "appearance"
        case .annotationDetail(let target): "annotation-detail-\(target.id.uuidString)"
        }
    }
}

private struct ContentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: ReaderModel

    var body: some View {
        NavigationStack {
            Group {
                if model.chapters.isEmpty {
                    ContentUnavailableView("没有目录", systemImage: "list.bullet.indent", description: Text("这本 EPUB 没有提供章节目录。"))
                } else {
                    List(model.chapters) { chapter in
                        Button {
                            model.jump(to: chapter)
                            dismiss()
                        } label: {
                            HStack {
                                Text(chapter.title)
                                Spacer()
                                if chapter.id == model.currentChapterID {
                                    Image(systemName: "checkmark").foregroundStyle(Color.elsepageAccent)
                                }
                            }
                            .foregroundStyle(chapter.id == model.currentChapterID ? Color.elsepageAccent : .primary)
                            .padding(.leading, CGFloat(chapter.depth) * 16)
                        }
                        .accessibilityHint("跳转到这一章")
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ReaderSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: ReaderModel
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                if model.isSearching { ProgressView("正在搜索…") }
                else if model.searchResults.isEmpty {
                    ContentUnavailableView(
                        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "搜索正文" : "没有找到结果",
                        systemImage: "magnifyingglass",
                        description: Text(query.isEmpty ? "输入关键词查找书中内容。" : "试试更短或不同的关键词。")
                    )
                } else {
                    List(model.searchResults) { result in
                        Button {
                            model.jump(to: result.locator); dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(result.excerpt).foregroundStyle(.primary).lineLimit(3)
                                if let context = result.locator.textBefore {
                                    Text(context).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }.listStyle(.plain)
                }
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索本书")
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await model.search(query)
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ReaderAnnotationsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: ReaderModel
    let onSelect: (ReaderAnnotation) -> Void

    private var annotations: [ReaderAnnotation] {
        let highlighted = model.highlights.map { highlight in
            ReaderAnnotation(highlight: highlight, note: model.notes.first { $0.highlightID == highlight.id })
        }
        let independentNotes = model.notes
            .filter { $0.highlightID == nil }
            .map { ReaderAnnotation(highlight: nil, note: $0) }
        return (highlighted + independentNotes)
            .sorted { lhs, rhs in
                if let left = model.annotationSortKey(for: lhs.locator),
                   let right = model.annotationSortKey(for: rhs.locator),
                   left != right {
                    return left < right
                }
                let leftDate = lhs.highlight?.createdAt ?? lhs.note!.createdAt
                let rightDate = rhs.highlight?.createdAt ?? rhs.note!.createdAt
                return leftDate < rightDate
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.highlights.isEmpty && model.notes.isEmpty {
                    ContentUnavailableView("还没有标注", systemImage: "highlighter", description: Text("选中文字即可添加高亮或批注。"))
                } else {
                    List(annotations) { annotation in
                        Button { onSelect(annotation) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                if let highlight = annotation.highlight {
                                    Circle()
                                        .fill(highlight.color.readerColor)
                                        .frame(width: 10, height: 10)
                                        .padding(.top, 5)
                                } else {
                                    Image(systemName: "note.text")
                                        .font(.caption)
                                        .foregroundStyle(Color.elsepageAccent)
                                        .frame(width: 10)
                                        .padding(.top, 5)
                                }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(annotation.locator.textHighlight ?? "原文位置")
                                        .foregroundStyle(.primary)
                                        .lineLimit(3)
                                    if let note = annotation.note {
                                        Text(note.body)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    Text(model.annotationLocationLabel(for: annotation.locator))
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("标注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ReaderAnnotation: Identifiable {
    let highlight: Highlight?
    let note: Note?
    var id: UUID { highlight?.id ?? note!.id }
    var locator: BookLocator { highlight?.locator ?? note!.locator }
}

private struct ReaderAnnotationTarget: Hashable {
    let id: UUID
    let highlightID: UUID?
    let noteID: UUID?
    let startNoteEditing: Bool

    static func highlight(_ id: UUID, startNoteEditing: Bool = false) -> Self {
        Self(id: id, highlightID: id, noteID: nil, startNoteEditing: startNoteEditing)
    }

    static func note(_ id: UUID) -> Self {
        Self(id: id, highlightID: nil, noteID: id, startNoteEditing: false)
    }
}

private struct AnnotationSortKey: Comparable {
    let chapterIndex: Int
    let progression: Double

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.chapterIndex != rhs.chapterIndex { return lhs.chapterIndex < rhs.chapterIndex }
        return lhs.progression < rhs.progression
    }
}

private extension ReaderModel {
    func annotationSortKey(for locator: BookLocator) -> AnnotationSortKey? {
        let resource = locator.href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? locator.href
        guard let chapterIndex = chapters.firstIndex(where: { chapter in
            let chapterResource = chapter.href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? chapter.href
            return chapterResource == resource
        }) else { return nil }
        return AnnotationSortKey(chapterIndex: chapterIndex, progression: locator.progression ?? 0)
    }

    func annotationLocationLabel(for locator: BookLocator) -> String {
        let chapter = chapters.first { chapter in
            let chapterResource = chapter.href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? chapter.href
            let resource = locator.href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? locator.href
            return chapterResource == resource
        }?.title
        let progress = locator.totalProgression ?? locator.progression
        if let chapter, let progress {
            return "\(chapter) · \(Int((progress * 100).rounded()))%"
        }
        return chapter ?? "原文位置"
    }
}

private struct ReaderAnnotationDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: ReaderModel
    let target: ReaderAnnotationTarget
    @State private var isEditingNote = false
    @State private var noteText = ""

    private var highlight: Highlight? {
        guard let highlightID = target.highlightID else { return nil }
        return model.highlights.first { $0.id == highlightID }
    }

    private var note: Note? {
        if let highlightID = target.highlightID {
            return model.notes.first { $0.highlightID == highlightID }
        }
        guard let noteID = target.noteID else { return nil }
        return model.notes.first { $0.id == noteID }
    }

    private var locator: BookLocator? {
        highlight?.locator ?? note?.locator
    }

    var body: some View {
        NavigationStack {
            Group {
                if let highlight {
                    ScrollView {
                        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.medium) {
                            Text(highlight.locator.textHighlight ?? "高亮位置")
                                .font(.system(.body, design: .serif))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(model.annotationLocationLabel(for: highlight.locator))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Divider()

                            VStack(alignment: .leading, spacing: 10) {
                                Text("高亮颜色")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 14) {
                                    ForEach(HighlightColor.allCases, id: \.self) { color in
                                        Button {
                                            model.update(highlight: highlight, color: color)
                                        } label: {
                                            Circle()
                                                .fill(color.readerColor)
                                                .frame(width: 30, height: 30)
                                                .overlay(Circle().stroke(.primary.opacity(0.18)))
                                                .overlay {
                                                    if highlight.color == color {
                                                        Image(systemName: "checkmark")
                                                            .font(.caption.bold())
                                                            .foregroundStyle(.black.opacity(0.7))
                                                    }
                                                }
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("\(color.readerName)高亮")
                                        .accessibilityAddTraits(highlight.color == color ? .isSelected : [])
                                    }
                                }
                            }

                            Divider()

                            noteEditor(note: note, highlight: highlight)

                            Divider()

                            Button(role: .destructive) {
                                model.delete(highlight: highlight)
                                dismiss()
                            } label: {
                                Label("删除高亮", systemImage: "trash")
                            }
                        }
                        .padding(.horizontal, ElsepageTheme.Spacing.large)
                        .padding(.vertical, ElsepageTheme.Spacing.medium)
                    }
                } else if let locator, let note {
                    ScrollView {
                        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.medium) {
                            Text(locator.textHighlight ?? "原文位置")
                                .font(.system(.body, design: .serif))
                            Text(model.annotationLocationLabel(for: locator))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Divider()
                            noteEditor(note: note, highlight: nil)
                        }
                        .padding(.horizontal, ElsepageTheme.Spacing.large)
                        .padding(.vertical, ElsepageTheme.Spacing.medium)
                    }
                } else {
                    ContentUnavailableView("标注已不存在", systemImage: "highlighter")
                }
            }
            .navigationTitle("这段标注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents(isEditingNote ? [.medium, .large] : [.height(250), .medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            noteText = note?.body ?? ""
            isEditingNote = target.startNoteEditing
        }
    }

    @ViewBuilder
    private func noteEditor(note: Note?, highlight: Highlight?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("我的笔记")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !isEditingNote {
                    Button(note == nil ? "添加" : "编辑") {
                        noteText = note?.body ?? ""
                        isEditingNote = true
                    }
                    .font(.subheadline.weight(.medium))
                }
            }

            if isEditingNote {
                TextEditor(text: $noteText)
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel("笔记内容")
                HStack {
                    Button("取消") { isEditingNote = false }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("保存") { saveNote(note: note, highlight: highlight) }
                        .buttonStyle(.borderedProminent)
                        .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else if let note {
                Text(note.body)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("这段文字还没有笔记。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func saveNote(note: Note?, highlight: Highlight?) {
        let text = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let note {
            model.update(note: note, body: text)
        } else if let highlight {
            model.saveNote(for: highlight, body: text)
        } else {
            return
        }
        isEditingNote = false
    }
}

private extension HighlightColor {
    var readerColor: Color {
        switch self {
        case .yellow: Color(red: 0.96, green: 0.78, blue: 0.24)
        case .green: Color(red: 0.36, green: 0.72, blue: 0.43)
        case .blue: Color(red: 0.32, green: 0.56, blue: 0.90)
        case .pink: Color(red: 0.90, green: 0.42, blue: 0.61)
        }
    }

    var readerName: String {
        switch self {
        case .yellow: "黄色"
        case .green: "绿色"
        case .blue: "蓝色"
        case .pink: "粉色"
        }
    }
}

private struct ReaderAppearanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: ReaderModel

    var body: some View {
        NavigationStack {
            Form {
                Section("主题") {
                    HStack(spacing: 12) {
                        themeButton(.system, "自动", .gray)
                        themeButton(.light, "明亮", .white)
                        themeButton(.sepia, "柔和", Color(red: 0.91, green: 0.83, blue: 0.66))
                        themeButton(.dark, "深色", .black)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .contain)
                }
                Section("排版") {
                    settingSlider("字号", value: $model.preferences.fontSize, range: 0.8 ... 1.6)
                    settingSlider("行高", value: $model.preferences.lineHeight, range: 0.8 ... 2.0)
                    settingSlider("页边距", value: $model.preferences.pageMargins, range: 0.5 ... 2.0)
                }
                Section("阅读方式") {
                    Picker("阅读方式", selection: $model.preferences.readingMode) {
                        Text("分页").tag(ReadingMode.paginated)
                        Text("滚动").tag(ReadingMode.scroll)
                    }
                    .pickerStyle(.segmented)
                    Text("章节内上下滚动，章节之间左右滑动。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .onDisappear { model.savePreferences() }
    }

    private func themeButton(_ theme: ReaderTheme, _ title: String, _ color: Color) -> some View {
        Button { model.preferences.theme = theme } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 38, height: 38)
                    .overlay(Circle().stroke(.secondary.opacity(0.35)))
                    .overlay {
                        if model.preferences.theme == theme {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(theme == .dark ? .white : .black)
                        }
                    }
                Text(title).font(.caption2).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)主题")
        .accessibilityAddTraits(model.preferences.theme == theme ? .isSelected : [])
    }

    private func settingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).frame(width: 52, alignment: .leading)
            Slider(value: value, in: range)
                .accessibilityLabel(title)
        }
    }
}

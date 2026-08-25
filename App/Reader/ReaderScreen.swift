import ReaderCore
import SwiftUI

struct ReaderScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State var model: ReaderModel
    @State private var presentedSheet: ReaderSheet?

    var body: some View {
        ZStack {
            themeBackground.ignoresSafeArea()

            if model.isPrepared {
                ReadiumReaderView(model: model, colorScheme: colorScheme)
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
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .contents: ContentsSheet(model: model)
            case .search: ReaderSearchSheet(model: model)
            case .annotations: ReaderAnnotationsSheet(model: model)
            case .appearance: ReaderAppearanceSheet(model: model)
            }
        }
        .sheet(item: $model.noteEditor) { request in
            ReaderNoteEditorSheet(model: model, request: request)
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
                ElsepageIconButton(systemName: "chevron.left", accessibilityLabel: "返回书架") { dismiss() }
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

    private var themeBackground: Color {
        switch model.preferences.theme {
        case .system: colorScheme == .dark ? Color(uiColor: .black) : .elsepageBackground
        case .light: Color(uiColor: .systemBackground)
        case .dark: Color(uiColor: .black)
        case .sepia: .elsepageReaderSepia
        }
    }
}

private enum ReaderSheet: String, Identifiable {
    case contents, search, annotations, appearance
    var id: String { rawValue }
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

    var body: some View {
        NavigationStack {
            Group {
                if model.highlights.isEmpty && model.notes.isEmpty {
                    ContentUnavailableView("还没有标注", systemImage: "highlighter", description: Text("选中文字即可添加高亮或批注。"))
                } else {
                    List {
                        if !model.notes.isEmpty {
                            Section("批注") {
                                ForEach(model.notes) { note in
                                    annotationButton(note.body, context: note.locator.textHighlight, locator: note.locator)
                                }
                            }
                        }
                        let standaloneHighlights = model.highlights.filter { highlight in
                            !model.notes.contains { $0.highlightID == highlight.id }
                        }
                        if !standaloneHighlights.isEmpty {
                            Section("高亮") {
                                ForEach(standaloneHighlights) { highlight in
                                    annotationButton(highlight.locator.textHighlight ?? "高亮位置", context: highlight.locator.textBefore, locator: highlight.locator)
                                }
                            }
                        }
                    }.listStyle(.insetGrouped)
                }
            }
            .navigationTitle("标注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func annotationButton(_ title: String, context: String?, locator: BookLocator) -> some View {
        Button {
            model.jump(to: locator); dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).foregroundStyle(.primary).lineLimit(3)
                if let context { Text(context).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
    }
}

private struct ReaderNoteEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: ReaderModel
    let request: ReaderNoteEditorRequest
    @State private var noteText: String

    init(model: ReaderModel, request: ReaderNoteEditorRequest) {
        self.model = model
        self.request = request
        _noteText = State(initialValue: request.note?.body ?? "")
    }

    var bodyView: some View {
        NavigationStack {
            Form {
                if let quote = request.locator.textHighlight, !quote.isEmpty {
                    Section("原文") {
                        Text(quote)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Section("笔记") {
                    TextEditor(text: $noteText)
                        .frame(minHeight: 160)
                        .accessibilityLabel("笔记内容")
                }
            }
            .navigationTitle(request.note == nil ? "添加笔记" : "编辑笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let text = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let note = request.note {
                            model.update(note: note, body: text)
                        } else if let highlight = request.highlight {
                            model.saveNote(for: highlight, body: text)
                        } else {
                            model.saveNote(locator: request.locator, body: text)
                        }
                        dismiss()
                    }
                    .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(!noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View { bodyView }
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
                    Text("滚动模式使用上下滑动阅读。")
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

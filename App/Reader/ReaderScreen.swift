import Foundation
import ReaderCore
import ReflectionCore
import SwiftUI
import UIKit

struct ReaderScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var model: ReaderModel
    @State private var presentedSheet: ReaderSheet?
    @State private var reflectionPrompt: SessionReflectionModel?
    @State private var dismissAfterReflection = false
    let openingCover: UIImage?
    let onOpenSettings: (() -> Void)?
    let onReflectionSaved: () -> Void

    init(
        model: ReaderModel,
        achievements: AchievementModel? = nil,
        openingCover: UIImage? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onReflectionSaved: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: model)
        model.achievements = achievements
        self.openingCover = openingCover
        self.onOpenSettings = onOpenSettings
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
                    notes: model.notes,
                    jumpTargetJSON: model.jumpTargetJSON,
                    colorScheme: colorScheme
                )
                .ignoresSafeArea()
                .transition(reduceMotion ? .identity : .opacity)
            } else {
                readerOpeningPlaceholder
                    .transition(reduceMotion ? .identity : .opacity)
            }

            if model.isPrepared, model.showsControls {
                readerChrome
                    .environment(\.colorScheme, readerColorScheme)
                    .transition(.opacity)
            }

            if model.isPrepared {
                ReaderAnnotationOverlays(
                    model: model,
                    noticeBottomInset: model.helpPresentation == nil ? 0 : 184
                )
                // Menus and notices float over the page, so they must follow the
                // reading theme rather than the system. With a dark page in a
                // light system the chrome text used to resolve to near-black.
                .environment(\.colorScheme, readerColorScheme)
            }
        }
        .animation(ElsepageTheme.Motion.quick, value: model.showsControls)
        .animation(ElsepageTheme.Motion.moment(reduceMotion), value: model.isPrepared)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(model.isPrepared && !model.showsControls)
        .task {
            model.perfOpenBeganAt = CFAbsoluteTimeGetCurrent()
            model.perfOpenInterval = Perf.shared.begin(.readerOpen)
            await model.prepare()
        }
        .sheet(item: $presentedSheet) { sheet in
            readerSheetChrome(
                Group {
                    switch sheet {
                    case .contents: ContentsSheet(model: model)
                    case .search: ReaderSearchSheet(model: model)
                    case .annotations:
                        ReaderAnnotationsSheet(model: model) { annotation in
                            if let highlight = annotation.highlight {
                                // Menu opens in place once the jump arrives.
                                model.jumpToHighlight(highlight.id)
                                presentedSheet = nil
                            } else if let note = annotation.note {
                                model.jump(to: note.locator)
                                presentedSheet = nil
                                model.openNoteEditor(.note(note.id))
                            }
                        }
                    case .appearance: ReaderAppearanceSheet(model: model)
                    }
                }
            )
        }
        .sheet(item: $model.noteEditorRequest, onDismiss: {
            // Reset explicitly so a later request with the same note always
            // re-presents, whatever the automatic dismissal path did.
            model.noteEditorRequest = nil
        }) { request in
            readerSheetChrome(NoteEditorSheet(model: model, target: request.target))
        }
        .sheet(item: $model.helpPresentation) { presentation in
            readerSheetChrome(
                ReaderHelpSheet(
                    model: presentation.model,
                    openCitation: { evidence in jumpToCitation(evidence) },
                    onOpenSettings: onOpenSettings
                )
            )
        }
        .sheet(item: $model.contextReflection) { reflection in
            readerSheetChrome(
                SessionReflectionSheet(model: reflection, onSaved: { _ in }) { evidence in
                    jumpToCitation(evidence)
                }
            )
        }
        .sheet(item: $reflectionPrompt, onDismiss: {
            if dismissAfterReflection { dismiss() }
        }) { reflection in
            readerSheetChrome(
                SessionReflectionSheet(model: reflection, onSaved: { _ in onReflectionSaved() }) { evidence in
                    jumpToCitation(evidence)
                }
            )
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
            // Annotation menu anchors are screen coordinates; drop them while
            // backgrounded so they cannot reappear stale after relaunch.
            model.clearTransientAnnotationUI(reason: "background")
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

    /// Keeps the zoom destination visually related to the book after the
    /// transition finishes. The EPUB remains free to prepare asynchronously;
    /// only this placeholder is replaced once the reader is ready.
    private var readerOpeningPlaceholder: some View {
        VStack(spacing: ElsepageTheme.Spacing.large) {
            ElsepageBookCover(
                image: openingCover,
                title: model.book.title,
                author: model.book.author,
                seed: Int(model.book.id.rawValue.uuid.0),
                width: ElsepageBookCoverMetrics.width
            )

            ProgressView()
                .controlSize(.small)
                .tint(.elsepageInteractive)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在打开《\(model.book.title)》")
    }

    private var readerChrome: some View {
        VStack(spacing: 0) {
            topChrome

            Spacer(minLength: 0)

            // A11Y-01: at accessibility Dynamic Type sizes a single row cannot
            // fit on narrow widths, so the bar wraps into two stacked rows.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: ElsepageSpacing.md) {
                    bottomBarButtons
                    bottomBarProgress
                }
                VStack(alignment: .leading, spacing: ElsepageSpacing.xs) {
                    HStack(spacing: ElsepageSpacing.md) {
                        bottomBarButtons
                    }
                    bottomBarProgress
                }
            }
            .padding(.horizontal, ElsepageSpacing.sm)
            .frame(minHeight: ReaderChromeMetrics.bottomBarHeight)
            .background(themeBackground, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(ElsepageColor.separator.opacity(0.35), lineWidth: ElsepageBorder.hairline)
            }
            .padding(.horizontal, ElsepageSpacing.md)
        }
        .foregroundStyle(ElsepageColor.textPrimary)
        // A short page-colour fade, not a reserved band: the capsule still
        // floats over the text, but a line ending at the capsule edge fades
        // out instead of being sliced in half. Only present with the chrome.
        .background(alignment: .top) { chromeScrim(edge: .top) }
        .background(alignment: .bottom) { chromeScrim(edge: .bottom) }
        // Capping chrome text growth keeps the floating capsules predictable at
        // accessibility sizes. Reading text itself follows the reader's font
        // size, not Dynamic Type.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func chromeScrim(edge: VerticalEdge) -> some View {
        LinearGradient(
            stops: edge == .top
                ? [
                    .init(color: themeBackground, location: 0),
                    .init(color: themeBackground, location: 0.88),
                    .init(color: themeBackground.opacity(0), location: 1),
                ]
                : [
                    .init(color: themeBackground.opacity(0), location: 0),
                    .init(color: themeBackground, location: 0.12),
                    .init(color: themeBackground, location: 1),
                ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: ReaderChromeMetrics.scrimHeight)
        .allowsHitTesting(false)
    }

    /// One floating capsule, like the bottom bar. It deliberately sits over the
    /// page instead of reserving a band above it: the text keeps the full page,
    /// and the transient chrome is the only thing that covers it.
    private var topChrome: some View {
        HStack(spacing: ElsepageSpacing.xs) {
            chromeIcon("xmark", label: "结束阅读并返回书架") { finishReading() }
            if model.canNavigateBack {
                chromeIcon("arrow.uturn.backward", label: "返回跳转前位置") { model.navigateBack() }
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(model.book.title)
                    .font(ElsepageFont.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let chapter = model.currentChapterTitle {
                    Text(chapter)
                        .font(ElsepageFont.caption2)
                        .foregroundStyle(ElsepageColor.textSecondary)
                        .lineLimit(1)
                }
            }
            // A11Y-02: title + current chapter read as one element.
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, ElsepageSpacing.xs)

            chromeIcon("magnifyingglass", label: "搜索正文") { presentedSheet = .search }
            chromeIcon("textformat.size", label: "阅读设置") { presentedSheet = .appearance }
        }
        .padding(.horizontal, ElsepageSpacing.sm)
        .frame(height: ReaderChromeMetrics.topBarHeight)
        .background(themeBackground, in: Capsule())
        .overlay {
            Capsule()
                .stroke(ElsepageColor.separator.opacity(0.35), lineWidth: ElsepageBorder.hairline)
        }
        .padding(.horizontal, ElsepageSpacing.md)
        .padding(.top, ElsepageSpacing.xs)
    }

    private func chromeIcon(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .frame(width: ElsepageSpacing.touchTarget, height: ElsepageSpacing.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var bottomBarButtons: some View {
        HStack(spacing: ElsepageSpacing.xs) {
            barButton("目录", systemName: "list.bullet.indent") { presentedSheet = .contents }
            barButton("标注", systemName: "highlighter") { presentedSheet = .annotations }
        }
    }

    /// Icon + short label. The label is what makes these discoverable at a
    /// glance; the 44pt row keeps the touch target while staying compact.
    private func barButton(_ title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .regular))
                Text(title)
                    .font(ElsepageFont.caption2)
                    .foregroundStyle(ElsepageColor.textSecondary)
            }
            .frame(minWidth: 48, minHeight: ElsepageSpacing.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var bottomBarProgress: some View {
        HStack(spacing: ElsepageSpacing.sm) {
            // The bar is decorative: a 4pt-tall control exposes a hit area far
            // below 44pt, so the percentage text carries the accessibility
            // value instead of duplicating it.
            ProgressView(value: model.progress)
                .tint(ElsepageColor.accent)
                .accessibilityHidden(true)
            Text(model.progress, format: .percent.precision(.fractionLength(0)))
                .font(ElsepageFont.caption2.monospacedDigit())
                .foregroundStyle(ElsepageColor.textSecondary)
                .frame(minWidth: 34, alignment: .trailing)
                .accessibilityLabel("阅读进度")
                .accessibilityValue(Text(model.progress, format: .percent.precision(.fractionLength(0))))
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
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
            let sessionHighlights = model.highlights(in: summary.session)
            reflectionPrompt = SessionReflectionModel(
                book: model.book,
                summary: summary,
                locator: locator,
                linkedHighlightIDs: sessionHighlights.map(\.id),
                // Biases recognition toward the words this reader just
                // highlighted, which is where the vocabulary they will say
                // actually comes from.
                highlightTexts: sessionHighlights.compactMap { $0.locator.textHighlight },
                reflectionRepository: model.reflectionRepository,
                readerAgent: model.readerAgent,
                makePolishService: model.makePolishService,
                achievements: model.achievements,
                recordAgentDiscussion: model.agentDiscussionRecorder
            )
        }
    }

    /// 从 Agent Citation 跳回原文 (PRD §10.3): performs the jump and lands a
    /// chrome-level pill so the arrival is acknowledged without ever animating
    /// the EPUB content itself (P1).
    private func jumpToCitation(_ evidence: AgentResponseEvidence) {
        guard let locator = evidence.locator else { return }
        model.jump(to: locator)
        model.showNotice(.returnedToSource)
    }

    private var themeBackground: Color {
        switch model.preferences.theme {
        case .system: colorScheme == .dark ? Color(uiColor: .black) : .elsepageBackground
        case .light: Color(uiColor: .systemBackground)
        case .dark: Color(uiColor: .black)
        case .sepia: .elsepageReaderSepia
        }
    }

    /// The reading theme owns the page, so it also owns every overlay drawn on
    /// top of it. A dark page in a light system used to give the floating chrome
    /// dark text on a black capsule.
    private var readerColorScheme: ColorScheme {
        switch model.preferences.theme {
        case .system: colorScheme
        case .light, .sepia: .light
        case .dark: .dark
        }
    }

    /// Sheets are a new environment root, so the reader theme has to be pushed
    /// in explicitly. Without this a dark page opened a light sheet (and vice
    /// versa), and the default material let body text show through the form.
    private func readerSheetChrome<Content: View>(_ content: Content) -> some View {
        content
            .environment(\.colorScheme, readerColorScheme)
            .presentationBackground(
                ReaderPageBackground.color(for: model.preferences.theme, colorScheme: colorScheme)
            )
    }
}

/// Shared geometry for the reader chrome.
/// The chrome floats over the page and reserves no content inset: the EPUB uses
/// the full safe area, so showing or hiding the transient capsule never
/// reflows the text and never leaves a permanent blank band.
enum ReaderChromeMetrics {
    static let topBarHeight: CGFloat = 48
    static let bottomBarHeight: CGFloat = 48
    /// Extra space kept free above the content, excluding the window's safe
    /// area. Zero: the capsule is an overlay, not a layout row.
    static let contentTopInset: CGFloat = 0
    /// Extra space kept free below the content, excluding the window's safe
    /// area. Zero: same reason as the top.
    static let contentBottomInset: CGFloat = 0
    /// Height of the page-colour fade under the floating chrome. It softens
    /// the line at the capsule edge without reserving layout space.
    static let scrimHeight: CGFloat = 72
}

private enum ReaderSheet: Identifiable {
    case contents, search, annotations, appearance

    var id: String {
        switch self {
        case .contents: "contents"
        case .search: "search"
        case .annotations: "annotations"
        case .appearance: "appearance"
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
                    ScrollViewReader { proxy in
                        List(model.chapters) { chapter in
                            Button {
                                model.jump(to: chapter)
                                dismiss()
                            } label: {
                                HStack(spacing: ElsepageSpacing.sm) {
                                    Text(chapter.title)
                                        .lineLimit(2)
                                    Spacer(minLength: 0)
                                    if chapter.id == model.currentChapterID {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.semibold))
                                    }
                                }
                                .foregroundStyle(chapter.id == model.currentChapterID ? ElsepageColor.accent : ElsepageColor.textPrimary)
                                .padding(.leading, CGFloat(chapter.depth) * ElsepageSpacing.lg)
                                .frame(minHeight: ElsepageSpacing.controlHeight)
                            }
                            .id(chapter.id)
                            .accessibilityHint("跳转到这一章")
                        }
                        .listStyle(.plain)
                        .onAppear {
                            // Open the table of contents at the chapter being
                            // read, not at the book's first page.
                            guard let current = model.currentChapterID else { return }
                            proxy.scrollTo(current, anchor: .center)
                        }
                    }
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
                                        .fill(highlight.color.annotationColor)
                                        .frame(width: 10, height: 10)
                                        .padding(.top, 5)
                                        .accessibilityHidden(true)
                                } else {
                                    Image(systemName: "note.text")
                                        .font(.caption)
                                        .foregroundStyle(Color.elsepageInteractive)
                                        .frame(width: 10)
                                        .padding(.top, 5)
                                        .accessibilityHidden(true)
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
                            // A11Y-02: excerpt + note + location read as one stop.
                            .accessibilityElement(children: .combine)
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("恢复默认") {
                        model.preferences = .default
                        model.savePreferences()
                    }
                    .font(.subheadline)
                }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
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
            // A11Y-03: the whole cell (≥44pt tall) is the tap target.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)主题")
        .accessibilityAddTraits(model.preferences.theme == theme ? .isSelected : [])
    }

    private func settingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
                // A11Y-01: a fixed 52pt column clips at accessibility sizes; a
                // minimum lets the label wrap instead. The slider carries the
                // label for VoiceOver, so the visible text stays silent.
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 52, alignment: .leading)
                .accessibilityHidden(true)
            Slider(value: value, in: range)
                .accessibilityLabel(title)
        }
    }
}

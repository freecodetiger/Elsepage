import ReaderCore
import SwiftUI

struct ReaderScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
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
        .statusBarHidden(model.isPrepared && !model.showsControls)
        .task { await model.prepare() }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .contents: ContentsSheet(model: model)
            case .appearance: ReaderAppearanceSheet(model: model)
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
    }

    private var readerChrome: some View {
        VStack(spacing: ElsepageTheme.Spacing.small) {
            HStack(spacing: ElsepageTheme.Spacing.medium) {
                ElsepageIconButton(systemName: "chevron.left", accessibilityLabel: "返回书架") { dismiss() }
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.book.title)
                        .font(.system(.subheadline, design: .serif, weight: .semibold))
                        .lineLimit(1)
                    if let chapter = model.currentChapterTitle {
                        Text(chapter).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                ElsepageIconButton(systemName: "textformat", accessibilityLabel: "阅读设置") { presentedSheet = .appearance }
            }
            .padding(.horizontal, ElsepageTheme.Spacing.medium)
            .padding(.vertical, ElsepageTheme.Spacing.small)
            .background(ElsepageTheme.MaterialToken.chrome)

            Spacer()

            VStack(spacing: ElsepageTheme.Spacing.small) {
                HStack(spacing: ElsepageTheme.Spacing.medium) {
                    Button { presentedSheet = .contents } label: {
                        Label("目录", systemImage: "list.bullet.indent")
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(model.progress, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit().foregroundStyle(.secondary)
                        .accessibilityLabel("阅读进度")
                }
                .font(.subheadline.weight(.medium))
                ProgressView(value: model.progress)
                    .tint(.elsepageAccent)
                    .accessibilityLabel("阅读进度")
                    .accessibilityValue(Text(model.progress, format: .percent.precision(.fractionLength(0))))
            }
            .padding(ElsepageTheme.Spacing.medium)
            .background(ElsepageTheme.MaterialToken.chrome, in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ElsepageTheme.Radius.large, style: .continuous)
                    .stroke(.primary.opacity(0.06))
            }
            .shadow(
                color: ElsepageTheme.Shadow.floatingColor,
                radius: ElsepageTheme.Shadow.floatingRadius,
                y: ElsepageTheme.Shadow.floatingY
            )
            .padding(.horizontal, ElsepageTheme.Spacing.medium)
            .padding(.bottom, ElsepageTheme.Spacing.small)
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
    case contents, appearance
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
                            Text(chapter.title)
                                .foregroundStyle(.primary)
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

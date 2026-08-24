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
        .animation(.easeInOut(duration: 0.18), value: model.showsControls)
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
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                chromeButton("chevron.left") { dismiss() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.book.title)
                        .font(.system(.subheadline, design: .serif, weight: .semibold))
                        .lineLimit(1)
                    if let chapter = model.currentChapterTitle {
                        Text(chapter).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                chromeButton("textformat") { presentedSheet = .appearance }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(.regularMaterial)

            Spacer()

            VStack(spacing: 10) {
                HStack {
                    Button { presentedSheet = .contents } label: {
                        Label("目录", systemImage: "list.bullet.indent")
                    }
                    Spacer()
                    Text(model.progress, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.medium))
                ProgressView(value: model.progress).tint(.primary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .background(.regularMaterial)
        }
        .foregroundStyle(.primary)
    }

    private func chromeButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 38, height: 38)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(systemName == "chevron.left" ? "返回书库" : "阅读设置")
    }

    private var themeBackground: Color {
        switch model.preferences.theme {
        case .system: colorScheme == .dark ? .black : .white
        case .light: .white
        case .dark: .black
        case .sepia: Color(red: 0.98, green: 0.96, blue: 0.91)
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
    }

    private func settingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).frame(width: 52, alignment: .leading)
            Slider(value: value, in: range)
        }
    }
}

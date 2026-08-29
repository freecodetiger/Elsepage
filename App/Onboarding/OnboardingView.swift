import AppInfrastructure
import LibraryCore
import ModelProviders
import SwiftUI
import UniformTypeIdentifiers

/// First-launch onboarding (PRD §11): 导入第一本 EPUB → 配置 AI Provider +
/// Test Connection → 指向第一次阅读与 Reflection. Presented as a full-screen
/// cover over the tab shell. 安静、温暖、不幼稚: every step keeps a visible
/// skip, going back never scolds, and Reflection is pointed at — never forced.
struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    @Bindable var provider: ProviderSettingsModel
    /// Hands control back to the shell. A non-nil book opens the reader;
    /// nil just closes the flow (the 去书架 case switches to the shelf).
    let onFinish: (Book?) -> Void
    @State private var showsFileImporter = false

    init(model: OnboardingModel, onFinish: @escaping (Book?) -> Void) {
        self.model = model
        _provider = Bindable(model.provider)
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.xLarge) {
                    stepTitle
                    stepContent
                }
                .padding(.horizontal, ElsepageTheme.Spacing.page)
                .padding(.top, ElsepageTheme.Spacing.large)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize)
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.elsepageBackground.ignoresSafeArea())
        .animation(ElsepageTheme.Motion.quick, value: model.step)
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [UTType.epub],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await model.importEPUB(at: url) }
            }
        }
    }

    // MARK: - Header: back + progress dots

    private var header: some View {
        HStack(spacing: ElsepageTheme.Spacing.medium) {
            if model.flow.canGoBack {
                ElsepageIconButton(systemName: "chevron.left", accessibilityLabel: "上一步") {
                    model.goBack()
                }
            } else {
                // Balances the back button; matches its 44pt tap target (A11Y-03).
                Color.clear.frame(width: 44, height: 44)
            }
            Spacer()
            progressDots
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, ElsepageTheme.Spacing.page)
        .padding(.top, ElsepageTheme.Spacing.medium)
    }

    private var progressDots: some View {
        HStack(spacing: ElsepageTheme.Spacing.small) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step == model.step ? Color.elsepageAccent : Color.secondary.opacity(0.25))
                    .frame(width: step == model.step ? 22 : 7, height: 7)
            }
        }
        .animation(ElsepageTheme.Motion.quick, value: model.step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(model.step.rawValue + 1) 步，共 \(OnboardingStep.allCases.count) 步")
    }

    // MARK: - Step content

    @ViewBuilder private var stepTitle: some View {
        switch model.step {
        case .importBook:
            stepHeading(
                title: "把一本你正在读的书带进来",
                caption: "支持无 DRM 的 EPUB。它会留在你的设备上，页外不会上传它。"
            )
        case .configureAI:
            stepHeading(
                title: "连上你自己的 AI",
                caption: "填写你的 API Key，页外用它读你的书和想法。Key 只保存在本机，请求只发给你选择的服务商。"
            )
        case .firstRead:
            stepHeading(
                title: firstReadTitle,
                caption: "读完一个小节，停下来留一段想法。页外会认真读完你写下的内容，安静地回应——第一次只需要 60 秒。"
            )
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch model.step {
        case .importBook:
            importFeedback
        case .configureAI:
            providerFields
        case .firstRead:
            EmptyView()
        }
    }

    private var firstReadTitle: String {
        model.flow.importedBookTitle.map { "从《\($0)》开始第一段阅读" } ?? "去书架，挑一本开始"
    }

    private var importFeedback: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.medium) {
            if model.isImporting {
                HStack(spacing: ElsepageTheme.Spacing.small) {
                    ProgressView()
                    Text("正在导入…").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if let title = model.flow.importedBookTitle {
                Label("《\(title)》已在书架上。", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.elsepageAccent)
            }
            if let message = model.importErrorMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var providerFields: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.medium) {
            Picker("服务商", selection: Binding(
                get: { provider.selectedPreset },
                set: { provider.selectPreset($0) }
            )) {
                ForEach(ModelProviderPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.menu)

            if provider.selectedPreset == .custom {
                TextField("Base URL", text: $provider.baseURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
            }
            TextField("模型名称", text: $provider.modelID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField(provider.hasSavedKey ? "API Key（已保存）" : "API Key", text: $provider.apiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .privacySensitive()

            providerFeedback

            Text("没有 Key 也可以先跳过，纯本地阅读一样完整；之后随时能在设置中配置。")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(ElsepageTheme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ElsepageTheme.MaterialToken.chrome,
            in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.large, style: .continuous)
        )
    }

    @ViewBuilder private var providerFeedback: some View {
        if provider.lastConnectionTestSucceeded, let status = provider.statusMessage {
            Label(status, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else if let status = provider.statusMessage, !provider.isWorking {
            // e.g. 「配置已保存在本机」— saved, but the test has not passed yet.
            Label(status, systemImage: "tray.and.arrow.down").foregroundStyle(.secondary)
        } else if let error = provider.errorMessage {
            Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red)
        }
    }

    // MARK: - Bottom actions: primary + always-visible skip

    private var actions: some View {
        VStack(spacing: ElsepageTheme.Spacing.medium) {
            primaryButton
            Button(skipTitle, action: skipAction)
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, ElsepageTheme.Spacing.page)
        .padding(.top, ElsepageTheme.Spacing.small)
        .padding(.bottom, ElsepageTheme.Spacing.large)
    }

    @ViewBuilder private var primaryButton: some View {
        Button {
            primaryAction()
        } label: {
            HStack(spacing: ElsepageTheme.Spacing.small) {
                Text(primaryTitle)
                if primaryInProgress { ProgressView() }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.elsepageAccent)
        // A11Y-03: AA label on the accent fill in both color schemes.
        .foregroundStyle(Color.elsepageOnAccent)
        .disabled(primaryDisabled)
    }

    private var primaryTitle: String {
        switch model.step {
        case .importBook:
            return model.flow.importedBookTitle == nil ? "选择 EPUB 文件" : "继续"
        case .configureAI:
            return model.flow.hasSucceededConnectionTest ? "继续" : "保存并测试连接"
        case .firstRead:
            return model.importedBook == nil ? "去书架" : "打开刚导入的书"
        }
    }

    private var primaryDisabled: Bool {
        switch model.step {
        case .importBook: return model.isImporting
        case .configureAI: return provider.isWorking
        case .firstRead: return false
        }
    }

    private var primaryInProgress: Bool {
        switch model.step {
        case .importBook: return model.isImporting
        case .configureAI: return provider.isWorking
        case .firstRead: return false
        }
    }

    private func primaryAction() {
        switch model.step {
        case .importBook:
            if model.flow.importedBookTitle == nil {
                showsFileImporter = true
            } else {
                model.proceed()
            }
        case .configureAI:
            if model.flow.hasSucceededConnectionTest {
                model.proceed()
            } else {
                Task { await model.saveAndTestProvider() }
            }
        case .firstRead:
            finish(opening: model.importedBook)
        }
    }

    private var skipTitle: String {
        switch model.step {
        case .importBook: return "稍后再说"
        case .configureAI: return "先跳过，之后在设置中配置"
        case .firstRead: return "稍后再读"
        }
    }

    private func skipAction() {
        switch model.step {
        case .importBook, .configureAI:
            model.skipCurrentStep()
        case .firstRead:
            finish()
        }
    }

    // MARK: - Helpers

    private func stepHeading(title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.medium) {
            Text(title)
                .font(.system(.title, design: .serif, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(caption)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func finish(opening book: Book? = nil) {
        model.prepareForDismissal()
        onFinish(book)
    }
}

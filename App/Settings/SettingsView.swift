import ContextRouting
import ModelProviders
import SwiftUI

// MARK: - 设置主页

/// Settings root: a grouped navigation list. Each row links to a focused
/// sub-page and shows a live status summary so the user can see what's
/// configured before entering. Destructive actions live in their own pages.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: SettingsRootModel

    var body: some View {
        NavigationStack {
            List {
                Section("AI 模型与连接") {
                    NavigationLink {
                        ChatProviderView(model: model.chat) {
                            await model.deleteChatConfiguration()
                        }
                    } label: {
                        statusRow(title: "聊天模型", status: model.chatStatusText, muted: model.chatStatusColorIsMuted, icon: "bubble.left.and.bubble.right")
                    }
                    NavigationLink {
                        EmbeddingSettingsView(model: model.rag)
                    } label: {
                        statusRow(title: "Embedding", status: model.embeddingStatusText, muted: model.embeddingStatusColorIsMuted, icon: "square.grid.2x2")
                    }
                    NavigationLink {
                        RerankerSettingsView(model: model.rag)
                    } label: {
                        statusRow(title: "Reranker", status: model.rerankerStatusText, muted: model.rerankerStatusColorIsMuted, icon: "arrow.up.and.down")
                    }
                }

                if model.ragManagement != nil {
                    Section("检索 (RAG)") {
                        NavigationLink {
                            RAGManagementView(model: model.ragManagement!)
                        } label: {
                            statusRow(title: "每本书的检索进度", status: "索引状态与重新嵌入", muted: false, icon: "doc.text.magnifyingglass")
                        }
                    }
                }

                Section("诊断") {
                    NavigationLink {
                        DiagnosticsView(model: model.diagnostics)
                    } label: {
                        statusRow(title: "路由诊断", status: model.diagnosticsSummary, muted: true, icon: "chart.bar")
                    }
                }

                Section("数据与隐私") {
                    NavigationLink {
                        DataSettingsView(model: model.data)
                    } label: {
                        statusRow(title: "数据与导出", status: "导出 / 清除本地数据", muted: false, icon: "internaldrive")
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { await model.loadAll() }
            .onDisappear { model.clearTransientSecrets() }
        }
    }

    private func statusRow(title: String, status: String, muted: Bool, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(muted ? Color.secondary : Color.green)
            }
        }
        // A11Y-02: title + live status read as one stop.
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 聊天模型

struct ChatProviderView: View {
    @Bindable var model: ProviderSettingsModel
    let onDeleteConfiguration: @MainActor () async -> Void
    @State private var showsDeleteConfirmation = false

    var body: some View {
        Form {
            Section("Provider") {
                Picker("服务商", selection: Binding(
                    get: { model.selectedPreset },
                    set: { model.selectPreset($0) }
                )) {
                    ForEach(ModelProviderPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                if model.selectedPreset == .custom {
                    TextField("Base URL", text: $model.baseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                } else {
                    LabeledContent("Base URL", value: model.baseURL)
                        .font(.footnote)
                        .textSelection(.enabled)
                }
                TextField("模型", text: $model.modelID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(model.hasSavedKey ? "API Key（已保存）" : "API Key", text: $model.apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
            }

            Section {
                Button("保存配置") { Task { _ = await model.save() } }
                Button("测试连接") { Task { await model.testConnection() } }
                if model.hasSavedKey {
                    Button("删除配置和 API Key", role: .destructive) { showsDeleteConfirmation = true }
                }
            } footer: {
                Text("预设会自动使用服务商的 OpenAI-compatible 地址。API Key 只保存在本机 Keychain；模型名请按服务商控制台填写。")
            }
            .disabled(model.isWorking)

            if let status = model.statusMessage {
                Section { Label(status, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
        }
        .navigationTitle("聊天模型")
        .navigationBarTitleDisplayMode(.inline)
        .alert("操作失败", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) { Button("好") {} } message: { Text(model.errorMessage ?? "") }
        .alert("删除配置和 API Key？", isPresented: $showsDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task { await onDeleteConfiguration() }
            }
        } message: {
            Text("将删除聊天、Embedding 与 Reranker 的全部配置和 API Key（仅本机 Keychain）。")
        }
    }
}

// MARK: - Embedding / Reranker 角色页

struct EmbeddingSettingsView: View {
    @Bindable var model: RAGSettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("启用语义检索", isOn: Binding(
                    get: { model.embeddingEnabled },
                    set: { enabled in Task { enabled ? await model.enableEmbedding() : await model.disableEmbedding() } }
                ))
            }

            Section {
                Picker("Embedding 预设", selection: $model.embeddingPresetSelection) {
                    Text("自定义").tag("")
                    ForEach(ProviderSettingsModel.siliconFlowEmbeddingModels, id: \.model) { preset in
                        Text(preset.name).tag(preset.model)
                    }
                }
                TextField("Embedding 模型", text: $model.embeddingModelID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(model.embeddingEnabled)
                TextField("Embedding Base URL", text: $model.embeddingBaseURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .disabled(model.embeddingEnabled)
                SecureField(model.embeddingHasSavedKey ? "Embedding API Key（已保存）" : "Embedding API Key", text: $model.embeddingApiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                    .disabled(model.embeddingEnabled)
                if model.embeddingEnabled {
                    Label("语义检索已启用（\(model.embeddingModelID)）", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Button("测试 Embedding") { Task { await model.testEmbedding() } }
                if let status = model.embeddingStatusMessage {
                    Label(status, systemImage: "sparkles").foregroundStyle(.secondary)
                }
            } header: {
                Text("Embedding")
            } footer: {
                Text("为每本书建立向量索引（语义召回）。独立 Base URL 与 API Key（与聊天 Provider 无关）；未配置或失败时自动降级为词法检索。")
            }
            .disabled(model.isEmbeddingWorking)
        }
        .navigationTitle("Embedding")
        .navigationBarTitleDisplayMode(.inline)
        .alert("操作失败", isPresented: errorBinding) {
            Button("好") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}

struct RerankerSettingsView: View {
    @Bindable var model: RAGSettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("启用 Reranker", isOn: Binding(
                    get: { model.rerankerEnabled },
                    set: { enabled in Task { enabled ? await model.enableReranker() : await model.disableReranker() } }
                ))
            }

            Section {
                Picker("Reranker 预设", selection: $model.rerankerPresetSelection) {
                    Text("自定义").tag("")
                    ForEach(ProviderSettingsModel.siliconFlowRerankerModels, id: \.model) { preset in
                        Text(preset.name).tag(preset.model)
                    }
                }
                TextField("Reranker 模型", text: $model.rerankerModelID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(model.rerankerEnabled)
                TextField("Reranker Base URL", text: $model.rerankerBaseURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .disabled(model.rerankerEnabled)
                SecureField(model.rerankerHasSavedKey ? "Reranker API Key（已保存）" : "Reranker API Key", text: $model.rerankerApiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                    .disabled(model.rerankerEnabled)
                if model.rerankerEnabled {
                    Label("Reranker 已启用（\(model.rerankerModelID)）", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Button("测试 Reranker") { Task { await model.testReranker() } }
                if let status = model.rerankerStatusMessage {
                    Label(status, systemImage: "sparkles").foregroundStyle(.secondary)
                }
            } header: {
                Text("Reranker")
            } footer: {
                Text("对召回候选做精排门禁，低相关的不再作为证据发给 Agent。独立 Base URL 与 API Key；未配置或失败时自动使用融合结果。")
            }
            .disabled(model.isRerankerWorking)
        }
        .navigationTitle("Reranker")
        .navigationBarTitleDisplayMode(.inline)
        .alert("操作失败", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) { Button("好") {} } message: { Text(model.errorMessage ?? "") }
    }
}

// MARK: - 路由诊断

struct DiagnosticsView: View {
    @Bindable var model: DiagnosticsModel

    var body: some View {
        Form {
            if let diagnostics = model.routingDiagnostics {
                let fallbacks = diagnostics.fallbackCounts.sorted { $0.value > $1.value }
                    .map { "\($0.key): \($0.value)" }
                    .joined(separator: "、")
                Section {
                    LabeledContent("总追踪数", value: "\(diagnostics.totalTraces)")
                    LabeledContent("回退次数", value: fallbacks.isEmpty ? "0" : fallbacks)
                    LabeledContent("路由平均", value: Self.durationText(diagnostics.averageRoutingDuration))
                    LabeledContent("检索平均", value: Self.durationText(diagnostics.averageRetrievalDuration))
                    LabeledContent("回应平均", value: Self.durationText(diagnostics.averageReplyDuration))
                } header: {
                    Text("路由诊断")
                } footer: {
                    Text("记录每次 Agent 回应使用的上下文与耗时，仅存本机摘要，不保存原文。")
                }

                Section {
                    ForEach(model.recentTraces, id: \.id) { trace in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(Self.timeText(trace.createdAt))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if trace.usedFallback {
                                    Text(Self.fallbackText(trace))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.red)
                                } else {
                                    Text("正常")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if trace.usedFallback {
                                Text(Self.fallbackDetailText(trace))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(Self.metricsText(trace))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("最近路由")
                } footer: {
                    Text("回退原因里 invalidStructuredOutput 表示模型返回的计划无法解析，modelFailure 表示模型请求本身失败（细因为具体错误）。")
                }
            } else {
                Section { Text("暂无诊断数据") }
            }
        }
        .navigationTitle("路由诊断")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.reload() }
    }

    private static func timeText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }

    private static func fallbackText(_ trace: ContextPlanTrace) -> String {
        if let detail = trace.fallbackDetail, !detail.isEmpty {
            return "\(trace.fallbackReason?.rawValue ?? "unknown") · \(detail)"
        }
        return trace.fallbackReason?.rawValue ?? "unknown"
    }

    private static func fallbackDetailText(_ trace: ContextPlanTrace) -> String {
        let detail = trace.fallbackDetail ?? ""
        let reason = trace.fallbackReason?.rawValue ?? "unknown"
        return detail.isEmpty ? reason : "\(reason)：\(detail)"
    }

    private static func metricsText(_ trace: ContextPlanTrace) -> String {
        var parts = [
            "路由\(Self.secondsText(trace.routingDuration))",
            "检索\(Self.secondsText(trace.retrievalDuration))",
            "回应\(Self.secondsText(trace.replyDuration))",
        ]
        if let metrics = trace.pipelineMetrics {
            var evidence: [String] = []
            if let book = metrics.expandedEvidenceCount { evidence.append("书\(book)") }
            if let thought = metrics.reflectionEvidenceCount { evidence.append("思\(thought)") }
            if let memory = metrics.memoryEvidenceCount { evidence.append("记\(memory)") }
            if !evidence.isEmpty { parts.append("证据 " + evidence.joined(separator: "/")) }
        }
        if let routingTokens = trace.routingTokenUsage?.totalTokens {
            parts.append("路由 tokens \(routingTokens)")
        }
        if let replyTokens = trace.replyTokenUsage?.totalTokens {
            parts.append("回应 tokens \(replyTokens)")
        }
        return parts.joined(separator: " · ")
    }

    private static func secondsText(_ duration: Duration) -> String {
        String(format: "%.2fs", secondsValue(duration))
    }

    private static func durationText(_ duration: Duration?) -> String {
        guard let duration else { return "—" }
        return String(format: "%.2f 秒", secondsValue(duration))
    }

    private static func secondsValue(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

// MARK: - 数据与隐私

struct DataSettingsView: View {
    @Bindable var model: DataSettingsModel
    @State private var showsDeleteAllConfirmation = false
    @State private var showsWipeList = false
    @State private var showsWipeConfirmation = false

    var body: some View {
        Form {
            Section {
                Button("导出我的数据") { Task { await model.exportMyData() } }
                if let url = model.exportedDataURL {
                    ShareLink(item: url) {
                        Label("分享导出的 JSON", systemImage: "square.and.arrow.up")
                    }
                }
            } footer: {
                Text("导出包含你的书籍、阅读位置、高亮、笔记、反思、长期记忆与「AI 眼中的我」档案，不含 Provider 配置或 API Key。")
            }

            Section {
                Button("删除书籍与索引", role: .destructive) {
                    showsDeleteAllConfirmation = true
                }
                .disabled(model.isDeletingAllBooks)
            } footer: {
                Text("删除书籍会一并移除数据库记录与沙盒文件（含索引），且不可撤销；Provider 配置和 Keychain 不受影响。")
            }

            wipeSection
        }
        .navigationTitle("数据与隐私")
        .navigationBarTitleDisplayMode(.inline)
        .alert("操作失败", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) { Button("好") {} } message: { Text(model.errorMessage ?? "") }
        .alert("删除全部书籍与索引？", isPresented: $showsDeleteAllConfirmation) {
            Button("取消", role: .cancel) {}
            Button("全部删除", role: .destructive) {
                Task { await model.deleteAllBooks() }
            }
        } message: {
            Text("将删除书库中全部书籍的数据库记录与沙盒文件（含阅读位置、高亮、笔记、反思、会话与索引）。此操作不可撤销。Provider 配置和 API Key 不受影响。")
        }
        .alert("清除所有本地数据？", isPresented: $showsWipeConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除所有数据", role: .destructive) {
                Task { await model.wipeAllLocalData() }
            }
        } message: {
            Text("以上列出的全部内容将被永久删除，应用会回到首次启动状态。此操作不可撤销。")
        }
    }

    /// Stage one of the destructive confirmation: the first tap only reveals
    /// what exactly will be deleted; the red confirm button inside opens the
    /// final system alert that performs the wipe.
    @ViewBuilder private var wipeSection: some View {
        Section {
            if !showsWipeList {
                Button("清除所有本地数据", role: .destructive) {
                    showsWipeList = true
                }
                .disabled(model.isWipingAllData)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("将删除以下全部内容：")
                        .font(.subheadline.weight(.semibold))
                    ForEach(Self.wipeScope, id: \.self) { item in
                        Label(item, systemImage: "minus")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                Button("确认清除所有数据", role: .destructive) {
                    showsWipeConfirmation = true
                }
                .disabled(model.isWipingAllData)
            }
        } footer: {
            Text("清除后应用回到首次启动状态：需要重新配置 Provider 并重新导入书籍。此操作不可撤销。")
        }
    }

    private static let wipeScope = [
        "全部书籍与其 EPUB 文件",
        "全文与向量索引",
        "阅读位置、高亮与笔记",
        "阅读会话与反思（含思想、提问、引用与依据）",
        "长期记忆与成就",
        "Provider 配置与 API Key（Keychain）",
        "全部本地偏好设置",
    ]
}

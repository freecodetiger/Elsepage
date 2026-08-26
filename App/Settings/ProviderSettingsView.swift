import ModelProviders
import SwiftUI

struct ProviderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: ProviderSettingsModel
    @State private var showsDeleteAllConfirmation = false

    var body: some View {
        NavigationStack {
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
                        Button("删除配置和 API Key", role: .destructive) {
                            Task { await model.deleteConfiguration() }
                        }
                    }
                } footer: {
                    Text("预设会自动使用服务商的 OpenAI-compatible 地址。API Key 只保存在本机 Keychain；模型名请按服务商控制台填写。")
                }
                .disabled(model.isWorking)

                if let status = model.statusMessage {
                    Section { Label(status, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }

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
                    Button(model.embeddingEnabled ? "停用语义检索" : "启用语义检索") {
                        Task { await (model.embeddingEnabled ? model.disableEmbedding() : model.enableEmbedding()) }
                    }
                    if let status = model.embeddingStatusMessage {
                        Label(status, systemImage: "sparkles").foregroundStyle(.secondary)
                    }

                    Divider()

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
                    Button(model.rerankerEnabled ? "停用 Reranker" : "启用 Reranker") {
                        Task { await (model.rerankerEnabled ? model.disableReranker() : model.enableReranker()) }
                    }
                    if let status = model.rerankerStatusMessage {
                        Label(status, systemImage: "sparkles").foregroundStyle(.secondary)
                    }

                    if let ragManagement = model.ragManagement {
                        NavigationLink {
                            RAGManagementView(model: ragManagement)
                        } label: {
                            Label("管理每本书的检索进度", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                } header: {
                    Text("语义检索 (RAG)")
                } footer: {
                    Text("Embedding：为每本书建立向量索引（语义召回）。Reranker：对召回候选做精排门禁，低相关的不再作为证据发给 Agent。两者各自独立的 Base URL 与 API Key（与聊天 Provider 无关），选硅基流动预设会自动填地址，需联网；未配置或失败时自动降级（词法 / 融合结果）。")
                }
                .disabled(model.isEmbeddingWorking || model.isRerankerWorking)

                Section {
                    Button("导出我的数据") {
                        Task { await model.exportMyData() }
                    }
                    if let url = model.exportedDataURL {
                        ShareLink(item: url) {
                            Label("分享导出的 JSON", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button("删除书籍与索引", role: .destructive) {
                        showsDeleteAllConfirmation = true
                    }
                    .disabled(model.isDeletingAllBooks)
                } header: {
                    Text("数据")
                } footer: {
                    Text("导出包含你的书籍、阅读位置、高亮、笔记、反思与记录，不含 Provider 配置或 API Key。删除书籍会一并移除数据库记录与沙盒文件（含索引），且不可撤销；Provider 配置和 Keychain 不受影响。")
                }
            }
            .navigationTitle("AI Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { await model.load() }
            .onDisappear { model.clearTransientSecret() }
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
        }
    }

    private static func durationText(_ duration: Duration?) -> String {
        guard let duration else { return "—" }
        let components = duration.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
        return String(format: "%.2f 秒", seconds)
    }
}

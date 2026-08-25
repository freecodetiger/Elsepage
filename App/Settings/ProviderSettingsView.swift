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

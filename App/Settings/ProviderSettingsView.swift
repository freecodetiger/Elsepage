import ModelProviders
import SwiftUI

struct ProviderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: ProviderSettingsModel

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
        }
    }
}

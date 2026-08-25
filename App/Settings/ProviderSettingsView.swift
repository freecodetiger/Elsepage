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
                        get: { model.provider },
                        set: { model.selectProvider($0) }
                    )) {
                        Text("OpenAI").tag(ModelProviderKind.openAI)
                        Text("OpenAI-compatible").tag(ModelProviderKind.openAICompatible)
                    }
                    TextField("Base URL", text: $model.baseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
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
                    Text("API Key 只保存在本机 Keychain。测试连接会向所选 Provider 发送一条最小测试消息。")
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

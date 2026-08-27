import Foundation
import Observation

/// Settings root: aggregates the focused sub-models (chat provider, RAG roles,
/// diagnostics, data) and exposes the status summaries the main settings list
/// shows. Cross-model coordination (config delete resets roles, transient key
/// clearing) lives here.
@MainActor @Observable
final class SettingsRootModel {
    let chat: ProviderSettingsModel
    let rag: RAGSettingsModel
    let diagnostics: DiagnosticsModel
    let data: DataSettingsModel
    /// Per-book RAG progress page model (owned by AppModel, shared here).
    let ragManagement: RAGManagementModel?

    init(
        chat: ProviderSettingsModel,
        rag: RAGSettingsModel,
        diagnostics: DiagnosticsModel,
        data: DataSettingsModel,
        ragManagement: RAGManagementModel? = nil
    ) {
        self.chat = chat
        self.rag = rag
        self.diagnostics = diagnostics
        self.data = data
        self.ragManagement = ragManagement
    }

    func loadAll() async {
        await chat.load()
        await rag.load()
        await diagnostics.reload()
    }

    /// Whether an Agent reply can be requested at all (chat provider configured).
    var hasSavedKey: Bool { chat.hasSavedKey }

    // MARK: - Status previews for the main list

    var chatStatusText: String { chat.hasSavedKey ? chat.modelID : "未配置" }
    var chatStatusColorIsMuted: Bool { !chat.hasSavedKey }

    var embeddingStatusText: String { rag.embeddingEnabled ? rag.embeddingModelID : "未启用" }
    var embeddingStatusColorIsMuted: Bool { !rag.embeddingEnabled }

    var rerankerStatusText: String { rag.rerankerEnabled ? rag.rerankerModelID : "未启用" }
    var rerankerStatusColorIsMuted: Bool { !rag.rerankerEnabled }

    var diagnosticsSummary: String {
        guard let d = diagnostics.routingDiagnostics else { return "—" }
        let fallbacks = d.fallbackCounts.values.reduce(0, +)
        return "\(d.totalTraces) 次 · \(fallbacks) 次回退"
    }

    // MARK: - Cross-model coordination

    func deleteChatConfiguration() async {
        await chat.deleteConfiguration()
        rag.resetAfterConfigDelete()
    }

    func clearTransientSecrets() {
        chat.clearTransientSecret()
        rag.clearTransientSecrets()
    }
}

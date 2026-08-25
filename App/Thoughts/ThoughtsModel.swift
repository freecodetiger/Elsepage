import Foundation
import LibraryCore
import Observation
import ReaderAgent
import ReflectionCore

/// Presentation state for the local Reflection archive and explicit ReaderAgent replies.
/// It does not know provider HTTP, credentials, Memory, or retrieval details.
@MainActor @Observable
final class ThoughtsModel {
    private let archive: ReflectionArchiveService
    private let readerAgent: ReaderAgent

    private(set) var entries: [ReflectionArchiveEntry] = []
    private(set) var isLoading = false
    private(set) var replyingTo: ReflectionID?
    var errorMessage: String?

    init(
        books: any BookRepository,
        reflections: any ReflectionRepository,
        readerAgent: ReaderAgent
    ) {
        archive = ReflectionArchiveService(books: books, reflections: reflections)
        self.readerAgent = readerAgent
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await archive.recentEntries()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestAgentReply(for reflection: Reflection) async {
        guard replyingTo == nil else { return }
        replyingTo = reflection.id
        defer { replyingTo = nil }
        for await event in readerAgent.respond(to: reflection.id) {
            switch event {
            case .completed:
                await reload()
            case .failed(let failure):
                errorMessage = Self.message(for: failure)
            case .started, .textDelta, .cancelled:
                break
            }
        }
    }

    private static func message(for failure: ReaderAgentFailure) -> String {
        switch failure {
        case .missingReflection: "找不到这条 Reflection。"
        case .providerNotConfigured: "请先配置并测试 AI Provider。"
        case .emptyResponse: "Provider 没有返回可显示的内容。"
        case .persistence: "Agent 回复无法保存到本机。"
        case .runtime(let failure):
            switch failure {
            case .authentication: "API Key 无效或没有访问权限。"
            case .rateLimited: "Provider 请求过于频繁，请稍后再试。"
            case .providerUnavailable: "Provider 暂时不可用。"
            case .network: "网络连接失败。"
            case .malformedProviderResponse: "Provider 返回了无法识别的响应。"
            case .budgetExceeded: "本次 Agent 请求超出时间或调用预算。"
            case .unknown: "Agent 暂时无法完成回应。"
            }
        }
    }
}

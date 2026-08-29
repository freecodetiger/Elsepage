import AchievementCore
import AgentRuntime
import ContextRouting
import Foundation
import LibraryCore
import Observation
import ReaderAgent
import ReaderCore
import ReadingSessionCore
import ReflectionCore
import RetrievalCore

/// Presentation state for the local Reflection archive, the structured Journal,
/// and explicit ReaderAgent replies. It does not know provider HTTP, credentials,
/// Memory, or retrieval details.
@MainActor @Observable
final class ThoughtsModel {
    private let archive: ReflectionArchiveService
    private let journalService: JournalEntryService
    private let readerAgent: ReaderAgent
    private let traceRepository: (any RoutingTraceRepository)?
    private let reflections: any ReflectionRepository
    private let makePolishService: (@MainActor () async -> TranscriptPolishService?)?
    let achievements: AchievementModel?

    private(set) var entries: [ReflectionArchiveEntry] = []
    private(set) var journalEntries: [JournalEntry] = []
    private(set) var isLoading = false
    private(set) var replyingTo: ReflectionID?
    /// Latest stored trace per reflection, used for archive disclosure.
    private(set) var tracesByReflection: [ReflectionID: ContextPlanTrace] = [:]
    var errorMessage: String?

    init(
        books: any BookRepository,
        reflections: any ReflectionRepository,
        sessions: any ReadingSessionRepository,
        reading: any ReadingRepository,
        index: any BookIndexRepository,
        journal: any JournalRepository,
        readerAgent: ReaderAgent,
        makePolishService: (@MainActor () async -> TranscriptPolishService?)? = nil,
        traceRepository: (any RoutingTraceRepository)? = nil,
        memoryRepository: (any MemoryRepository)? = nil,
        achievements: AchievementModel? = nil
    ) {
        archive = ReflectionArchiveService(books: books, reflections: reflections)
        journalService = JournalEntryService(
            books: books, reflections: reflections,
            sessions: sessions, index: index, reading: reading, journal: journal,
            memoryRepository: memoryRepository
        )
        self.reflections = reflections
        self.readerAgent = readerAgent
        self.makePolishService = makePolishService
        self.traceRepository = traceRepository
        self.achievements = achievements
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await archive.recentEntries()
            if let traceRepository {
                var traces: [ReflectionID: ContextPlanTrace] = [:]
                for entry in entries {
                    if let trace = try? await traceRepository.latestTrace(for: entry.reflection.id.description) {
                        traces[entry.reflection.id] = trace
                    }
                }
                tracesByReflection = traces
            }
            journalEntries = try await journalService.recentEntries()
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
            case .contextPrepared(let connection):
                if let connection, let achievements,
                   let connected = try? await reflections.reflection(id: connection.sourceReflectionID) {
                    await achievements.handle(.init(
                        reflection: reflection,
                        connectedSource: .init(reflection: connected, bookID: connected.bookID),
                        now: Date()
                    ))
                }
            case .started, .textDelta, .citationsValidated, .contextDisclosed, .cancelled:
                break
            }
        }
    }

    func makeConversation(for reflection: Reflection) -> ReflectionConversationModel {
        ReflectionConversationModel(
            reflection: reflection,
            repository: reflections,
            readerAgent: readerAgent,
            makePolishService: makePolishService,
            achievements: achievements
        )
    }

    /// JRNL-01/02: persists the user's edit of an Agent-drafted "What I think"
    /// bullet and refreshes the Journal. No-ops on unchanged or empty text.
    func applyThoughtEdit(_ thought: JournalThought, newText: String) async {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != thought.thought else { return }
        do {
            try await journalService.applyUserEdit(thoughtID: thought.id, newText: trimmed)
            await reload()
        } catch {
            errorMessage = "修改没能保存到本机。"
        }
    }

    private static func message(for failure: ReaderAgentFailure) -> String {
        switch failure {
        case .missingReflection: "找不到这条 Reflection。"
        case .providerNotConfigured: "请先配置并测试 AI Provider。"
        case .emptyResponse: "Provider 没有返回可显示的内容。"
        case .emptyUserMessage: "请先写下想继续说的内容。"
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

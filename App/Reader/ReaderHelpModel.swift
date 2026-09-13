import Foundation
import LibraryCore
import Observation
import ReaderAgent
import ReaderCore
import ReflectionCore
import UIKit

enum ReaderHelpModelError: LocalizedError {
    case readerUnavailable

    var errorDescription: String? {
        switch self {
        case .readerUnavailable: "阅读器已关闭。"
        }
    }
}

@MainActor @Observable
final class ReaderHelpModel {
    enum State: Equatable {
        case idle
        case preparing
        case streaming
        case completed
        case cancelled
        case failed(String)
    }

    static let defaultQuestion = "请解释这段文字在当前上下文中的意思。"

    let book: Book
    let anchor: BookLocator
    let selectedText: String
    let chapterTitle: String?

    private let service: ReaderHelpService
    private let persistNote: @MainActor (String) async throws -> Void

    var composerText = ""
    private(set) var turns: [ReaderHelpTurn] = []
    private(set) var activeQuestion: String?
    private(set) var streamingContent = ""
    private(set) var state: State = .idle
    private(set) var contextSummary: ReaderHelpContextSummary?
    private(set) var provenance: AgentResponseProvenance?
    private(set) var latestResponseID: UUID?
    var saveError: String?

    private var savedResponseID: UUID?

    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var streamingBuffer = StreamingResponseBuffer()
    @ObservationIgnored private var lastQuestion: String?
    @ObservationIgnored private var firstDeltaRecorded = false

    init(
        book: Book,
        anchor: BookLocator,
        selectedText: String,
        chapterTitle: String?,
        service: ReaderHelpService,
        persistNote: @escaping @MainActor (String) async throws -> Void
    ) {
        self.book = book
        self.anchor = anchor
        self.selectedText = selectedText
        self.chapterTitle = chapterTitle
        self.service = service
        self.persistNote = persistNote
    }

    var isBusy: Bool {
        state == .preparing || state == .streaming
    }

    var canSubmitComposer: Bool {
        !isBusy && !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canRetry: Bool {
        (state == .cancelled || isFailure) && lastQuestion != nil
    }

    var isSaved: Bool {
        latestResponseID != nil && savedResponseID == latestResponseID
    }

    var canSave: Bool {
        state == .completed && !isSaved && latestAgentAnswer != nil
    }

    var latestAgentAnswer: String? {
        turns.last(where: { $0.role == .agent })?.content
    }

    var contextDisclosure: String? {
        guard let contextSummary else { return nil }
        if contextSummary.failClosedReason != nil {
            return "仅基于当前可见文本回答，未检索后文。"
        }
        if contextSummary.retrievedBookEvidenceCount > 0 {
            return "基于当前选段、附近原文和 \(contextSummary.retrievedBookEvidenceCount) 条已读内容。"
        }
        if contextSummary.includedNearbyPassage {
            return "基于当前选段和附近已读原文。"
        }
        return nil
    }

    func explainSelection() {
        send(Self.defaultQuestion)
    }

    func sendComposer() {
        let question = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        composerText = ""
        send(question)
    }

    func retry() {
        guard let lastQuestion else { return }
        send(lastQuestion)
    }

    func cancel() {
        runTask?.cancel()
        runTask = nil
        flushStreamingResponse()
        streamingBuffer.discardPending()
        if isBusy {
            state = .cancelled
        }
    }

    func copyLatestAnswer() {
        guard let latestAgentAnswer else { return }
        UIPasteboard.general.string = latestAgentAnswer
    }

    func saveLatestAnswer() async {
        guard canSave, let responseID = latestResponseID, let body = noteBody else { return }
        do {
            try await persistNote(body)
            savedResponseID = responseID
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    private var isFailure: Bool {
        if case .failed = state { return true }
        return false
    }

    private var noteBody: String? {
        let relevant = turns
        guard !relevant.isEmpty else { return nil }
        let lines: [String] = relevant.compactMap { turn in
            let content = turn.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            switch turn.role {
            case .user:
                return content == Self.defaultQuestion ? nil : "问：\(content)"
            case .agent:
                return "Agent：\(content)"
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }

    private func send(_ question: String) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isBusy else { return }

        flushTask?.cancel()
        flushTask = nil
        streamingBuffer.begin()
        lastQuestion = question
        activeQuestion = question
        streamingContent = ""
        contextSummary = nil
        provenance = nil
        latestResponseID = nil
        saveError = nil
        state = .preparing
        runTask?.cancel()

        firstDeltaRecorded = false
        Perf.shared.event("readerHelp.start")
        let request = ReaderHelpRequest(
            bookID: book.id,
            anchor: anchor,
            selectedText: selectedText,
            question: question,
            recentTurns: turns
        )
        runTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.service.answer(request) {
                guard !Task.isCancelled else { return }
                self.handle(event, question: question)
            }
        }
    }

    private func handle(_ event: ReaderHelpEvent, question: String) {
        switch event {
        case .started:
            state = .preparing

        case .contextPrepared(let summary):
            contextSummary = summary
            Perf.shared.event("readerHelp.context nearby=\(summary.includedNearbyPassage) evidence=\(summary.retrievedBookEvidenceCount) active=\(summary.usedActiveChunk) failClosed=\(summary.failClosedReason?.rawValue ?? "none")")
            state = streamingContent.isEmpty ? .preparing : .streaming

        case .textDelta(let text):
            if !firstDeltaRecorded {
                firstDeltaRecorded = true
                Perf.shared.event("readerHelp.firstDelta")
            }
            streamingBuffer.append(text)
            state = .streaming
            scheduleStreamFlush()

        case .citationsValidated(let provenance):
            self.provenance = provenance

        case .completed(let response):
            flushTask?.cancel()
            flushTask = nil
            streamingBuffer.complete()
            turns.append(ReaderHelpTurn(role: .user, content: question))
            turns.append(ReaderHelpTurn(role: .agent, content: response.content))
            activeQuestion = nil
            streamingContent = ""
            provenance = response.provenance
            latestResponseID = response.id
            state = .completed
            Perf.shared.event("readerHelp.complete")
            runTask = nil

        case .cancelled:
            flushStreamingResponse()
            streamingBuffer.discardPending()
            state = .cancelled
            Perf.shared.event("readerHelp.cancel")
            runTask = nil

        case .failed(let failure):
            flushStreamingResponse()
            streamingBuffer.discardPending()
            state = .failed(Self.message(for: failure))
            Perf.shared.event("readerHelp.fail")
            runTask = nil
        }
    }

    private func scheduleStreamFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            self?.flushStreamingResponse()
        }
    }

    private func flushStreamingResponse() {
        flushTask?.cancel()
        flushTask = nil
        let next = streamingBuffer.flush(using: Self.visibleContent)
        if streamingContent != next {
            streamingContent = next
        }
    }

    private static func visibleContent(_ content: String) -> String {
        guard let range = content.range(of: "---CITATIONS---") else { return content }
        return String(content[..<range.lowerBound])
    }

    private static func message(for failure: ReaderHelpFailure) -> String {
        switch failure {
        case .providerNotConfigured:
            "还没有配置可用的模型服务。"
        case .invalidSelection:
            "没有可用的选中文字。"
        case .emptyQuestion:
            "请输入想问的问题。"
        case .selectionTooLong:
            "选段太长，请缩小选区或输入更具体的问题。"
        case .questionTooLong:
            "问题太长，请压缩到 500 字以内。"
        case .runtime(.authentication):
            "模型认证失败，请检查 Provider 设置。"
        case .runtime(.rateLimited):
            "请求过于频繁，请稍后再试。"
        case .runtime(.network):
            "网络不可用，请稍后重试。"
        case .runtime(.providerUnavailable):
            "模型服务暂时不可用。"
        case .runtime(.budgetExceeded):
            "这次回答超时了，可以重试。"
        case .runtime:
            "模型没有完成这次回答。"
        case .emptyResponse:
            "模型没有返回可显示的回答。"
        }
    }
}

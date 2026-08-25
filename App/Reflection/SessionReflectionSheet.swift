import LibraryCore
import Observation
import ReaderCore
import ReaderAgent
import ReadingSessionCore
import ReflectionCore
import SwiftUI

/// Feature-scoped state for the text-only, local-first reflection prompt.
/// Construction happens after the caller has ended a `ReadingSession`.
@MainActor @Observable
final class SessionReflectionModel: Identifiable {
    let id = UUID()
    enum SubmissionState: Equatable {
        case editing
        case saving
        case saved
    }

    let book: Book
    let summary: SessionEndingSummary
    let locator: BookLocator
    private let submission: TextReflectionSubmissionService
    private let reflectionRepository: any ReflectionRepository
    private let readerAgent: ReaderAgent
    private let draftID = ReflectionID()

    var text = ""
    private(set) var state: SubmissionState = .editing
    private(set) var reflection: Reflection?
    private(set) var messages: [ReflectionMessage] = []
    private(set) var responseProvenance: [UUID: AgentResponseProvenance] = [:]
    private(set) var streamingResponse = ""
    private(set) var connectedReflection: Reflection?
    private(set) var isResponding = false
    var followUpText = ""
    var agentNotice: String?
    var errorMessage: String?
    private var followUpID = UUID()

    init(
        book: Book,
        summary: SessionEndingSummary,
        locator: BookLocator,
        reflectionRepository: any ReflectionRepository,
        readerAgent: ReaderAgent
    ) {
        self.book = book
        self.summary = summary
        self.locator = locator
        self.reflectionRepository = reflectionRepository
        self.readerAgent = readerAgent
        submission = TextReflectionSubmissionService(repository: reflectionRepository)
    }

    var canSubmit: Bool {
        state == .editing && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func submit() async -> Reflection? {
        guard canSubmit else { return nil }
        state = .saving
        do {
            let reflection = try await submission.submit(.init(
                id: draftID,
                bookID: book.id,
                sessionID: summary.session.id,
                locator: locator,
                originalText: text
            ))
            self.reflection = reflection
            state = .saved
            return reflection
        } catch is CancellationError {
            state = .editing
            return nil
        } catch {
            state = .editing
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func requestAgentReply() async {
        guard let reflection, !isResponding else { return }
        await consume(readerAgent.respond(to: reflection.id))
    }

    func continueDiscussion() async {
        guard let reflection, !isResponding else { return }
        let trimmed = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = followUpID
        await consume(readerAgent.continueDiscussion(on: reflection.id, messageID: id, text: trimmed))
        if agentNotice == nil {
            followUpText = ""
            followUpID = UUID()
        }
    }

    private func consume(_ stream: AsyncStream<ReaderAgentEvent>) async {
        isResponding = true
        streamingResponse = ""
        agentNotice = nil
        defer { isResponding = false }
        for await event in stream {
            switch event {
            case .started:
                break
            case .contextPrepared(let connection):
                if let connection {
                    connectedReflection = try? await reflectionRepository.reflection(id: connection.sourceReflectionID)
                }
            case .textDelta(let text):
                streamingResponse = Self.withoutCitationBlock(streamingResponse + text)
            case .citationsValidated(let provenance):
                if let messageID = provenance.evidence.first?.messageID {
                    responseProvenance[messageID] = provenance
                }
            case .completed:
                await reloadMessages()
                streamingResponse = ""
            case .cancelled:
                agentNotice = nil
            case .failed(.providerNotConfigured):
                agentNotice = "想法已经保存在本机。需要时，你可以稍后再邀请回应。"
            case .failed(let failure):
                agentNotice = Self.message(for: failure)
            }
        }
    }

    private func reloadMessages() async {
        guard let reflection else { return }
        messages = (try? await reflectionRepository.messages(for: reflection.id)) ?? messages
        for message in messages where message.author == .agent {
            if let provenance = try? await reflectionRepository.provenance(for: message.id) {
                responseProvenance[message.id] = provenance
            }
        }
    }

    private static func withoutCitationBlock(_ content: String) -> String {
        guard let range = content.range(of: "---CITATIONS---") else { return content }
        return String(content[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func message(for failure: ReaderAgentFailure) -> String {
        switch failure {
        case .missingReflection, .persistence: "想法已保存，但回应暂时无法继续。"
        case .providerNotConfigured: "想法已经保存在本机。"
        case .emptyResponse: "这次没有收到可显示的回应，可以稍后重试。"
        case .emptyUserMessage: "先写下一点想继续说的内容。"
        case .runtime(.authentication): "当前模型配置无法通过验证，想法仍已保存。"
        case .runtime(.rateLimited): "回应有点拥挤，可以稍后再试。"
        case .runtime(.network), .runtime(.providerUnavailable): "现在网络不可用，想法仍已保存在本机。"
        case .runtime(.malformedProviderResponse), .runtime(.budgetExceeded), .runtime(.unknown):
            "这次回应没有完成，想法仍已保存在本机。"
        }
    }
}

struct SessionReflectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: SessionReflectionModel
    let onSaved: @MainActor (Reflection) -> Void
    var openCitation: ((AgentResponseEvidence) -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.large) {
                    header
                    if model.reflection == nil { editor } else { conversation }
                }
                .padding(ElsepageTheme.Spacing.page)
            }
            .background(Color.elsepageBackground)
            .navigationTitle("留下些什么")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.reflection == nil ? "今天先不了" : "完成") { dismiss() }
                }
                if model.reflection == nil { ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            if let reflection = await model.submit() {
                                onSaved(reflection)
                                await model.requestAgentReply()
                            }
                        }
                    }
                    .disabled(!model.canSubmit)
                } }
            }
        }
        .alert("暂时无法保存", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
            TextField("写下一点此刻真正留下来的东西…", text: $model.text, axis: .vertical)
                .lineLimit(5...12)
                .padding(ElsepageTheme.Spacing.medium)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous))
                .accessibilityLabel("本次阅读感想")
            Text("这是你的原始想法，会先保存在本机，再决定是否邀请回应。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.medium) {
            Text("已经留在本机")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.elsepageAccent)
            Text(model.reflection?.originalText ?? model.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(model.messages) { message in
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.author == .user ? "你继续说" : "回应")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if message.author == .agent {
                        AgentMarkdownText(
                            content: message.content,
                            provenance: model.responseProvenance[message.id] ?? .init(evidence: [], citations: []),
                            openCitation: openCitation
                        )
                    } else {
                        Text(message.content).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let provenance = model.responseProvenance[message.id] {
                    let citedIDs = Set(provenance.citations.map(\.evidenceID))
                    let cited = provenance.evidence.filter { citedIDs.contains($0.id) }
                    let shown = cited.isEmpty ? provenance.evidence : cited
                    if !shown.isEmpty {
                        DisclosureGroup("本次使用了 \(shown.count) 处阅读数据") {
                            ForEach(shown) { evidence in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(evidence.title ?? evidence.kind.title).font(.caption.weight(.semibold))
                                    Text(evidence.excerpt).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                                    if evidence.locator != nil {
                                        Button("回到原文") { openCitation?(evidence) }.font(.caption)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                        }
                        .font(.footnote)
                    }
                }
            }
            if !model.streamingResponse.isEmpty {
                AgentMarkdownText(content: model.streamingResponse)
                    .foregroundStyle(.secondary)
            } else if model.isResponding {
                ProgressView("正在回应…")
            }
            if let connected = model.connectedReflection {
                VStack(alignment: .leading, spacing: 4) {
                    Text("过去的你")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.elsepageAccent)
                    Text(connected.originalText).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            if let notice = model.agentNotice {
                Text(notice).font(.footnote).foregroundStyle(.secondary)
            }
            if model.messages.contains(where: { $0.author == .agent }) {
                Divider()
                TextField("继续聊聊…", text: $model.followUpText, axis: .vertical)
                    .lineLimit(2...6)
                Button("发送") { Task { await model.continueDiscussion() } }
                    .buttonStyle(.bordered)
                    .disabled(model.isResponding || model.followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
            Text(bookline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(durationLine)
                .font(.system(.title2, design: .serif, weight: .semibold))
            if let progress = model.summary.progressDelta, progress > 0 {
                Text("这次前进了 \(progress, format: .percent.precision(.fractionLength(0)))。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if model.summary.session.highlightCount > 0 || model.summary.session.noteCount > 0 {
                Text(annotationLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let quote = model.locator.textHighlight, !quote.isEmpty {
                Text(quote)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
    }

    private var bookline: String { "刚刚读了《\(model.book.title)》" }

    private var durationLine: String {
        guard model.summary.session.endedAt != nil else { return "这句话让你想到什么？" }
        let minutes = Int((model.summary.wallClockDuration / 60).rounded(.down))
        return minutes > 0 ? "这一段约 \(minutes) 分钟" : "这一段阅读结束了"
    }

    private var annotationLine: String {
        let highlights = model.summary.session.highlightCount
        let notes = model.summary.session.noteCount
        switch (highlights, notes) {
        case (let h, let n) where h > 0 && n > 0: return "留下了 \(h) 个高亮和 \(n) 条批注。"
        case (let h, _) where h > 0: return "留下了 \(h) 个高亮。"
        case (_, let n) where n > 0: return "留下了 \(n) 条批注。"
        default: return ""
        }
    }
}

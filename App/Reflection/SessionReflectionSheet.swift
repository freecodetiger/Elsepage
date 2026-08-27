import AchievementCore
import AgentRuntime
import LibraryCore
import Observation
import ReaderCore
import ReaderAgent
import ReadingSessionCore
import ReflectionCore
import SwiftUI

/// Feature-scoped state for the local-first reflection prompt.
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
    let linkedHighlightIDs: [UUID]
    private let submission: TextReflectionSubmissionService
    private let voiceSubmission: VoiceReflectionSubmissionService
    private let reflectionRepository: any ReflectionRepository
    private let readerAgent: ReaderAgent
    private let makePolishService: (@MainActor () async -> TranscriptPolishService?)?
    let achievements: AchievementModel?
    /// Built lazily by `refreshPolish()` whenever the sheet appears, so a provider
    /// configured after launch is picked up on the next reflection sheet.
    private(set) var polishService: TranscriptPolishService?
    private let draftID = ReflectionID()

    var text = "" {
        didSet {
            // A cleared editor is no longer a voice reflection: fall back to plain text so
            // "record voice, delete it all, type text" saves as `.text`.
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                inputKind = .text
            }
        }
    }
    /// Raw audio file name (inside Documents/Reflections) when the user opted to save it.
    var audioFileName: String?
    private(set) var inputKind: ReflectionInputKind = .text
    private(set) var state: SubmissionState = .editing
    private(set) var reflection: Reflection?
    private(set) var messages: [ReflectionMessage] = []
    private(set) var responseProvenance: [UUID: AgentResponseProvenance] = [:]
    private(set) var streamingResponse = ""
    private(set) var connectedReflection: Reflection?
    private(set) var isResponding = false
    private(set) var contextDisclosure: ContextDisclosure?
    /// The user's words captured right before an AI polish, so the raw version is
    /// never lost (PRD P2). Non-nil means a polish has been applied.
    private(set) var rawTranscript: String?
    var followUpText = ""
    var agentNotice: String?
    var errorMessage: String?
    private var followUpID = UUID()

    init(
        book: Book,
        summary: SessionEndingSummary,
        locator: BookLocator,
        linkedHighlightIDs: [UUID] = [],
        reflectionRepository: any ReflectionRepository,
        readerAgent: ReaderAgent,
        makePolishService: (@MainActor () async -> TranscriptPolishService?)? = nil,
        achievements: AchievementModel? = nil
    ) {
        self.book = book
        self.summary = summary
        self.locator = locator
        self.linkedHighlightIDs = linkedHighlightIDs
        self.reflectionRepository = reflectionRepository
        self.readerAgent = readerAgent
        self.makePolishService = makePolishService
        self.achievements = achievements
        submission = TextReflectionSubmissionService(repository: reflectionRepository)
        voiceSubmission = VoiceReflectionSubmissionService(repository: reflectionRepository)
    }

    /// Re-evaluates provider availability so the polish button appears as soon as a
    /// key is configured, not only when the app was launched with one.
    func refreshPolish() async {
        guard let makePolishService else { return }
        polishService = await makePolishService()
    }

    /// A polish button is offered once a provider is configured and there is text.
    var canPolish: Bool {
        polishService != nil && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The AI-optimized version of the user's words (one tier: 忠实+清晰). Kept
    /// separate from the editor so 查看我的原话 can swap without losing either side.
    private(set) var optimizedText: String?
    /// Whether the editor currently shows the optimized version instead of the raw words.
    private(set) var showingOptimized = false
    /// One auto-optimization per draft, so a second recording never overwrites the
    /// first raw capture (rawTranscript stays the true original).
    private(set) var hasAutoOptimized = false
    var isOptimizing = false

    /// 录音结束后的自动优化:说得乱没关系,AI 把表达理顺(忠实+清晰),原话始终可切回。
    func autoOptimizeAfterRecording() async {
        guard !hasAutoOptimized, polishService != nil,
              text.trimmingCharacters(in: .whitespacesAndNewlines).count >= Self.autoOptimizeMinimumCharacters else { return }
        hasAutoOptimized = true
        await applyOptimization()
    }

    /// 表达优化(唯一档位):忠于原意,把表达变清楚。保留原始转写为 source of truth。
    func applyOptimization() async {
        let current = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty, let polishService else { return }
        if rawTranscript == nil {
            rawTranscript = text
        }
        isOptimizing = true
        defer { isOptimizing = false }
        do {
            let optimized = try await polishService.polish(current)
            guard !optimized.isEmpty else { return }
            optimizedText = optimized
            text = optimized
            showingOptimized = true
        } catch {
            errorMessage = "优化暂不可用，已保留你的原话。"
        }
    }

    func showRaw() {
        guard let rawTranscript, showingOptimized else { return }
        text = rawTranscript
        showingOptimized = false
    }

    func showOptimized() {
        guard let optimizedText, !showingOptimized else { return }
        text = optimizedText
        showingOptimized = true
    }

    private static let autoOptimizeMinimumCharacters = 20

    var canSubmit: Bool {
        state == .editing && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func submit() async -> Reflection? {
        guard canSubmit else { return nil }
        state = .saving
        do {
            let reflection: Reflection
            if inputKind == .voiceTranscript {
                reflection = try await voiceSubmission.submit(.init(
                    id: draftID, bookID: book.id, sessionID: summary.session.id, locator: locator,
                    editedTranscript: rawTranscript ?? text,
                    audioFileName: audioFileName,
                    polishedText: showingOptimized ? text : nil,
                    linkedHighlightIDs: linkedHighlightIDs
                ))
            } else {
                reflection = try await submission.submit(.init(
                    id: draftID, bookID: book.id, sessionID: summary.session.id, locator: locator,
                    originalText: rawTranscript ?? text,
                    polishedText: showingOptimized ? text : nil,
                    linkedHighlightIDs: linkedHighlightIDs
                ))
            }
            self.reflection = reflection
            state = .saved
            if let achievements {
                await achievements.handle(.init(reflection: reflection, connectedSource: nil, now: Date()))
            }
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

    func markVoiceTranscript() {
        guard state == .editing else { return }
        // No voice content left (e.g. an empty transcription) is not a voice reflection.
        inputKind = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .text : .voiceTranscript
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
        contextDisclosure = nil
        defer { isResponding = false }
        for await event in stream {
            switch event {
            case .started:
                break
            case .contextPrepared(let connection):
                if let connection {
                    connectedReflection = try? await reflectionRepository.reflection(id: connection.sourceReflectionID)
                    if let connectedReflection, let reflection, let achievements {
                        await achievements.handle(.init(
                            reflection: reflection,
                            connectedSource: .init(reflection: connectedReflection, bookID: connectedReflection.bookID),
                            now: Date()
                        ))
                    }
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
            case .contextDisclosed(let disclosure):
                contextDisclosure = disclosure
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
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.large) {
                        header
                        if model.reflection == nil { editor } else { conversation }
                    }
                    .padding(ElsepageTheme.Spacing.page)
                }
                .background(Color.elsepageBackground)

                if model.reflection == nil {
                    Divider()
                    VoiceReflectionControls(
                        editableText: Binding(
                            get: { model.text },
                            set: { model.text = $0 }
                        ),
                        audioFileName: Binding(
                            get: { model.audioFileName },
                            set: { model.audioFileName = $0 }
                        ),
                        canPolish: model.canPolish,
                        onPolish: { await model.applyOptimization() },
                        onAutoPolish: { await model.autoOptimizeAfterRecording() },
                        onVoiceTranscript: { model.markVoiceTranscript() }
                    )
                    .padding(.horizontal, ElsepageTheme.Spacing.page)
                    .padding(.vertical, ElsepageTheme.Spacing.medium)
                    .background(Color.elsepageBackground)
                }
            }
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
            .task { await model.refreshPolish() }
            .achievementToast(model.achievements)
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
            if model.optimizedText != nil {
                optimizationToggle
            }
            if model.isOptimizing {
                HStack(spacing: ElsepageTheme.Spacing.small) {
                    ProgressView().controlSize(.small)
                    Text("正在优化你的表达…").font(.footnote).foregroundStyle(.secondary)
                }
            }
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

    /// 原话 ↔ 优化版切换。优化始终忠实原意(PRD P2),原话一键可回。
    private var optimizationToggle: some View {
        HStack(spacing: ElsepageTheme.Spacing.small) {
            Label(
                model.showingOptimized ? "AI 优化版" : "我的原话",
                systemImage: model.showingOptimized ? "wand.and.stars" : "text.quote"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.elsepageAccent)
            Spacer()
            Button(model.showingOptimized ? "查看我的原话" : "查看 AI 优化版") {
                if model.showingOptimized { model.showRaw() } else { model.showOptimized() }
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .accessibilityLabel("切换原话与优化版")
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.medium) {
            Text("已经留在本机")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.elsepageAccent)
            Text(model.reflection?.displayText ?? model.text)
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
            if let disclosure = model.contextDisclosure {
                Label(disclosureLine(disclosure), systemImage: "doc.text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
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

    private func disclosureLine(_ disclosure: ContextDisclosure) -> String {
        var parts: [String] = []
        if disclosure.retrievedBookEvidenceCount > 0 {
            parts.append("参考了已读部分 \(disclosure.retrievedBookEvidenceCount) 处书内内容")
        } else if disclosure.includedNearbyPassage {
            parts.append("参考了你正在读的这段原文")
        } else {
            parts.append("回应仅基于你的想法与对话")
        }
        if disclosure.connectedReflectionID != nil {
            parts.append("连接过去的一则想法")
        }
        parts.append("准备用时 \(Self.durationText(disclosure.routingDuration + disclosure.retrievalDuration))")
        return parts.joined(separator: "，")
    }

    private static func durationText(_ duration: Duration) -> String {
        let components = duration.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
        return String(format: "%.1f 秒", seconds)
    }
}

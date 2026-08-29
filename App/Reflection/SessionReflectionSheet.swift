import AchievementCore
import AgentRuntime
import LibraryCore
import Observation
import ReaderCore
import ReaderAgent
import ReadingSessionCore
import ReflectionCore
import SwiftUI
import UIKit

/// Keeps UIKit's live editing buffer authoritative while a keyboard is active.
/// This prevents a stale SwiftUI model value from restoring text that a
/// third-party keyboard cleared without emitting an intermediate change event.
struct ReflectionTextSynchronization {
    private(set) var isEditing = false
    private var lastCommittedText: String

    init(initialText: String) {
        lastCommittedText = initialText
    }

    mutating func editingBegan() {
        isEditing = true
    }

    @discardableResult
    mutating func userTextDidChange(_ uiText: String, hasMarkedText: Bool) -> String? {
        guard !hasMarkedText else { return nil }
        lastCommittedText = uiText
        return uiText
    }

    mutating func editingEnded(uiText: String) -> String {
        isEditing = false
        lastCommittedText = uiText
        return uiText
    }

    mutating func modelTextToApply(
        modelText: String,
        uiText: String,
        hasMarkedText: Bool
    ) -> String? {
        guard !hasMarkedText, modelText != uiText else { return nil }
        if !isEditing {
            lastCommittedText = modelText
            return modelText
        }
        // While editing, only accept a genuine external model update when the
        // UIKit buffer still equals the last value it reported. If they differ,
        // UIKit has newer text (for example a silent third-party keyboard clear).
        guard uiText == lastCommittedText, modelText != lastCommittedText else { return nil }
        lastCommittedText = modelText
        return modelText
    }
}

enum ReflectionComposerPolicy {
    static let minimumEditorHeight: CGFloat = 44

    static func naturalHeight(_ proposed: CGFloat, minimum: CGFloat = minimumEditorHeight) -> CGFloat {
        max(proposed, minimum)
    }

    static func canSend(text: String, isRecording: Bool, isResponding: Bool, hasMarkedText: Bool) -> Bool {
        !isRecording && !isResponding && !hasMarkedText
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum ReflectionTextPresentationPolicy {
    static func showsPlaceholder(text: String, hasMarkedText: Bool) -> Bool {
        text.isEmpty && !hasMarkedText
    }
}

struct ReflectionDraft: Equatable {
    enum Version: Equatable {
        case original
        case polished
    }

    private(set) var originalText: String
    private(set) var polishedText: String?
    private(set) var selectedVersion: Version
    private(set) var revision: UInt64

    init(
        originalText: String = "",
        polishedText: String? = nil,
        selectedVersion: Version = .original,
        revision: UInt64 = 0
    ) {
        self.originalText = originalText
        self.polishedText = polishedText
        self.selectedVersion = polishedText == nil ? .original : selectedVersion
        self.revision = revision
    }

    var selectedText: String {
        switch selectedVersion {
        case .original: originalText
        case .polished: polishedText ?? originalText
        }
    }

    var canSend: Bool {
        !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    mutating func updateSelectedText(_ text: String) {
        switch selectedVersion {
        case .original:
            updateOriginalText(text)
        case .polished:
            polishedText = text
            revision &+= 1
        }
    }

    mutating func updateOriginalText(_ text: String) {
        guard originalText != text || polishedText != nil || selectedVersion != .original else { return }
        originalText = text
        polishedText = nil
        selectedVersion = .original
        revision &+= 1
    }

    mutating func applyPolishedText(_ text: String) {
        guard !text.isEmpty else { return }
        polishedText = text
        selectedVersion = .polished
        revision &+= 1
    }

    mutating func select(_ version: Version) {
        guard version != .polished || polishedText != nil else { return }
        selectedVersion = version
    }

    mutating func clear() {
        guard !originalText.isEmpty || polishedText != nil else { return }
        originalText = ""
        polishedText = nil
        selectedVersion = .original
        revision &+= 1
    }

    mutating func takeSelectedTextForSending() -> String? {
        let text = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        clear()
        return text
    }
}

struct PendingReflectionMessage: Identifiable, Equatable {
    enum DeliveryState: Equatable {
        case sending
        case failed
    }

    let id: UUID
    let content: String
    var deliveryState: DeliveryState
}

struct ReflectionTextEditor: View {
    @Binding var text: String
    let placeholder: String
    var isEditable = true
    var minimumHeight: CGFloat = 88
    var focus: Binding<Bool>?
    var markedText: Binding<Bool>?
    var onHeightChange: (CGFloat) -> Void = { _ in }
    @State private var measuredHeight: CGFloat = 0
    @State private var localMarkedText = false

    var body: some View {
        ReflectionUIKitTextView(
            text: $text,
            placeholder: placeholder,
            isEditable: isEditable,
            isFocused: focus ?? .constant(false),
            managesFocus: focus != nil,
            hasMarkedText: markedText ?? $localMarkedText,
            measuredHeight: $measuredHeight,
            minimumHeight: minimumHeight
        )
        .frame(maxWidth: .infinity)
        .frame(height: measuredHeight == 0 ? minimumHeight : measuredHeight)
        .onChange(of: measuredHeight) { _, height in onHeightChange(height) }
    }
}

private final class ReflectionUITextView: UITextView {
    private let placeholderLabel = UILabel()
    private var lastLayoutWidth: CGFloat = 0
    var onWidthChanged: (() -> Void)?

    var placeholder = "" {
        didSet { placeholderLabel.text = placeholder }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.numberOfLines = 0
        placeholderLabel.isAccessibilityElement = false
        addSubview(placeholderLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let x = textContainerInset.left + textContainer.lineFragmentPadding
        let y = textContainerInset.top
        let width = max(0, bounds.width - x - textContainerInset.right - textContainer.lineFragmentPadding)
        let placeholderSize = placeholderLabel.sizeThatFits(.init(width: width, height: .greatestFiniteMagnitude))
        placeholderLabel.frame = .init(x: x, y: y, width: width, height: placeholderSize.height)
        if bounds.width > 0, bounds.width != lastLayoutWidth {
            lastLayoutWidth = bounds.width
            onWidthChanged?()
        }
    }

    func setPlaceholderVisible(_ visible: Bool) {
        placeholderLabel.isHidden = !visible
    }
}

private struct ReflectionUIKitTextView: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isEditable: Bool
    @Binding var isFocused: Bool
    let managesFocus: Bool
    @Binding var hasMarkedText: Bool
    @Binding var measuredHeight: CGFloat
    let minimumHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text, isFocused: $isFocused, measuredHeight: $measuredHeight,
            hasMarkedText: $hasMarkedText,
            initialText: text, minimumHeight: minimumHeight
        )
    }

    func makeUIView(context: Context) -> ReflectionUITextView {
        let view = ReflectionUITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = .init(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.lineFragmentPadding = 5
        view.textContainer.widthTracksTextView = true
        view.textContainer.lineBreakMode = .byWordWrapping
        view.textContainer.maximumNumberOfLines = 0
        view.isScrollEnabled = false
        view.alwaysBounceVertical = false
        view.showsVerticalScrollIndicator = false
        view.alwaysBounceHorizontal = false
        view.showsHorizontalScrollIndicator = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.text = text
        view.placeholder = placeholder
        view.isEditable = isEditable
        view.onWidthChanged = { [weak coordinator = context.coordinator, weak view] in
            guard let coordinator, let view else { return }
            coordinator.updateHeight(of: view, minimum: minimumHeight)
        }
        context.coordinator.updatePresentation(of: view, reportsMarkedText: false)
        context.coordinator.minimumHeight = minimumHeight
        context.coordinator.updateHeight(of: view, minimum: minimumHeight)
        return view
    }

    func updateUIView(_ view: ReflectionUITextView, context: Context) {
        if !isEditable, view.isFirstResponder {
            view.resignFirstResponder()
        }
        view.isEditable = isEditable
        view.placeholder = placeholder
        if managesFocus {
            if isFocused, !view.isFirstResponder, isEditable { view.becomeFirstResponder() }
            if !isFocused, view.isFirstResponder { view.resignFirstResponder() }
        }
        if let modelText = context.coordinator.synchronization.modelTextToApply(
            modelText: text,
            uiText: view.text,
            hasMarkedText: view.markedTextRange != nil
        ) {
            view.text = modelText
        }
        context.coordinator.updatePresentation(of: view, reportsMarkedText: false)
        context.coordinator.updateHeight(of: view, minimum: minimumHeight)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        private let text: Binding<String>
        private let isFocused: Binding<Bool>
        private let measuredHeight: Binding<CGFloat>
        private let hasMarkedText: Binding<Bool>
        var synchronization: ReflectionTextSynchronization
        var minimumHeight: CGFloat
        private var measurementGeneration: UInt64 = 0

        init(
            text: Binding<String>, isFocused: Binding<Bool>, measuredHeight: Binding<CGFloat>,
            hasMarkedText: Binding<Bool>,
            initialText: String, minimumHeight: CGFloat
        ) {
            self.text = text
            self.isFocused = isFocused
            self.measuredHeight = measuredHeight
            self.hasMarkedText = hasMarkedText
            self.minimumHeight = minimumHeight
            synchronization = .init(initialText: initialText)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            synchronization.editingBegan()
            if !isFocused.wrappedValue { isFocused.wrappedValue = true }
            updatePresentation(of: textView)
        }

        func textViewDidChange(_ textView: UITextView) {
            if let current = synchronization.userTextDidChange(
                textView.text,
                hasMarkedText: textView.markedTextRange != nil
            ), text.wrappedValue != current {
                text.wrappedValue = current
            }
            updateHeight(of: textView, minimum: minimumHeight)
            updatePresentation(of: textView)
            ensureCaretVisible(in: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            updatePresentation(of: textView)
            ensureCaretVisible(in: textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            let final = synchronization.editingEnded(uiText: textView.text)
            if text.wrappedValue != final {
                text.wrappedValue = final
            }
            if isFocused.wrappedValue { isFocused.wrappedValue = false }
            updatePresentation(of: textView)
        }

        func updatePresentation(of textView: UITextView, reportsMarkedText: Bool = true) {
            let marked = textView.markedTextRange != nil
            if reportsMarkedText, hasMarkedText.wrappedValue != marked {
                hasMarkedText.wrappedValue = marked
            }
            (textView as? ReflectionUITextView)?.setPlaceholderVisible(
                ReflectionTextPresentationPolicy.showsPlaceholder(
                    text: textView.text,
                    hasMarkedText: marked
                )
            )
        }

        func updateHeight(of textView: UITextView, minimum: CGFloat) {
            guard textView.bounds.width > 0 else { return }
            let proposed = textView.sizeThatFits(.init(width: textView.bounds.width, height: .greatestFiniteMagnitude)).height
            let height = ReflectionComposerPolicy.naturalHeight(proposed, minimum: minimum)
            guard abs(measuredHeight.wrappedValue - height) >= 0.5 else { return }
            let measuredWidth = textView.bounds.width
            let measuredText = textView.text
            measurementGeneration &+= 1
            let generation = measurementGeneration
            let measuredHeight = measuredHeight
            Task { @MainActor [weak self, weak textView] in
                guard let self, let textView,
                      generation == self.measurementGeneration,
                      abs(textView.bounds.width - measuredWidth) < 0.5,
                      textView.text == measuredText else { return }
                if abs(measuredHeight.wrappedValue - height) >= 0.5 {
                    measuredHeight.wrappedValue = height
                }
                self.ensureCaretVisible(in: textView)
            }
        }

        private func ensureCaretVisible(in textView: UITextView) {
            guard textView.isFirstResponder,
                  let selection = textView.selectedTextRange else { return }
            let caret = textView.caretRect(for: selection.end).insetBy(dx: 0, dy: -16)
            Task { @MainActor [weak textView] in
                guard let textView else { return }
                var ancestor = textView.superview
                while let view = ancestor {
                    if let scrollView = view as? UIScrollView {
                        let rect = textView.convert(caret, to: scrollView)
                        scrollView.scrollRectToVisible(rect, animated: true)
                        return
                    }
                    ancestor = view.superview
                }
            }
        }
    }
}

/// FIX-01 (PRD §21.5): counts one user-initiated agent discussion against the
/// reflection's reading session. Backed by `ReadingSessionService` in the app
/// graph; optional so previews and tests can omit it.
typealias AgentDiscussionRecorder = @MainActor (ReadingSessionID) async -> Void

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
    /// Persisted against the session the moment the user's submission opens the
    /// Agent conversation (FIX-01).
    let recordAgentDiscussion: AgentDiscussionRecorder?
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
    private(set) var conversation: ReflectionConversationModel?
    /// The user's words captured right before an AI polish, so the raw version is
    /// never lost (PRD P2). Non-nil means a polish has been applied.
    private(set) var rawTranscript: String?
    var errorMessage: String?

    init(
        book: Book,
        summary: SessionEndingSummary,
        locator: BookLocator,
        linkedHighlightIDs: [UUID] = [],
        reflectionRepository: any ReflectionRepository,
        readerAgent: ReaderAgent,
        makePolishService: (@MainActor () async -> TranscriptPolishService?)? = nil,
        achievements: AchievementModel? = nil,
        recordAgentDiscussion: AgentDiscussionRecorder? = nil
    ) {
        self.book = book
        self.summary = summary
        self.locator = locator
        self.linkedHighlightIDs = linkedHighlightIDs
        self.reflectionRepository = reflectionRepository
        self.readerAgent = readerAgent
        self.makePolishService = makePolishService
        self.achievements = achievements
        self.recordAgentDiscussion = recordAgentDiscussion
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
            conversation = ReflectionConversationModel(
                reflection: reflection,
                repository: reflectionRepository,
                readerAgent: readerAgent,
                makePolishService: makePolishService,
                achievements: achievements,
                recordAgentDiscussion: recordAgentDiscussion
            )
            state = .saved
            // Reflection 完成 (PRD §10.4): the output is durable, celebrate quietly.
            Haptics.reflectionSaved()
            // The submission opens the Agent conversation: one user-initiated
            // discussion (FIX-01). Local-first — the save above is already durable.
            await recordAgentDiscussion?(summary.session.id)
            if let achievements {
                await achievements.handle(.reflection(reflection, connectedSource: nil, now: Date()))
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
        await conversation?.requestAgentReply()
    }
}

/// Shared state for one long-lived Reflection conversation. Both the reading-end
/// flow and Thoughts use this module so persistence, Agent streaming, retries,
/// and stack-ordered deletion have one interface and one implementation.
@MainActor @Observable
final class ReflectionConversationModel: Identifiable {
    nonisolated let id: ReflectionID
    let reflection: Reflection
    private let repository: any ReflectionRepository
    private let readerAgent: ReaderAgent
    private let achievements: AchievementModel?
    private let makePolishService: (@MainActor () async -> TranscriptPolishService?)?
    private var polishService: TranscriptPolishService?
    /// Persisted each time the user sends a follow-up (FIX-01).
    let recordAgentDiscussion: AgentDiscussionRecorder?

    private(set) var messages: [ReflectionMessage] = []
    private(set) var responseProvenance: [UUID: AgentResponseProvenance] = [:]
    private(set) var streamingResponse = ""
    private(set) var connectedReflection: Reflection?
    private(set) var isResponding = false
    private(set) var isPolishing = false
    private(set) var contextDisclosure: ContextDisclosure?
    private(set) var isDeleted = false
    private(set) var pendingUserMessage: PendingReflectionMessage?
    var draft = ReflectionDraft()
    var followUpText: String {
        get { draft.selectedText }
        set { draft.updateSelectedText(newValue) }
    }
    var agentNotice: String?
    var errorMessage: String?
    private var followUpID = UUID()

    init(
        reflection: Reflection,
        repository: any ReflectionRepository,
        readerAgent: ReaderAgent,
        makePolishService: (@MainActor () async -> TranscriptPolishService?)? = nil,
        achievements: AchievementModel? = nil,
        recordAgentDiscussion: AgentDiscussionRecorder? = nil
    ) {
        id = reflection.id
        self.reflection = reflection
        self.repository = repository
        self.readerAgent = readerAgent
        self.makePolishService = makePolishService
        self.achievements = achievements
        self.recordAgentDiscussion = recordAgentDiscussion
    }

    var latestUserMessageID: UUID? {
        messages.last(where: { $0.author == .user })?.id
    }

    var canDeleteRoot: Bool { latestUserMessageID == nil }

    var canPolish: Bool {
        polishService != nil && !draft.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func load() async {
        if let makePolishService {
            polishService = await makePolishService()
        }
        do {
            try await reloadMessages()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func polishDraft() async {
        let original = draft.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty, let polishService, !isPolishing else { return }
        isPolishing = true
        defer { isPolishing = false }
        do {
            let polished = try await polishService.polish(original)
            guard !polished.isEmpty else { return }
            draft.applyPolishedText(polished)
        } catch {
            errorMessage = "整理暂不可用，已保留你的原话。"
        }
    }

    func requestAgentReply() async {
        guard !isResponding, !isDeleted else { return }
        await consume(readerAgent.respond(to: reflection.id))
    }

    func send() async {
        guard !isResponding, !isDeleted, pendingUserMessage == nil,
              let text = draft.takeSelectedTextForSending() else { return }
        let id = followUpID
        followUpID = UUID()
        pendingUserMessage = .init(id: id, content: text, deliveryState: .sending)
        await deliverPendingMessage(id: id, text: text)
    }

    func retryPendingSend() async {
        guard !isResponding, !isDeleted,
              let pendingUserMessage,
              pendingUserMessage.deliveryState == .failed else { return }
        self.pendingUserMessage?.deliveryState = .sending
        await deliverPendingMessage(id: pendingUserMessage.id, text: pendingUserMessage.content)
    }

    private func deliverPendingMessage(id: UUID, text: String) async {
        await consume(readerAgent.continueDiscussion(on: reflection.id, messageID: id, text: text))
        if messages.contains(where: { $0.id == id }) {
            pendingUserMessage = nil
            // The follow-up persisted: one user-initiated discussion (FIX-01), and
            // the user's own words are now in the thread (Questioner signal).
            if let sessionID = reflection.sessionID {
                await recordAgentDiscussion?(sessionID)
            }
            if let achievements {
                await achievements.handle(.reflection(reflection, connectedSource: nil, now: Date()))
            }
        } else if pendingUserMessage?.id == id {
            pendingUserMessage?.deliveryState = .failed
        }
    }

    /// Returns true only when the root Reflection was deleted and the whole
    /// conversation should disappear from its presenting UI.
    func deleteLatestUserTurn() async -> Bool {
        guard !isResponding, !isDeleted else { return false }
        do {
            switch try await repository.deleteLatestUserTurn(in: reflection.id) {
            case .deletedFollowUp:
                try await reloadMessages()
                agentNotice = nil
                contextDisclosure = nil
                return false
            case .deletedConversation:
                deleteAudioFileIfNeeded()
                messages = []
                responseProvenance = [:]
                isDeleted = true
                return true
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
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
                    connectedReflection = try? await repository.reflection(id: connection.sourceReflectionID)
                    if let connectedReflection, let achievements {
                        await achievements.handle(.reflection(
                            reflection,
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
                streamingResponse = ""
            case .contextDisclosed(let disclosure):
                contextDisclosure = disclosure
            case .cancelled:
                agentNotice = nil
            case .failed(.providerNotConfigured):
                agentNotice = "你的表达已经保存在本机。配置模型后可以重新邀请回应。"
            case .failed(let failure):
                agentNotice = Self.message(for: failure)
            }
        }
        do {
            try await reloadMessages()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadMessages() async throws {
        messages = try await repository.messages(for: reflection.id)
        if let pendingUserMessage,
           messages.contains(where: { $0.id == pendingUserMessage.id }) {
            self.pendingUserMessage = nil
        }
        var loaded: [UUID: AgentResponseProvenance] = [:]
        for message in messages where message.author == .agent {
            loaded[message.id] = try await repository.provenance(for: message.id)
        }
        responseProvenance = loaded
    }

    private func deleteAudioFileIfNeeded() {
        guard let name = reflection.audioFileName else { return }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Reflections", isDirectory: true)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    private static func withoutCitationBlock(_ content: String) -> String {
        guard let range = content.range(of: "---CITATIONS---") else { return content }
        return String(content[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func message(for failure: ReaderAgentFailure) -> String {
        switch failure {
        case .missingReflection, .persistence: "表达已保存，但回应暂时无法继续。"
        case .providerNotConfigured: "表达已经保存在本机。"
        case .emptyResponse: "这次没有收到可显示的回应，可以稍后重试。"
        case .emptyUserMessage: "先写下一点想继续说的内容。"
        case .runtime(.authentication): "当前模型配置无法通过验证，表达仍已保存。"
        case .runtime(.rateLimited): "回应有点拥挤，可以稍后再试。"
        case .runtime(.network), .runtime(.providerUnavailable): "现在网络不可用，表达仍已保存在本机。"
        case .runtime(.malformedProviderResponse), .runtime(.budgetExceeded), .runtime(.unknown):
            "这次回应没有完成，表达仍已保存在本机。"
        }
    }
}

struct SessionReflectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: SessionReflectionModel
    let onSaved: @MainActor (Reflection) -> Void
    var openCitation: ((AgentResponseEvidence) -> Void)?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.reflection == nil {
                    ScrollView {
                        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.large) {
                            header
                            editor
                        }
                        .padding(ElsepageTheme.Spacing.page)
                    }
                    .background(Color.elsepageBackground)
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
                    .transition(.moment(reduceMotion))
                } else if let conversation = model.conversation {
                    ReflectionConversationView(
                        model: conversation,
                        header: AnyView(header),
                        openCitation: openCitation,
                        onConversationDeleted: { dismiss() }
                    )
                    .transition(.moment(reduceMotion))
                }
            }
            // Reflection 完成 (PRD §10.3): the editor hands over to the saved
            // conversation with a quiet cross-fade.
            .animation(ElsepageTheme.Motion.moment(reduceMotion), value: model.reflection?.id)
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
        .presentationBackground(Color.elsepageBackground)
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
            ReflectionTextEditor(
                text: $model.text,
                placeholder: "写下一点此刻真正留下来的东西…",
                minimumHeight: 140
            )
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

struct ReflectionConversationView: View {
    @Bindable var model: ReflectionConversationModel
    var header: AnyView? = nil
    var openCitation: ((AgentResponseEvidence) -> Void)?
    var onConversationDeleted: @MainActor () -> Void = {}
    @State private var confirmsDeletion = false
    @State private var isVoiceInputActive = false
    @State private var isComposerFocused = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.medium) {
                    if let header { header }
                    userTurn(title: "你的 Reflection", text: model.reflection.displayText, canDelete: model.canDeleteRoot)

            ForEach(model.messages) { message in
                Divider()
                VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
                    HStack {
                        Text(message.author == .user ? "你继续说" : "Agent 回应")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        if message.author == .user, message.id == model.latestUserMessageID {
                            deleteButton
                        }
                    }
                    if message.author == .agent {
                        AgentMarkdownText(
                            content: message.content,
                            provenance: model.responseProvenance[message.id] ?? .init(evidence: [], citations: []),
                            openCitation: openCitation
                        )
                    } else {
                        Text(message.content).fixedSize(horizontal: false, vertical: true)
                    }
                    provenance(for: message)
                }
            }

            if let pending = model.pendingUserMessage {
                Divider()
                VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
                    HStack {
                        Text("你继续说")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        switch pending.deliveryState {
                        case .sending:
                            Label("已发送", systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .failed:
                            Button("重新发送") {
                                Task { await model.retryPendingSend() }
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                    Text(pending.content).fixedSize(horizontal: false, vertical: true)
                }
                .id(pending.id)
            }

            if !model.streamingResponse.isEmpty {
                AgentMarkdownText(content: model.streamingResponse).foregroundStyle(.secondary)
            } else if model.isResponding {
                HStack(spacing: ElsepageTheme.Spacing.small) {
                    ProgressView().controlSize(.small)
                    Text("Agent 正在理解你的表达…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Color.clear.frame(height: 1).id("reflection-agent-response")
            if let connected = model.connectedReflection {
                VStack(alignment: .leading, spacing: 4) {
                    Text("过去的你").font(.caption.weight(.semibold)).foregroundStyle(Color.elsepageAccent)
                    Text(connected.originalText).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            if let notice = model.agentNotice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
            if let disclosure = model.contextDisclosure {
                Label(disclosureLine(disclosure), systemImage: "doc.text.magnifyingglass")
                    .font(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
            }

                    Divider()
                    ReflectionComposer(
                        model: model,
                        isVoiceInputActive: $isVoiceInputActive,
                        isFocused: $isComposerFocused
                    )

                    Color.clear.frame(height: 1).id("reflection-conversation-bottom")
                }
                .padding(ElsepageTheme.Spacing.page)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isComposerFocused { isComposerFocused = false }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .background(Color.elsepageBackground)
            .onChange(of: isComposerFocused) { _, focused in
                if focused {
                    withAnimation(.snappy(duration: 0.2)) {
                        proxy.scrollTo("reflection-conversation-bottom", anchor: .bottom)
                    }
                }
            }
            .onChange(of: model.messages.count) { _, _ in
                proxy.scrollTo("reflection-conversation-bottom", anchor: .bottom)
            }
            .onChange(of: model.pendingUserMessage?.id) { _, id in
                if let id {
                    withAnimation(.snappy(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: model.streamingResponse.isEmpty) { _, isEmpty in
                if !isEmpty { proxy.scrollTo("reflection-agent-response", anchor: .bottom) }
            }
        }
        .background(Color(uiColor: .secondarySystemBackground).ignoresSafeArea())
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await model.load() }
        .alert("删除这次 Reflection？", isPresented: $confirmsDeletion) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task {
                    if await model.deleteLatestUserTurn() { onConversationDeleted() }
                }
            }
        } message: {
            Text(model.canDeleteRoot
                 ? "这会删除整个会话及其中的 Agent 回应，且无法撤销。"
                 : "这会删除最新一条 Reflection，以及它之后的 Agent 回应。")
        }
        .alert("暂时无法完成操作", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) { Button("好") {} } message: { Text(model.errorMessage ?? "") }
    }

    private func userTurn(title: String, text: String, canDelete: Bool) -> some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(Color.elsepageAccent)
                Spacer()
                if canDelete { deleteButton }
            }
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) { confirmsDeletion = true } label: {
            Image(systemName: "trash")
        }
        .disabled(model.isResponding || isVoiceInputActive)
        .accessibilityLabel("删除最新一条 Reflection")
    }

    @ViewBuilder private func provenance(for message: ReflectionMessage) -> some View {
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
                        }.padding(.vertical, 3)
                    }
                }.font(.footnote)
            }
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
        if disclosure.connectedReflectionID != nil { parts.append("连接过去的一则想法") }
        return parts.joined(separator: "，")
    }
}

private struct ReflectionComposer: View {
    @Bindable var model: ReflectionConversationModel
    @Binding var isVoiceInputActive: Bool
    @Binding var isFocused: Bool
    @State private var hasMarkedText = false
    @State private var voiceNotice: String?
    @State private var clearedDraft: ReflectionDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
            if model.draft.polishedText != nil {
                Picker("草稿版本", selection: Binding(
                    get: { model.draft.selectedVersion },
                    set: { model.draft.select($0) }
                )) {
                    Text("我的原话").tag(ReflectionDraft.Version.original)
                    Text("整理版").tag(ReflectionDraft.Version.polished)
                }
                .pickerStyle(.segmented)
            }

            if isVoiceInputActive {
                HStack(spacing: ElsepageTheme.Spacing.small) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("正在聆听，你可以慢慢说完整")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            } else if let voiceNotice {
                Text(voiceNotice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ReflectionTextEditor(
                text: $model.followUpText,
                placeholder: isVoiceInputActive ? "正在等待你的表达…" : "继续写下你的 Reflection…",
                isEditable: !isVoiceInputActive,
                minimumHeight: ReflectionComposerPolicy.minimumEditorHeight,
                focus: $isFocused,
                markedText: $hasMarkedText
            )
            .frame(maxWidth: .infinity)

            HStack(spacing: ElsepageTheme.Spacing.small) {
                VoiceReflectionControls(
                    editableText: Binding(
                        get: { model.draft.originalText },
                        set: { model.draft.updateOriginalText($0) }
                    ),
                    audioFileName: Binding<String?>.constant(nil),
                    allowsAudioSaving: false,
                    style: .compactComposer,
                    onRecordingStateChange: { active in
                        isVoiceInputActive = active
                        if active { isFocused = false }
                    },
                    onFailureMessageChange: { voiceNotice = $0 }
                )
                .disabled(hasMarkedText)

                if model.canPolish, !isVoiceInputActive {
                    Button {
                        isFocused = false
                        Task { await model.polishDraft() }
                    } label: {
                        if model.isPolishing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("整理表达", systemImage: "wand.and.stars")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(hasMarkedText || model.isPolishing)
                }

                if model.draft.canSend, !isVoiceInputActive {
                    Menu {
                        Button("清空全文", role: .destructive) {
                            clearedDraft = model.draft
                            model.draft.clear()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("更多草稿操作")
                }

                Spacer()
                if !isVoiceInputActive { sendButton }
            }

            if let clearedDraft {
                HStack {
                    Text("已清空全部内容").font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button("撤销") {
                        model.draft = clearedDraft
                        self.clearedDraft = nil
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
        }
        .padding(.vertical, ElsepageTheme.Spacing.small)
        .animation(.snappy(duration: 0.25), value: isVoiceInputActive)
    }

    private var sendButton: some View {
        Button {
            Haptics.followUpSent()
            Task { await model.send() }
        } label: {
            Image(systemName: "arrow.up")
                .font(.body.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .accessibilityLabel("发送")
        .disabled(!ReflectionComposerPolicy.canSend(
            text: model.followUpText,
            isRecording: isVoiceInputActive,
            isResponding: model.isResponding,
            hasMarkedText: hasMarkedText
        ) || model.pendingUserMessage != nil)
    }
}

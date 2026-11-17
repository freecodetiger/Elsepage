import ReaderAgent
import ReaderCore
import ReflectionCore
import SwiftUI

struct ReaderHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var model: ReaderHelpModel
    let openCitation: (AgentResponseEvidence) -> Void
    let onOpenSettings: (() -> Void)?

    @FocusState private var composerFocused: Bool
    @State private var selectedDetent: PresentationDetent = .height(300)
    @State private var confirmsDiscard = false

    private static let bottomAnchor = "conversation-bottom"

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        // Streaming updates every ~50ms; a scroll without animation keeps the
        // newest token visible instead of queueing overlapping animations.
        proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: ElsepageTheme.Spacing.medium) {
                        quoteCard
                        conversation
                        completedExtras
                        saveFeedback
                        disclosure
                        saveError
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchor)
                    }
                    .padding(ElsepageTheme.Spacing.medium)
                }
                .scrollDismissesKeyboard(.interactively)
                // Follow the new question as soon as it is sent, then follow
                // the streamed tokens. Do not scroll when the stream completes:
                // the source list and answer actions sit below the answer, and
                // jumping to them would hide the very text the reader asked for.
                .onChange(of: model.activeQuestion) { _, question in
                    if question != nil { scrollToBottom(proxy) }
                }
                .onChange(of: model.streamingContent) { _, text in
                    guard !text.isEmpty else { return }
                    scrollToBottom(proxy)
                }
            }

            Divider()
            composer
        }
        .background(Color.elsepageBackground)
        .presentationDetents([.height(184), .height(300), .medium, .large], selection: $selectedDetent)
        // No drag indicator: this temporary thread is deliberately not
        // swipe-dismissable, so the indicator would promise a gesture that
        // does nothing. Closing is explicit and confirmed when it has content.
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(true)
        .onAppear {
            // At accessibility sizes the quote card and composer need the
            // whole sheet; a 300pt detent clips the primary action.
            if dynamicTypeSize.isAccessibilitySize {
                selectedDetent = .large
            }
        }
        .onChange(of: model.saveNotice) { _, notice in
            // Reveal the newly persisted underline/highlight behind the sheet.
            if notice != nil, !dynamicTypeSize.isAccessibilitySize {
                selectedDetent = .height(184)
            }
        }
        .onChange(of: model.state) { _, state in
            // The 300pt sheet is sized for the quote and the first action; once
            // tokens arrive, give the answer enough room without taking the
            // whole page. Only expand from the initial detent, so a reader who
            // deliberately collapsed the sheet keeps their choice.
            if state == .streaming, selectedDetent == .height(300) {
                selectedDetent = .medium
            }
        }
        .onDisappear { model.cancel() }
        .confirmationDialog("丢弃这次问答？", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("继续问", role: .cancel) {}
            Button("丢弃并关闭", role: .destructive) {
                model.discard()
                dismiss()
            }
        } message: {
            Text("这次问答没有保存，关闭后不会保留。")
        }
    }

    private var hasThreadContent: Bool {
        !model.turns.isEmpty
            || model.activeQuestion != nil
            || !model.streamingContent.isEmpty
            || !model.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func requestClose() {
        if hasThreadContent {
            confirmsDiscard = true
        } else {
            model.discard()
            dismiss()
        }
    }

    private var header: some View {
        HStack(spacing: ElsepageTheme.Spacing.small) {
            VStack(alignment: .leading, spacing: 3) {
                Text("问 AI")
                    .font(.system(.headline, design: .serif))
                if let chapter = model.chapterTitle {
                    Text(chapter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                requestClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭并丢弃这次问答")
        }
        .padding(.leading, ElsepageTheme.Spacing.medium)
        .padding(.trailing, ElsepageTheme.Spacing.small)
        .padding(.vertical, ElsepageTheme.Spacing.small)
    }

    private var quoteCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("选中原文")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(model.selectedText)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text("回答只使用这段原文和你已经读过的部分。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("选中原文：\(model.selectedText)")
    }

    @ViewBuilder private var conversation: some View {
        ForEach(Array(model.turns.enumerated()), id: \.offset) { index, turn in
            turnBubble(
                turn,
                isLatestAgent: index == model.turns.count - 1
                    && turn.role == .agent
                    && model.state == .completed
            )
        }

        if let question = model.activeQuestion {
            userBubble(question)
        }

        switch model.state {
        case .idle:
            if model.turns.isEmpty {
                suggestion
            }
        case .preparing:
            statusRow("正在理解这句话和已读上下文…")
        case .streaming:
            if model.streamingContent.isEmpty {
                statusRow("正在回答…")
            } else {
                agentBubble(model.streamingContent, provenance: model.provenance)
            }
        case .completed:
            EmptyView()
        case .cancelled:
            stoppedRow
        case .failed(let message):
            failureCard(message)
        }
    }

    private var suggestion: some View {
        Button {
            model.explainSelection()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "text.magnifyingglass")
                Text("解释这段")
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .foregroundStyle(Color.elsepageInteractive)
            .background(Color.elsepageInteractive.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("向 AI 解释当前选中的文字")
    }

    @ViewBuilder private var completedExtras: some View {
        if model.state == .completed {
            sourceList
            answerActions
        }
    }

    @ViewBuilder private var sourceList: some View {
        if let provenance = model.provenance, !provenance.citations.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Divider()
                ForEach(Array(provenance.citations.enumerated()), id: \.offset) { index, citation in
                    if let evidence = provenance.evidence.first(where: { $0.id == citation.evidenceID }) {
                        if evidence.locator != nil {
                            Button {
                                handleCitation(evidence)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(AgentMarkdownText.superscript(index + 1))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.elsepageInteractive)
                                    Text(sourceTitle(for: evidence))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(ElsepageColor.textTertiary)
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("来源 \(index + 1)：\(sourceTitle(for: evidence))")
                        } else {
                            // Past thoughts have no locator. Do not render a
                            // button that promises a jump it cannot perform.
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(AgentMarkdownText.superscript(index + 1))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.elsepageInteractive)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sourceTitle(for: evidence))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("这条过去记录没有原文位置，无法跳转")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 44, alignment: .leading)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("来源 \(index + 1)：\(sourceTitle(for: evidence))，无法跳转")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var answerActions: some View {
        let isSaving = model.isSavingNote
        let isSaved = model.isSaved

        HStack(spacing: ElsepageTheme.Spacing.large) {
            Button {
                model.copyLatestAnswer()
            } label: {
                Label("复制", systemImage: "doc.on.doc")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)

            Button {
                Task { await model.saveLatestAnswer() }
            } label: {
                Label(
                    isSaving ? "保存中…" : (isSaved ? "已保存" : "存为笔记"),
                    systemImage: isSaving ? "clock" : (isSaved ? "checkmark.circle.fill" : "note.text.badge.plus")
                )
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(!model.canSave)

            Spacer()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .opacity(model.canSave || isSaved ? 1 : 0.55)
    }

    @ViewBuilder private var saveFeedback: some View {
        if let notice = model.saveNotice {
            Label(notice, systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.elsepageSuccess)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityLabel("笔记保存成功：\(notice)")
        }
    }

    private var disclosure: some View {
        Group {
            if model.isLatestResponseTruncated {
                Label("回答可能未完整显示，可以重试或继续追问。", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let disclosure = model.contextDisclosure {
                Label(disclosure, systemImage: "book.closed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var saveError: some View {
        if let error = model.saveError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(Color.elsepageDanger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("继续追问…", text: $model.composerText, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit { model.sendComposer() }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("继续追问")

                if model.isBusy {
                    Button {
                        model.cancel()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(ElsepageColor.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(ElsepageColor.surfaceSecondary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("停止回答")
                } else {
                    Button {
                        model.sendComposer()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(ElsepageColor.onAccent)
                            .frame(width: 44, height: 44)
                            .background(
                                model.canSubmitComposer ? ElsepageColor.accent : Color.secondary.opacity(0.28),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canSubmitComposer)
                    .accessibilityLabel("发送追问")
                }
            }
        }
        .padding(.horizontal, ElsepageTheme.Spacing.medium)
        .padding(.top, ElsepageTheme.Spacing.small)
        .padding(.bottom, ElsepageTheme.Spacing.small)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder private func turnBubble(_ turn: ReaderHelpTurn, isLatestAgent: Bool) -> some View {
        switch turn.role {
        case .user:
            userBubble(turn.content)
        case .agent:
            agentBubble(
                turn.content,
                provenance: isLatestAgent ? model.provenance : nil
            )
        }
    }

    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 32)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("你的问题：\(text)")
    }

    private func agentBubble(
        _ text: String,
        provenance: AgentResponseProvenance?
    ) -> some View {
        AgentMarkdownText(
            content: text,
            provenance: provenance ?? .init(evidence: [], citations: []),
            openCitation: handleCitation,
            citationStyle: .superscript
        )
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AI 回答")
    }

    private func sourceTitle(for evidence: AgentResponseEvidence) -> String {
        switch evidence.kind {
        case .nearbyPassage:
            return "原文 · 当前阅读位置"
        case .bookPassage:
            return "书中 · \(evidence.title ?? "已读内容")"
        case .pastReflection:
            return "过去 · 你的想法"
        }
    }

    private func handleCitation(_ evidence: AgentResponseEvidence) {
        // Keep the temporary thread alive. Collapsing the sheet reveals the
        // source while preserving the answer and its follow-up context.
        if !dynamicTypeSize.isAccessibilitySize {
            selectedDetent = .height(184)
        }
        openCitation(evidence)
    }

    private func statusRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// A failure is a state, not a line of gray text: it says what happened and
    /// offers the next action in place. The configuration failure routes to
    /// Settings instead of leaving the reader with a dead retry.
    private func failureCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: ElsepageSpacing.sm) {
            HStack(alignment: .top, spacing: ElsepageSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(ElsepageColor.warning)
                Text(message)
                    .font(ElsepageFont.subheadline)
                    .foregroundStyle(ElsepageColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: ElsepageSpacing.lg) {
                if model.canRetry {
                    Button("重试") { model.retry() }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                if model.failureNeedsConfiguration, let onOpenSettings {
                    Button("去设置聊天模型") {
                        dismiss()
                        onOpenSettings()
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .accessibilityHint("关闭这次问答并打开聊天模型设置")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ElsepageSpacing.md)
        .background(ElsepageColor.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: ElsepageRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var stoppedRow: some View {
        HStack(spacing: ElsepageSpacing.sm) {
            Text("已停止")
                .font(ElsepageFont.subheadline)
                .foregroundStyle(ElsepageColor.textSecondary)
            Button("重试") { model.retry() }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

}

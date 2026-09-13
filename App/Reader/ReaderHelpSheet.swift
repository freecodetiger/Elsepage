import ReaderAgent
import ReaderCore
import ReflectionCore
import SwiftUI

struct ReaderHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: ReaderHelpModel
    let openCitation: (AgentResponseEvidence) -> Void

    @FocusState private var composerFocused: Bool
    @State private var selectedDetent: PresentationDetent = .medium

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: ElsepageTheme.Spacing.medium) {
                    quoteCard
                    conversation
                    completedExtras
                    saveFeedback
                    disclosure
                    saveError
                }
                .padding(ElsepageTheme.Spacing.medium)
            }
            .scrollDismissesKeyboard(.interactively)

            Divider()
            composer
        }
        .background(Color.elsepageBackground)
        .presentationDetents([.height(184), .medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(true)
        .onChange(of: model.saveNotice) { _, notice in
            // Reveal the newly persisted underline/highlight behind the sheet.
            if notice != nil {
                selectedDetent = .height(184)
            }
        }
        .onDisappear { model.cancel() }
    }

    private var header: some View {
        HStack(spacing: ElsepageTheme.Spacing.small) {
            VStack(alignment: .leading, spacing: 3) {
                Text("问 Agent")
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
                model.discard()
                dismiss()
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
            retryRow("已停止")
        case .failed(let message):
            retryRow(message)
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
            .foregroundStyle(Color.elsepageAccent)
            .background(Color.elsepageAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("向 Agent 解释当前选中的文字")
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
                        Button {
                            handleCitation(evidence)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(AgentMarkdownText.superscript(index + 1))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.elsepageAccent)
                                Text(sourceTitle(for: evidence))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("来源 \(index + 1)：\(sourceTitle(for: evidence))")
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
                .foregroundStyle(.green)
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
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if model.canRetry {
                HStack {
                    Button("重试") { model.retry() }
                        .font(.caption.weight(.semibold))
                    Spacer()
                }
            }

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

                Button {
                    model.sendComposer()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.elsepageOnAccent)
                        .frame(width: 44, height: 44)
                        .background(
                            model.canSubmitComposer ? Color.elsepageAccent : Color.secondary.opacity(0.28),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!model.canSubmitComposer)
                .accessibilityLabel("发送追问")
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
        .accessibilityLabel("Agent 回答")
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
        selectedDetent = .height(184)
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

    private func retryRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

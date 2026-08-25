import LibraryCore
import ReaderCore
import ReadingSessionCore
import ReflectionCore
import SwiftUI

/// The structured Journal card: reading context (duration/chapters), linked
/// highlights, What I think, open Agent questions, citations that jump back to
/// the source, and Memory-change snapshots.
struct JournalEntryCard: View {
    let entry: JournalEntry
    let openSource: (Book, BookLocator) -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.medium) {
            Button(action: { withAnimation(.snappy(duration: 0.24)) { isExpanded.toggle() } }) {
                VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
                    metadata
                    Text(entry.reflection.originalText)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(isExpanded ? nil : 3)
                    compactStatus
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "收起日志" : "展开日志")

            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(ElsepageTheme.Spacing.medium)
        .background(ElsepageTheme.MaterialToken.chrome, in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous)
                .stroke(.primary.opacity(isExpanded ? 0.10 : 0.05))
        }
    }

    private var metadata: some View {
        HStack(alignment: .firstTextBaseline, spacing: ElsepageTheme.Spacing.small) {
            Text(entry.book.title)
                .font(.system(.subheadline, design: .serif, weight: .semibold))
                .lineLimit(1)
            Text(entry.reflection.createdAt, format: .dateTime.month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private var compactStatus: some View {
        HStack(spacing: ElsepageTheme.Spacing.medium) {
            if let duration = entry.sessionDuration {
                Label(durationLabel(duration), systemImage: "clock")
            }
            if !entry.chapters.isEmpty {
                Label("\(entry.chapters.count) 章", systemImage: "list.bullet")
            }
            if !entry.linkedHighlights.isEmpty {
                Label("\(entry.linkedHighlights.count) 高亮", systemImage: "highlighter")
            }
            if !entry.openQuestions.isEmpty {
                Label("有提问", systemImage: "questionmark.bubble")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var expandedContent: some View {
        if let session = entry.session, session.duration != nil {
            Divider()
            row(title: "本次阅读", systemImage: "clock", value: sessionLine(session))
        }
        if !entry.chapters.isEmpty {
            Divider()
            row(title: "覆盖章节", systemImage: "list.bullet", value: entry.chapters.compactMap(\.title).joined(separator: "、"))
        }
        if !entry.linkedHighlights.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Label("相关高亮", systemImage: "highlighter")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.elsepageAccent)
                ForEach(entry.linkedHighlights) { highlight in
                    Button {
                        openSource(entry.book, highlight.locator)
                    } label: {
                        Text(highlight.locator.textHighlight ?? "高亮位置")
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if !entry.whatIThink.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Label("我想", systemImage: "brain.head.profile")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.elsepageAccent)
                ForEach(entry.whatIThink, id: \.id) { thought in
                    Text("· \(thought.thought)")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        if !entry.questions.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Label("留下问题", systemImage: "questionmark.bubble")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.elsepageAccent)
                ForEach(entry.questions) { question in
                    HStack(alignment: .top, spacing: 6) {
                        Text("· \(question.text)")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        if question.status == .answered {
                            Text("已回应").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        if !entry.citations.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Label("引用", systemImage: "quote.opening")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.elsepageAccent)
                ForEach(entry.citations) { citation in
                    Button {
                        if let locator = citation.locator { openSource(entry.book, locator) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            if let title = citation.title {
                                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                            }
                            if let excerpt = citation.excerpt {
                                Text(excerpt)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(3)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(citation.locator == nil)
                }
            }
        }
        if !entry.memoryChanges.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Label("记住的改变", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.elsepageAccent)
                ForEach(entry.memoryChanges, id: \.id) { change in
                    Text("· \(change.changeType.rawValue)：\(change.summary)")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        if let locator = entry.sourceLocator {
            Divider()
            Button("回到原文") { openSource(entry.book, locator) }
                .font(.footnote.weight(.medium))
        }
    }

    private func row(title: String, systemImage: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sessionLine(_ session: ReadingSession) -> String {
        var parts: [String] = []
        if let duration = session.duration { parts.append(durationLabel(duration)) }
        parts.append("\(session.highlightCount) 高亮 · \(session.noteCount) 批注")
        return parts.joined(separator: "，")
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        let minutes = Int((duration / 60).rounded(.down))
        if minutes > 0 { return "\(minutes) 分钟" }
        return "不足 1 分钟"
    }
}

import SwiftUI
import ReflectionCore
import UIKit

extension AgentEvidenceKind {
    /// Display label used when an evidence snapshot has no better title.
    var title: String {
        switch self {
        case .nearbyPassage: "当前阅读位置"
        case .bookPassage: "书中内容"
        case .pastReflection: "过去的想法"
        }
    }
}

/// Renders model-authored Markdown without treating it as executable HTML.
/// User-authored Reflection text intentionally continues to use plain `Text`.
struct AgentMarkdownText: View {
    let content: String
    var provenance: AgentResponseProvenance = .init(evidence: [], citations: [])
    var openCitation: ((AgentResponseEvidence) -> Void)?
    /// UITextView 需要显式字体/颜色——外层 `.font`/`.foregroundStyle` 不会透传进来。
    var textStyle: UIFont.TextStyle = .body
    var isSecondary = false
    var body: some View {
        MessageText(
            content: .markdown(linkedContent),
            textStyle: textStyle,
            isSecondary: isSecondary,
            linkHandler: handleURL
        )
    }

    /// 拦截 citation 链接的轻点;无法识别的 elsepage 链接吞掉,避免系统尝试打开未知 scheme 弹错。
    private func handleURL(_ url: URL) -> Bool {
        guard url.scheme == "elsepage-citation" else { return false }
        if let evidence = provenance.evidence.first(where: { $0.id == url.host() }) {
            openCitation?(evidence)
        }
        return true
    }

    private var linkedContent: String {
        provenance.citations.reduce(content) { result, citation in
            result.replacingOccurrences(
                of: "[\(citation.marker)]",
                with: "[\(citation.marker)](elsepage-citation://\(citation.evidenceID))"
            )
        }
    }
}

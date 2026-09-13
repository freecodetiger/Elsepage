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
enum AgentCitationStyle {
    case superscript
    case label
}

struct AgentMarkdownText: View {
    let content: String
    var provenance: AgentResponseProvenance = .init(evidence: [], citations: [])
    var openCitation: ((AgentResponseEvidence) -> Void)?
    /// UITextView 需要显式字体/颜色——外层 `.font`/`.foregroundStyle` 不会透传进来。
    var textStyle: UIFont.TextStyle = .body
    var isSecondary = false
    var citationStyle: AgentCitationStyle = .label
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
                with: "[\(displayLabel(for: citation))](elsepage-citation://\(citation.evidenceID))"
            )
        }
    }

    private func displayLabel(for citation: AgentCitation) -> String {
        switch citationStyle {
        case .superscript:
            guard let index = provenance.citations.firstIndex(where: { $0.marker == citation.marker }) else {
                return citation.marker
            }
            return Self.superscript(index + 1)
        case .label:
            return citationLabel(for: citation)
        }
    }

    private func citationLabel(for citation: AgentCitation) -> String {
        guard let evidence = provenance.evidence.first(where: { $0.id == citation.evidenceID }) else {
            return citation.marker
        }
        return switch evidence.kind {
        case .nearbyPassage: "原文"
        case .bookPassage: "书中"
        case .pastReflection: "过去"
        }
    }

    static func superscript(_ number: Int) -> String {
        let map: [Character: Character] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        ]
        return String(String(number).map { map[$0] ?? $0 })
    }
}

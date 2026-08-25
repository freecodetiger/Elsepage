import SwiftUI
import ReflectionCore

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

    var body: some View {
        Text(attributedContent)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "elsepage-citation",
                      let evidence = provenance.evidence.first(where: { $0.id == url.host() }) else {
                    return .systemAction
                }
                openCitation?(evidence)
                return .handled
            })
    }

    private var attributedContent: AttributedString {
        (try? AttributedString(
            markdown: linkedContent,
            options: .init(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(content)
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

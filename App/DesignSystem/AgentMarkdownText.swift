import SwiftUI

/// Renders model-authored Markdown without treating it as executable HTML.
/// User-authored Reflection text intentionally continues to use plain `Text`.
struct AgentMarkdownText: View {
    let content: String

    var body: some View {
        Text(attributedContent)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributedContent: AttributedString {
        (try? AttributedString(
            markdown: content,
            options: .init(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(content)
    }
}

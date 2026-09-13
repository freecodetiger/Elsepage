import AgentRuntime
import Foundation
import ReflectionCore

/// Standalone one-shot model call that turns the first Reflection and first
/// Agent response into an immutable browsing summary.
public struct ReflectionSummaryService: Sendable {
    public static let promptVersion = "reflection-summary-v1"

    private let clientFactory: any ModelClientFactory

    public init(clientFactory: any ModelClientFactory) {
        self.clientFactory = clientFactory
    }

    public func summarize(
        reflection: Reflection,
        firstAgentResponse: String
    ) async throws -> String {
        let response = firstAgentResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !response.isEmpty else { throw ReflectionSummaryError.emptyResponse }

        let client = try await clientFactory.makeClient()
        let request = ModelRequest(
            messages: [
                ModelMessage(role: .system, content: Self.systemPrompt),
                ModelMessage(
                    role: .user,
                    content: """
                    用户第一次记录：
                    \(reflection.originalText)

                    第一次 AI 回应：
                    \(response)
                    """
                )
            ],
            temperature: 0.2,
            maxOutputTokens: 80
        )

        var content = ""
        for try await event in client.stream(request: request) {
            if case .textDelta(let text) = event {
                content += text
            }
        }
        return try Self.normalize(content)
    }

    static func normalize(_ raw: String) throws -> String {
        let firstLine = raw
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            ?? ""

        var text = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["概要：", "概要:", "总结：", "总结:", "- ", "• "] {
            if text.hasPrefix(prefix) {
                text.removeFirst(prefix.count)
            }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "“”\"'「」『』"))
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.count > ReflectionSummary.maximumCharacterCount,
           let sentence = text.split(whereSeparator: { "。！？!?".contains($0) }).first {
            text = String(sentence)
        }

        guard !text.isEmpty else { throw ReflectionSummaryError.emptyResult }
        guard text.count <= ReflectionSummary.maximumCharacterCount else {
            throw ReflectionSummaryError.tooLong
        }
        return text
    }

    private static let systemPrompt = """
    你是页外的阅读记录整理器。输入是用户第一次留下的阅读记录，以及页外对它的第一次回应。

    请写一句“概要”：
    - 只用一句话，尽量 12–24 个中文字符，不能超过 36 个字符。
    - 准确复述用户这次留下的核心意思；可以吸收第一次回应中的澄清，但不得添加用户没有表达、回应也没有支持的新观点。
    - 像用户自己留下的一句判断，不要写“用户认为”“这段记录说明”“本文讨论”等报告腔。
    - 不要提问，不要鼓励，不要评价，不要 Markdown，不要编号，不要引号包裹整句。
    - 直接输出概要本身，不要前缀或解释。
    """
}

public enum ReflectionSummaryError: Error, Equatable, Sendable {
    case emptyResponse
    case emptyResult
    case tooLong
}

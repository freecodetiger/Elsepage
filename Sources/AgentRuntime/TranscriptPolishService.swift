import Foundation

/// Standalone "make my spoken words neat" model call. Deliberately independent of
/// `ReaderAgent`: it sends the raw transcript with a fixed system prompt and returns
/// the polished text unchanged in meaning. Shares the configured BYOK provider via
/// the same `ModelClientFactory`; no context routing, evidence, or conversation.
public struct TranscriptPolishService: Sendable {
    private let clientFactory: any ModelClientFactory

    public init(clientFactory: any ModelClientFactory) {
        self.clientFactory = clientFactory
    }

    public func polish(_ transcript: String) async throws -> String {
        let client = try await clientFactory.makeClient()
        let request = ModelRequest(
            messages: [
                ModelMessage(role: .system, content: Self.systemPrompt),
                ModelMessage(role: .user, content: transcript)
            ],
            temperature: 0.2
            // No maxOutputTokens: polish output ≈ transcript length, which can run
            // to a thousand+ Chinese chars. Truncation would silently cut the reply.
        )
        var content = ""
        for try await event in client.stream(request: request) {
            if case .textDelta(let text) = event { content += text }
        }
        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw TranscriptPolishError.emptyResult }
        return result
    }

    /// 忠实 + 清晰:保留用户全部要点与立场,只把表达变清楚(去口头语、合并重复、
    /// 理顺语序)。这是对用户表达质量的提升,不是代写——不添加任何用户没说的内容。
    private static let systemPrompt = """
    你是一位表达优化助手。把用户口述的语音转写改写成清晰、通顺、有层次的书面文本。
    要求：
    - 完全忠于原意：保留全部信息要点、观点、立场和例子。
    - 把表达变清楚：去掉口头语与重复（如"然后然后""就是""嗯"），合并重复表达，理顺语序与逻辑。
    - 不添加用户没说的观点、背景、例子或结论；不代写；不改变用户想表达的意思。
    直接输出改写后的文本本身，不要任何解释、前缀、引号或额外内容。
    """
}

public enum TranscriptPolishError: Error, Equatable, Sendable {
    case emptyResult
}

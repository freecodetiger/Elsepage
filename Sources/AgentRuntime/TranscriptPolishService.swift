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
            temperature: 0.2,
            maxOutputTokens: 800
        )
        var content = ""
        for try await event in client.stream(request: request) {
            if case .textDelta(let text) = event { content += text }
        }
        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw TranscriptPolishError.emptyResult }
        return result
    }

    /// Keep the user's own words; only tidy punctuation, paragraph breaks and flow.
    private static let systemPrompt = """
    你是一位文字整理助手。把用户口述的语音转写整理成通顺、工整、易读的书面文字。
    严格要求：不改变原意，不新增信息，不删减要点，不做摘要，不添加结论。
    直接输出整理后的文本本身，不要任何解释、前缀、引号或额外内容。
    """
}

public enum TranscriptPolishError: Error, Equatable, Sendable {
    case emptyResult
}

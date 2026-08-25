import Foundation
import ReflectionCore

public struct ValidatedAgentResponse: Equatable, Sendable {
    public let content: String
    public let citations: [AgentCitation]
}

/// Validates the deliberately small inline citation contract (`[E1]`, `[E2]`, ...).
/// Unknown markers are removed from display and never become persisted citations.
public struct AgentCitationValidator: Sendable {
    public init() {}

    public func validate(
        content: String,
        messageID: UUID,
        evidence: [AgentResponseEvidence]
    ) -> ValidatedAgentResponse {
        let known = Dictionary(uniqueKeysWithValues: evidence.map { ($0.id, $0) })
        var output = ""
        var cited = Set<String>()
        var citations: [AgentCitation] = []
        var index = content.startIndex

        while index < content.endIndex {
            if content[index] == "[", let marker = marker(startingAt: index, in: content) {
                if known[marker.id] != nil {
                    output += "[\(marker.id)]"
                    if cited.insert(marker.id).inserted {
                        citations.append(.init(messageID: messageID, evidenceID: marker.id, marker: marker.id))
                    }
                }
                index = marker.endIndex
            } else {
                output.append(content[index])
                index = content.index(after: index)
            }
        }
        return ValidatedAgentResponse(
            content: output.trimmingCharacters(in: .whitespacesAndNewlines),
            citations: citations
        )
    }

    private func marker(startingAt start: String.Index, in content: String) -> (id: String, endIndex: String.Index)? {
        var cursor = content.index(after: start)
        guard cursor < content.endIndex, content[cursor] == "E" else { return nil }
        cursor = content.index(after: cursor)
        let digitsStart = cursor
        while cursor < content.endIndex, content[cursor].isNumber { cursor = content.index(after: cursor) }
        guard cursor > digitsStart, cursor < content.endIndex, content[cursor] == "]" else { return nil }
        let id = String(content[content.index(after: start)..<cursor])
        return (id, content.index(after: cursor))
    }
}

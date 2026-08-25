import AgentRuntime
import Foundation
import ReflectionCore
import RetrievalCore

public struct ValidatedAgentResponse: Equatable, Sendable {
    public let content: String
    public let citations: [AgentCitation]
}

/// Validates the deliberately small inline citation contract (`[E1]`, `[E2]`, ...)
/// plus an optional structured `---CITATIONS---` block the model appends to its reply.
///
/// The structured block is authoritative when present: an inline marker is only kept
/// when its evidence's `sourceID` appears in the block and (for book passages) the
/// chunk still exists locally, belongs to this book, and sits within the read boundary.
/// When the block is absent (e.g. a provider without JSON mode) every known marker is
/// accepted, matching the previous inline-only contract.
///
/// Unknown markers are removed from display and never become persisted citations.
public struct AgentCitationValidator: Sendable {
    public init() {}

    public func validate(
        content: String,
        messageID: UUID,
        evidence: [AgentResponseEvidence],
        bookIndex: (any BookIndexRepository)? = nil,
        version: Int = BookIndexPipeline.currentVersion,
        readingBoundary: ReadingBoundary? = nil
    ) async -> ValidatedAgentResponse {
        let known = Dictionary(uniqueKeysWithValues: evidence.map { ($0.id, $0) })
        let bySourceID = Dictionary(evidence.map { ($0.sourceID, $0) }, uniquingKeysWith: { first, _ in first })
        let split = Self.splitStructuredBlock(from: content)
        let displayContent = split.display
        let acceptedSourceIDs: Set<String>
        if split.structured.isEmpty {
            acceptedSourceIDs = Set(evidence.map(\.sourceID))
        } else {
            acceptedSourceIDs = Set(split.structured.compactMap { structured in
                guard let matched = bySourceID[structured.evidenceID],
                      matched.kind.rawValue.lowercased() == structured.kind.lowercased() else { return nil }
                return matched.sourceID
            })
        }

        var output = ""
        var cited = Set<String>()
        var citations: [AgentCitation] = []
        var index = displayContent.startIndex

        while index < displayContent.endIndex {
            if displayContent[index] == "[", let marker = marker(startingAt: index, in: displayContent) {
                if let evidence = known[marker.id], acceptedSourceIDs.contains(evidence.sourceID) {
                    var accepted = cited.contains(marker.id)
                    if !accepted {
                        accepted = await self.localEvidenceIsValid(evidence, bookIndex: bookIndex, version: version, readingBoundary: readingBoundary)
                    }
                    if accepted {
                        output += "[\(marker.id)]"
                        if cited.insert(marker.id).inserted {
                            citations.append(.init(messageID: messageID, evidenceID: marker.id, marker: marker.id))
                        }
                    }
                }
                index = marker.endIndex
            } else {
                output.append(displayContent[index])
                index = displayContent.index(after: index)
            }
        }
        return ValidatedAgentResponse(
            content: output.trimmingCharacters(in: .whitespacesAndNewlines),
            citations: citations
        )
    }

    private func localEvidenceIsValid(
        _ evidence: AgentResponseEvidence,
        bookIndex: (any BookIndexRepository)?,
        version: Int,
        readingBoundary: ReadingBoundary?
    ) async -> Bool {
        guard evidence.kind == .bookPassage else { return true }
        guard let bookIndex else { return true }
        let chunkID = BookChunkID(rawValue: evidence.sourceID)
        guard let chunk = try? await bookIndex.chunk(id: chunkID, bookID: evidence.bookID, version: version) else { return false }
        guard chunk.bookID == evidence.bookID else { return false }
        if let readingBoundary, !readingBoundary.contains(chunk) { return false }
        return true
    }

    private static func splitStructuredBlock(from content: String) -> (display: String, structured: [AgentStructuredCitation]) {
        let delimiter = "---CITATIONS---"
        guard let range = content.range(of: delimiter) else { return (content, []) }
        let display = String(content[..<range.lowerBound])
        let jsonText = String(content[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = jsonText.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([AgentStructuredCitation].self, from: data) else {
            return (display, [])
        }
        return (display, decoded)
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

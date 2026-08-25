import Foundation
import ReaderCore

/// Best-effort structured extraction from free-text Agent output.
///
/// We do NOT change the Agent prompt/events (coordinator contract); instead this
/// parser tolerates plain prose and harvests a JSON object when the model emits
/// one (optionally fenced), mirroring the `JSONDecoder().decode` pattern used by
/// `LLMReaderContextRouter`. If nothing parses, the Journal simply stays sparse.
public enum JournalStructuredParser {
    public struct MemoryProposal: Hashable, Sendable {
        public var changeType: JournalMemoryChangeType
        public var memoryID: String?
        public var summary: String
    }

    public struct ParsedCitation: Hashable, Sendable {
        public var title: String?
        public var excerpt: String?
        public var locator: BookLocator?
    }

    public struct Parsed: Hashable, Sendable {
        public var thoughts: [String]
        public var question: String?
        public var memoryProposals: [MemoryProposal]
        public var citations: [ParsedCitation]

        public static let empty = Parsed(thoughts: [], question: nil, memoryProposals: [], citations: [])
    }

    public static func parse(_ content: String) -> Parsed {
        guard let envelope = decodeEnvelope(from: content) else { return .empty }
        return Parsed(
            thoughts: envelope.whatIThink?.compactMap { Self.clean($0) } ?? [],
            question: clean(envelope.question),
            memoryProposals: (envelope.memory_proposals ?? []).compactMap(Self.proposal),
            citations: (envelope.citations ?? []).compactMap(Self.citation)
        )
    }

    // MARK: - Decoding

    private struct Envelope: Decodable {
        var question: String?
        var whatIThink: [String]?
        var memory_proposals: [MemoryPayload]?
        var citations: [CitationPayload]?
    }

    private struct MemoryPayload: Decodable {
        var type: String?
        var id: String?
        var summary: String?
    }

    private struct CitationPayload: Decodable {
        var title: String?
        var excerpt: String?
        var locator: LocatorPayload?
    }

    private struct LocatorPayload: Decodable {
        var href: String?
        var progression: Double?
        var totalProgression: Double?
        var textBefore: String?
        var textHighlight: String?
        var textAfter: String?
    }

    private static func decodeEnvelope(from content: String) -> Envelope? {
        if let envelope = decode(content) { return envelope }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip a ```json ... ``` fence, then try again.
        let fenced = trimmed.replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
        if let envelope = decode(fenced) { return envelope }
        // Fall back to the first balanced {...} object embedded in prose.
        for candidate in Self.jsonObjects(in: content) {
            if let envelope = decode(candidate) { return envelope }
        }
        return nil
    }

    private static func decode(_ text: String) -> Envelope? {
        try? JSONDecoder().decode(Envelope.self, from: Data(text.utf8))
    }

    /// Extracts balanced `{ ... }` substrings, longest-first, to avoid picking a
    /// nested object when prose surrounds the real payload.
    private static func jsonObjects(in text: String) -> [String] {
        let characters = Array(text)
        var objects: [String] = []
        var openingIndex: Int?
        var depth = 0
        for index in characters.indices {
            switch characters[index] {
            case "{":
                if depth == 0 { openingIndex = index }
                depth += 1
            case "}":
                depth -= 1
                if depth == 0, let opened = openingIndex {
                    objects.append(String(characters[opened...index]))
                    openingIndex = nil
                }
            default: continue
            }
        }
        return objects.sorted { $0.count > $1.count }
    }

    private static func clean(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private static func proposal(_ payload: MemoryPayload) -> MemoryProposal? {
        guard let summary = clean(payload.summary) else { return nil }
        let type = payload.type.flatMap(JournalMemoryChangeType.init(rawValue:)) ?? .store
        return MemoryProposal(changeType: type, memoryID: payload.id, summary: summary)
    }

    private static func citation(_ payload: CitationPayload) -> ParsedCitation? {
        guard payload.excerpt != nil || payload.title != nil || payload.locator != nil else { return nil }
        return ParsedCitation(
            title: clean(payload.title),
            excerpt: clean(payload.excerpt),
            locator: payload.locator.flatMap(locator(from:))
        )
    }

    private static func locator(from payload: LocatorPayload) -> BookLocator? {
        guard let href = payload.href else { return nil }
        let object: [String: Any] = [
            "href": href,
            "locations": [
                "progression": payload.progression ?? 0,
                "totalProgression": payload.totalProgression ?? 0,
            ],
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? BookLocator(
            json: json,
            href: href,
            progression: payload.progression,
            totalProgression: payload.totalProgression,
            textBefore: payload.textBefore,
            textHighlight: payload.textHighlight,
            textAfter: payload.textAfter
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

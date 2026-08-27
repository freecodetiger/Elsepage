import Foundation
import ReflectionCore

/// Conservative lexical retrieval over past reflections: at least two shared
/// meaningful tokens and a 40% overlap against the smaller thought. This favors
/// silence over a weak or performative personal connection.
public enum ReflectionLexicalMatcher {
    public struct Match: Hashable, Sendable {
        public let reflection: Reflection
        public let relevance: Double
    }

    public static func strongestMatch(
        for query: String,
        among candidates: [Reflection]
    ) -> Match? {
        let queryTokens = tokens(in: query)
        guard queryTokens.count >= 2 else { return nil }
        return candidates.compactMap { reflection -> Match? in
            let candidateTokens = tokens(in: reflection.originalText)
            let overlap = queryTokens.intersection(candidateTokens).count
            guard overlap >= 2 else { return nil }
            let relevance = Double(overlap) / Double(max(1, min(queryTokens.count, candidateTokens.count)))
            guard relevance >= 0.40 else { return nil }
            return Match(reflection: reflection, relevance: relevance)
        }
        .max { lhs, rhs in
            if lhs.relevance == rhs.relevance {
                return lhs.reflection.createdAt < rhs.reflection.createdAt
            }
            return lhs.relevance < rhs.relevance
        }
    }

    /// CJK-aware tokenization: latin/number words (length >= 2) plus CJK bigrams.
    /// Shared by reflection and memory matching so both lanes score consistently.
    public static func tokens(in text: String) -> Set<String> {
        let lowered = text.lowercased()
        let words = lowered.split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 2 }
        let cjk = lowered.unicodeScalars.filter { scalar in
            (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
        }
        let bigrams = zip(cjk, cjk.dropFirst()).map { String($0) + String($1) }
        return Set(words + bigrams)
    }
}

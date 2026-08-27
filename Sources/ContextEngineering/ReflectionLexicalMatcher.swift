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
        candidates.compactMap { reflection -> Match? in
            lexicalRelevance(query: query, candidate: reflection).map { Match(reflection: reflection, relevance: $0) }
        }
        .max { lhs, rhs in
            if lhs.relevance == rhs.relevance {
                return lhs.reflection.createdAt < rhs.reflection.createdAt
            }
            return lhs.relevance < rhs.relevance
        }
    }

    /// Lexical relevance of one candidate, or nil when it fails the conservative
    /// bar (≥2 shared tokens AND ≥40% overlap). Shared by the pure-lexical matcher
    /// and the hybrid fusion lane.
    public static func lexicalRelevance(query: String, candidate: Reflection) -> Double? {
        let queryTokens = tokens(in: query)
        guard queryTokens.count >= 2 else { return nil }
        let candidateTokens = tokens(in: candidate.originalText)
        let overlap = queryTokens.intersection(candidateTokens).count
        guard overlap >= 2 else { return nil }
        let relevance = Double(overlap) / Double(max(1, min(queryTokens.count, candidateTokens.count)))
        guard relevance >= 0.40 else { return nil }
        return relevance
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

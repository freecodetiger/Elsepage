import BrainCore
import ContextRouting
import Foundation

/// The integration layer between the Brain domain and the Context Engineering
/// pipeline (docs/brain.md §12-13, phase 16): BrainCandidates become ordinary
/// `ContextCandidate`s so the existing ContextAssembler dedup/rank/budget
/// machinery stays the only downstream system. BrainCore itself is untouched.
public struct BrainContextProvider: Sendable {
    private let retriever: BrainRetriever

    public init(retriever: BrainRetriever) {
        self.retriever = retriever
    }

    /// Retrieves brain items relevant to `query` and adapts them for the
    /// assembler. Used when the planner requests brain retrieval.
    public func candidates(
        query: String,
        kinds: Set<BrainItemKind> = [.thought, .question],
        limit: Int = 3
    ) async -> [ContextCandidate] {
        let hits = await retriever.retrieve(query: query, kinds: kinds, limit: limit)
        return hits.compactMap { Self.candidate(from: $0) }
    }

    /// The user's explicitly active brain item (brain.md §11A): pinned context
    /// that deterministically enters the bundle — input-driven, never subject
    /// to planner veto or retriever luck.
    public static func pinnedCandidate(for item: BrainItem) -> ContextCandidate {
        candidate(
            from: BrainCandidate(item: item, lexicalScore: nil, semanticScore: nil),
            source: .pinnedBrain, relevance: 1.0
        )
    }

    /// The single-candidate mapping, exposed for tests and for callers that
    /// already hold a scored BrainCandidate.
    public static func candidate(from hit: BrainCandidate) -> ContextCandidate? {
        candidate(from: hit, source: .brain, relevance: hit.semanticScore ?? hit.lexicalScore ?? 0.5)
    }

    private static func candidate(from hit: BrainCandidate, source: ContextSource, relevance: Double) -> ContextCandidate {
        let item = hit.item
        return ContextCandidate(
            id: item.id.rawValue,
            source: source,
            content: Self.contentText(of: item),
            relevance: relevance,
            metadata: [
                "brainItemID": item.id.rawValue,
                "brainKind": item.kind.rawValue,
                "brainTitle": Self.titleText(of: item),
            ]
        )
    }

    public static func contentText(of item: BrainItem) -> String {
        switch item {
        case .thought(let item): item.statement
        case .question(let item): item.question
        case .memory(let item): item.content
        }
    }

    public static func titleText(of item: BrainItem) -> String {
        switch item {
        case .thought(let item): item.title
        case .question(let item): String(item.question.prefix(24))
        case .memory(let item): String(item.content.prefix(24))
        }
    }
}

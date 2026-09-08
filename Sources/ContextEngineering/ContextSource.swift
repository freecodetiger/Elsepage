/// The distinct context sources a Context Planner can draw on. Each is retrieved
/// by its own source-specific retriever; the assembly layer ranks and budgets
/// across them.
public enum ContextSource: String, Hashable, Codable, Sendable, CaseIterable {
    case nearbyPassage
    case bookPassage
    case pastReflection
    /// Brain items (Thought/Question/Memory) — the user's own formed thinking
    /// and stable knowledge, bridged from BrainRetriever (phase 16). Memory rides
    /// this lane as non-citable context, not a separate evidence lane.
    case brain
    /// The user's explicitly active brain item (discussing one item in the Brain
    /// page) — pinned context that must deterministically enter the bundle,
    /// outranking every retrieved source.
    case pinnedBrain
    case conversation
}

/// The distinct context sources a Context Planner can draw on. Each is retrieved
/// by its own source-specific retriever; the assembly layer ranks and budgets
/// across them.
public enum ContextSource: String, Hashable, Codable, Sendable {
    case nearbyPassage
    case bookPassage
    case pastReflection
    case memory
    case conversation
}

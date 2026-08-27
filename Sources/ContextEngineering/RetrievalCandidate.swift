import Foundation

/// A normalized, source-agnostic retrieval hit produced by a source-specific
/// retriever (book child, past reflection, memory, ...). Carries both scoring
/// lanes so the assembly layer can fuse, dedup, and budget without knowing the
/// source's internal mechanics.
public struct RetrievalCandidate: Hashable, Sendable {
    public let id: String
    public let source: ContextSource
    public let text: String
    public let lexicalScore: Double?
    public let semanticScore: Double?
    /// Source-specific provenance (e.g. book chunk id / reflection id / memory id).
    public let metadata: [String: String]

    public init(
        id: String,
        source: ContextSource,
        text: String,
        lexicalScore: Double? = nil,
        semanticScore: Double? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.source = source
        self.text = text
        self.lexicalScore = lexicalScore
        self.semanticScore = semanticScore
        self.metadata = metadata
    }
}

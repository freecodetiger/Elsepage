import Foundation

/// Process-local cache for reflection/memory semantic vectors. Keyed by
/// (source, itemID, contentHash, embeddingModel) so a text re-embedded under a
/// different model (or edited content) never collides with a stale vector. Not
/// persisted: this is a session-scoped cost saver, not storage.
public final class SemanticVectorCache: @unchecked Sendable {
    public struct Key: Hashable, Sendable {
        public let source: ContextSource
        public let itemID: String
        public let contentHash: String
        public let model: String

        public init(source: ContextSource, itemID: String, contentHash: String, model: String) {
            self.source = source
            self.itemID = itemID
            self.contentHash = contentHash
            self.model = model
        }
    }

    private let lock = NSLock()
    private var store: [Key: [Float]] = [:]
    private var hits = 0
    private var misses = 0

    public init() {}

    public func vector(for key: Key) -> [Float]? {
        lock.withLock {
            if let vector = store[key] {
                hits += 1
                return vector
            }
            misses += 1
            return nil
        }
    }

    public func store(_ vector: [Float], for key: Key) {
        lock.withLock { store[key] = vector }
    }

    public var hitMissCounts: (hits: Int, misses: Int) {
        lock.withLock { (hits, misses) }
    }
}

import Foundation

public enum MemoryKind: String, Codable, Sendable, CaseIterable {
    case episodic, semantic, preference, openQuestion, profileTrait
}

public enum MemoryStatus: String, Codable, Sendable, CaseIterable {
    case provisional, active, superseded
}

/// A long-term, derived memory about the reader. Memories are evidence-backed
/// (each references the Reflection and message that produced it) and never
/// replace source data. `userEdited` memories are never overwritten by the
/// automatic application pipeline (P2).
public struct ReaderMemory: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let sourceReflectionID: ReflectionID?
    public let kind: MemoryKind
    public var claim: String
    public var confidence: Double
    public var status: MemoryStatus
    public var userEdited: Bool
    public let evidenceIDs: [String]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        sourceReflectionID: ReflectionID? = nil,
        kind: MemoryKind,
        claim: String,
        confidence: Double,
        status: MemoryStatus = .provisional,
        userEdited: Bool = false,
        evidenceIDs: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sourceReflectionID = sourceReflectionID
        self.kind = kind
        self.claim = claim
        self.confidence = min(1, max(0, confidence))
        self.status = status
        self.userEdited = userEdited
        self.evidenceIDs = evidenceIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Persists long-term memories. Deleting a source Reflection cascades its
/// derived memories (PRD §19).
public protocol MemoryRepository: Sendable {
    func memories() async throws -> [ReaderMemory]
    func memories(kind: MemoryKind) async throws -> [ReaderMemory]
    func save(_ memory: ReaderMemory) async throws
    func delete(id: UUID) async throws
    func deleteAll() async throws
    func markInaccurate(id: UUID) async throws
}

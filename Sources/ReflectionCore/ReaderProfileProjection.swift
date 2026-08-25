import Foundation

/// Deterministic, evidence-based summary of what the Agent currently understands
/// about the reader. A pure projection over `ReaderMemory` values — no IO, no UI.
///
/// Superseded memories are kept out of the profile and active lists but remain
/// available as the visible audit trail (`supersededMemories`) so a user's
/// "不准确" is never silently dropped.
public struct ReaderProfileProjection: Hashable, Sendable {
    /// Active `profileTrait` / `preference` / `semantic` memories, most recently
    /// updated first. This is the "AI 眼中的我" data source.
    public let profileTraits: [ReaderMemory]
    /// Every memory that has not been superseded (the "记忆" list).
    public let activeMemories: [ReaderMemory]
    /// Memories the user marked 不准确, newest first (shown struck-through).
    public let supersededMemories: [ReaderMemory]

    public init(memories: [ReaderMemory]) {
        let ordered = memories.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        profileTraits = ordered.filter {
            $0.status != .superseded
                && ($0.kind == .profileTrait || $0.kind == .preference || $0.kind == .semantic)
        }
        activeMemories = ordered.filter { $0.status != .superseded }
        supersededMemories = ordered.filter { $0.status == .superseded }
    }
}

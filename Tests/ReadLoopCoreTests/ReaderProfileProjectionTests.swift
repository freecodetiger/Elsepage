import Foundation
import LibraryCore
import Persistence
import ReflectionCore
import Testing

/// WS2: the "AI 眼中的我" projection is deterministic, evidence-based, and never
/// surfaces superseded memories.
@Test func projectionGroupsTraitsExcludesSupersededAndIsDeterministic() {
    let base = Date(timeIntervalSince1970: 1_000_000)
    let episodic = ReaderMemory(kind: .episodic, claim: "上周读完了一本小说", confidence: 0.9, status: .active, createdAt: base, updatedAt: base.addingTimeInterval(4000))
    let semantic = ReaderMemory(kind: .semantic, claim: "认为阅读是对话", confidence: 0.6, status: .active, createdAt: base, updatedAt: base.addingTimeInterval(3000))
    let preference = ReaderMemory(kind: .preference, claim: "偏好精装书", confidence: 0.7, status: .provisional, createdAt: base, updatedAt: base.addingTimeInterval(2000))
    let trait = ReaderMemory(kind: .profileTrait, claim: "重视自由", confidence: 0.8, status: .active, createdAt: base, updatedAt: base.addingTimeInterval(1000))
    let superseded = ReaderMemory(kind: .profileTrait, claim: "旧的错误理解", confidence: 0.6, status: .superseded, createdAt: base, updatedAt: base.addingTimeInterval(5000))

    let projection = ReaderProfileProjection(memories: [superseded, trait, preference, semantic, episodic])

    // Profile = active trait/preference/semantic, most recently updated first.
    #expect(projection.profileTraits.map(\.claim) == ["认为阅读是对话", "偏好精装书", "重视自由"])
    #expect(!projection.profileTraits.contains { $0.id == superseded.id })

    // Active list keeps every non-superseded memory; superseded is its own audit trail.
    #expect(projection.activeMemories.count == 4)
    #expect(!projection.activeMemories.contains { $0.status == .superseded })
    #expect(projection.supersededMemories.map(\.id) == [superseded.id])

    // The projection is deterministic regardless of input order.
    let shuffled = ReaderProfileProjection(memories: [trait, semantic, episodic, superseded, preference])
    #expect(shuffled.profileTraits == projection.profileTraits)
    #expect(shuffled.activeMemories == projection.activeMemories)
}

@Test func markInaccurateSupersedesAndProjectionDropsIt() async throws {
    let db = try AppDatabase.inMemory()
    let repository = GRDBMemoryRepository(database: db)
    try await repository.save(ReaderMemory(
        kind: .semantic, claim: "旧理解", confidence: 0.6, status: .provisional, evidenceIDs: []
    ))

    let memory = try #require(try await repository.memories().first)
    try await repository.markInaccurate(id: memory.id)

    let marked = try #require(try await repository.memories().first)
    #expect(marked.status == .superseded)

    let projection = ReaderProfileProjection(memories: try await repository.memories())
    #expect(projection.profileTraits.isEmpty)
    #expect(projection.activeMemories.isEmpty)
    #expect(projection.supersededMemories.count == 1)
}

@Test func userEditedMemoryRoundTripsThroughRepository() async throws {
    let db = try AppDatabase.inMemory()
    let repository = GRDBMemoryRepository(database: db)
    var memory = ReaderMemory(
        kind: .preference, claim: "用户喜欢安静的环境", confidence: 0.6,
        status: .provisional, userEdited: true, evidenceIDs: []
    )
    try await repository.save(memory)

    var loaded = try #require(try await repository.memories().first)
    #expect(loaded.claim == "用户喜欢安静的环境")
    #expect(loaded.userEdited == true)

    // A user edit sticks: claim overwritten, flag preserved.
    loaded.claim = "用户喜欢安静且有自然光的环境"
    loaded.updatedAt = Date().addingTimeInterval(10)
    try await repository.save(loaded)
    let reloaded = try #require(try await repository.memories().first)
    #expect(reloaded.claim == "用户喜欢安静且有自然光的环境")
    #expect(reloaded.userEdited == true)
}

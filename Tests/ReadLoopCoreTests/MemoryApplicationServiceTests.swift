import Foundation
import LibraryCore
import Persistence
import ReflectionCore
import Testing

@Test func storeCreatesProvisionalSemanticMemoryWithEvidence() async throws {
    let db = try AppDatabase.inMemory()
    let (reflectionID, repository) = try await makeReflection(in: db)
    let service = MemoryApplicationService(repository: repository)
    let evidence = ["refl:\(reflectionID)", "msg:some-message-id"]

    try await service.apply(
        JournalMemoryChange(journalID: reflectionID, changeType: .store, summary: "用户重视自由"),
        sourceReflectionID: reflectionID,
        evidence: evidence
    )

    let memory = try #require(try await repository.memories().first)
    #expect(try await repository.memories().count == 1)
    #expect(memory.sourceReflectionID == reflectionID)
    #expect(memory.kind == .semantic)
    #expect(memory.claim == "用户重视自由")
    #expect(abs(memory.confidence - 0.6) < 1e-9)
    #expect(memory.status == .provisional)
    #expect(memory.userEdited == false)
    #expect(memory.evidenceIDs == evidence)
}

@Test func reinforceRaisesConfidenceAndSkipsUserEditedAndSuperseded() async throws {
    let db = try AppDatabase.inMemory()
    let (reflectionID, repository) = try await makeReflection(in: db)
    let service = MemoryApplicationService(repository: repository)

    try await service.apply(
        JournalMemoryChange(journalID: reflectionID, changeType: .store, summary: "用户喜欢早起"),
        sourceReflectionID: reflectionID, evidence: ["refl:\(reflectionID)"]
    )
    let reinforce = JournalMemoryChange(journalID: reflectionID, changeType: .reinforce, summary: "用户喜欢早起")

    try await service.apply(reinforce, sourceReflectionID: reflectionID, evidence: [])
    var memory = try #require(try await repository.memories().first)
    #expect(abs(memory.confidence - 0.75) < 1e-9)

    // A user-edited memory is never reinforced.
    memory.userEdited = true
    try await repository.save(memory)
    try await service.apply(reinforce, sourceReflectionID: reflectionID, evidence: [])
    memory = try #require(try await repository.memories().first)
    #expect(abs(memory.confidence - 0.75) < 1e-9)

    // A superseded memory is never reinforced either.
    memory.status = .superseded
    memory.userEdited = false
    try await repository.save(memory)
    try await service.apply(reinforce, sourceReflectionID: reflectionID, evidence: [])
    memory = try #require(try await repository.memories().first)
    #expect(memory.status == .superseded)
    #expect(abs(memory.confidence - 0.75) < 1e-9)
}

@Test func reviseOverwritesClaimAndSkipsUserEditedAndSuperseded() async throws {
    let db = try AppDatabase.inMemory()
    let (reflectionID, repository) = try await makeReflection(in: db)
    let service = MemoryApplicationService(repository: repository)

    try await service.apply(
        JournalMemoryChange(journalID: reflectionID, changeType: .store, summary: "用户喜欢早起"),
        sourceReflectionID: reflectionID, evidence: ["refl:\(reflectionID)"]
    )
    let revise = JournalMemoryChange(journalID: reflectionID, changeType: .revise, summary: "用户喜欢早起并运动")

    try await service.apply(revise, sourceReflectionID: reflectionID, evidence: [])
    var memory = try #require(try await repository.memories().first)
    #expect(memory.claim == "用户喜欢早起并运动")

    // A user-edited memory is never overwritten.
    memory.userEdited = true
    try await repository.save(memory)
    try await service.apply(revise, sourceReflectionID: reflectionID, evidence: [])
    memory = try #require(try await repository.memories().first)
    #expect(memory.claim == "用户喜欢早起并运动")

    // A superseded memory is never resurrected.
    memory.status = .superseded
    memory.userEdited = false
    try await repository.save(memory)
    try await service.apply(revise, sourceReflectionID: reflectionID, evidence: [])
    memory = try #require(try await repository.memories().first)
    #expect(memory.claim == "用户喜欢早起并运动")
    #expect(memory.status == .superseded)
}

@Test func doubleApplyingSameStoreChangeCreatesSingleMemory() async throws {
    let db = try AppDatabase.inMemory()
    let (reflectionID, repository) = try await makeReflection(in: db)
    let service = MemoryApplicationService(repository: repository)
    let change = JournalMemoryChange(journalID: reflectionID, changeType: .store, summary: "用户重视自由")

    try await service.apply(change, sourceReflectionID: reflectionID, evidence: ["refl:\(reflectionID)"])
    try await service.apply(change, sourceReflectionID: reflectionID, evidence: ["refl:\(reflectionID)"])

    #expect(try await repository.memories().count == 1)
}

// MARK: - Helpers

/// Creates a real Reflection so the `memories.sourceReflectionID` foreign key
/// (REFERENCES reflections ON DELETE CASCADE) is satisfied, mirroring how the
/// pipeline runs only for existing reflections.
private func makeReflection(in db: AppDatabase) async throws -> (ReflectionID, GRDBMemoryRepository) {
    let books = GRDBBookRepository(database: db)
    let reflections = GRDBReflectionRepository(database: db)
    let repository = GRDBMemoryRepository(database: db)
    let book = TestFixtures.book()
    try await books.insert(book)
    let reflection = Reflection(bookID: book.id, originalText: "一段想法", inputKind: .text)
    try await reflections.insert(reflection, linkedHighlightIDs: [], evidence: [])
    return (reflection.id, repository)
}

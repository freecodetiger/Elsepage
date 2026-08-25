import Foundation
import LibraryCore
import Persistence
import ReflectionCore
import Testing

@Test func memoryRepositoryRoundTripsAndFiltersByKind() async throws {
    let db = try AppDatabase.inMemory()
    let repository = GRDBMemoryRepository(database: db)
    let now = Date(timeIntervalSince1970: 1_000_000)
    let memory = ReaderMemory(
        id: UUID(), sourceReflectionID: nil, kind: .preference,
        claim: "用户偏爱精装书", confidence: 0.8, status: .active,
        userEdited: true, evidenceIDs: ["refl:abc", "msg:def"],
        createdAt: now, updatedAt: now
    )

    try await repository.save(memory)
    #expect(try await repository.memories() == [memory])
    #expect(try await repository.memories(kind: .preference) == [memory])
    #expect(try await repository.memories(kind: .semantic).isEmpty)
}

@Test func markInaccurateSupersedesAndDeleteAllClears() async throws {
    let db = try AppDatabase.inMemory()
    let repository = GRDBMemoryRepository(database: db)
    let memory = ReaderMemory(
        kind: .semantic, claim: "旧理解", confidence: 0.6,
        status: .provisional, evidenceIDs: []
    )
    try await repository.save(memory)

    try await repository.markInaccurate(id: memory.id)
    let marked = try #require(try await repository.memories().first)
    #expect(marked.status == .superseded)

    try await repository.deleteAll()
    #expect(try await repository.memories().isEmpty)
}

@Test func deletingSourceReflectionCascadesDerivedMemories() async throws {
    let db = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: db)
    let reflections = GRDBReflectionRepository(database: db)
    let repository = GRDBMemoryRepository(database: db)
    let book = TestFixtures.book()
    try await books.insert(book)
    let reflection = Reflection(bookID: book.id, originalText: "一段想法", inputKind: .text)
    try await reflections.insert(reflection, linkedHighlightIDs: [], evidence: [])

    try await repository.save(ReaderMemory(
        sourceReflectionID: reflection.id, kind: .semantic,
        claim: "派生记忆", confidence: 0.6, status: .provisional,
        evidenceIDs: ["refl:\(reflection.id)"]
    ))
    #expect(try await repository.memories().count == 1)

    try await reflections.delete(id: reflection.id)
    #expect(try await repository.memories().isEmpty)
}

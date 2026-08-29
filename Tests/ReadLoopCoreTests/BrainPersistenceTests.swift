import BrainCore
import Foundation
import GRDB
import LibraryCore
import Persistence
import ReflectionCore
import Testing

// Phase 12 (docs/brain.md): BrainCore domain round-trips, brainItems per-kind
// invariants, the legacy memories backfill, and data-wipe coverage.

@Test func brainItemRoundTripsAllThreeKinds() async throws {
    let database = try AppDatabase.inMemory()
    let repository = GRDBBrainRepository(database: database)
    let now = Date(timeIntervalSince1970: 1_000)
    let statement = "自由最困难的部分是没有人能替你承担选择的后果。"

    let thought = BrainItem.thought(Thought(
        id: BrainItemID(rawValue: "thought-1"), title: "自由意味着责任",
        statement: statement,
        stage: .evolving, provenance: BrainProvenance(originEvidence: nil),
        createdAt: now, updatedAt: now
    ))
    let question = BrainItem.question(Question(
        id: BrainItemID(rawValue: "question-1"),
        question: "理解一个人是否意味着认同他？",
        state: .exploring, provenance: BrainProvenance(originEvidence: nil),
        createdAt: now.addingTimeInterval(1), updatedAt: now.addingTimeInterval(1)
    ))
    let memory = BrainItem.memory(BrainMemory(
        id: BrainItemID(rawValue: "memory-1"),
        content: "用户倾向从责任角度理解自由",
        origin: .agentInferred, confidence: .medium, state: .needsReview,
        provenance: BrainProvenance(originEvidence: nil),
        createdAt: now.addingTimeInterval(2), updatedAt: now.addingTimeInterval(2)
    ))
    for item in [thought, question, memory] {
        try await repository.save(item)
    }

    let all = try await repository.items()
    #expect(all.map(\.kind) == [.thought, .question, .memory])
    #expect(all.first?.id == thought.id)

    let thoughts = try await repository.items(kind: .thought)
    guard case .thought(let loadedThought) = try #require(thoughts.first) else {
        Issue.record("expected thought")
        return
    }
    #expect(loadedThought.title == "自由意味着责任")
    #expect(loadedThought.statement == statement)
    #expect(loadedThought.stage == .evolving)

    #expect(try await repository.item(id: question.id) != nil)
    try await repository.delete(id: question.id)
    #expect(try await repository.item(id: question.id) == nil)
    #expect(try await repository.items(kind: .question).isEmpty)
}

@Test func perKindStateConstraintRejectsIllegalRows() async throws {
    let database = try AppDatabase.inMemory()
    // The domain model cannot even express a memory with a thought-only state,
    // so the storage CHECK is exercised with a raw insert.
    await #expect(throws: Error.self) {
        try await database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO brainItems (id, kind, title, content, state, origin, confidence, schemaVersion, createdAt, updatedAt)
                VALUES ('bad-1', 'memory', NULL, '内容', 'evolving', 'agentInferred', 'medium', 1, ?, ?)
                """, arguments: [Date(), Date()])
        }
    }
    await #expect(throws: Error.self) {
        try await database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO brainItems (id, kind, title, content, state, origin, confidence, schemaVersion, createdAt, updatedAt)
                VALUES ('bad-2', 'unknown', NULL, '内容', 'open', NULL, NULL, 1, ?, ?)
                """, arguments: [Date(), Date()])
        }
    }
}

@Test func memoriesBackfillIntoBrainItemsDeterministically() async throws {
    let database = try AppDatabase.inMemory()
    let memories = GRDBMemoryRepository(database: database)
    try await memories.save(ReaderMemory(kind: .semantic, claim: "待确认的记忆", confidence: 0.6, status: .provisional))
    try await memories.save(ReaderMemory(kind: .preference, claim: "高置信的偏好", confidence: 0.85, status: .active))
    try await memories.save(ReaderMemory(kind: .semantic, claim: "已退役的记忆", confidence: 0.4, status: .superseded))
    try await memories.save(ReaderMemory(kind: .episodic, claim: "用户改过的记忆", confidence: 0.9, status: .active, userEdited: true))

    try await database.writer.write { db in try AppDatabase.backfillBrainItems(db) }
    // Idempotent: re-running the backfill must not duplicate rows.
    try await database.writer.write { db in try AppDatabase.backfillBrainItems(db) }

    let repository = GRDBBrainRepository(database: database)
    let items = try await repository.items(kind: .memory)
    #expect(items.count == 4)
    let byContent = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, BrainMemory)? in
        guard case .memory(let memory) = item else { return nil }
        return (memory.content, memory)
    })
    #expect(byContent["待确认的记忆"]?.state == .needsReview)
    #expect(byContent["待确认的记忆"]?.confidence == .medium)
    #expect(byContent["高置信的偏好"]?.state == .active)
    #expect(byContent["高置信的偏好"]?.confidence == .high)
    #expect(byContent["已退役的记忆"]?.state == .superseded)
    #expect(byContent["已退役的记忆"]?.confidence == .low)
    for memory in byContent.values {
        #expect(memory.origin == .agentInferred)
        #expect(memory.provenance.originEvidence == nil)
    }
    // The legacy store keeps working untouched (MyMind switches in phase 13).
    #expect(try await memories.memories().count == 4)
}

@Test func backfilledMemoryKeepsSourceReflectionProvenanceAndCascades() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let book = TestFixtures.book()
    try await books.insert(book)
    let reflection = Reflection(bookID: book.id, originalText: "来源反思", inputKind: .text)
    try await reflections.insert(reflection, linkedHighlightIDs: [], evidence: [])

    let memories = GRDBMemoryRepository(database: database)
    try await memories.save(ReaderMemory(
        sourceReflectionID: reflection.id, kind: .semantic,
        claim: "有据可依的记忆", confidence: 0.7, status: .provisional
    ))
    try await database.writer.write { db in try AppDatabase.backfillBrainItems(db) }

    let repository = GRDBBrainRepository(database: database)
    let item = try #require(try await repository.items(kind: .memory).first)
    guard case .memory(let memory) = item else {
        Issue.record("expected memory")
        return
    }
    #expect(memory.provenance.originEvidence == .reflection(reflection.id.description))

    // The brainItems.sourceReflectionID cascade mirrors the legacy behavior:
    // deleting the source reflection removes the derived memory.
    try await reflections.delete(id: reflection.id)
    #expect(try await repository.items(kind: .memory).isEmpty)
}

@Test func wipeAllUserDataRemovesBrainItems() async throws {
    let database = try AppDatabase.inMemory()
    let repository = GRDBBrainRepository(database: database)
    try await repository.save(.question(Question(
        id: BrainItemID(rawValue: "question-wipe"),
        question: "擦除前的问题", state: .open,
        provenance: BrainProvenance(originEvidence: nil),
        createdAt: Date(), updatedAt: Date()
    )))

    try await database.wipeAllUserData()
    #expect(try await repository.items().isEmpty)
}

@Test func emptyContentIsRejectedBeforeItReachesTheDatabase() async throws {
    let database = try AppDatabase.inMemory()
    let repository = GRDBBrainRepository(database: database)
    do {
        try await repository.save(.thought(Thought(
            id: BrainItemID(rawValue: "thought-blank"), title: "空白",
            statement: "   ", stage: .emerging,
            provenance: BrainProvenance(originEvidence: nil),
            createdAt: Date(), updatedAt: Date()
        )))
        Issue.record("expected emptyContent error")
    } catch let error as BrainItemValidationError {
        #expect(error == .emptyContent)
    }
}

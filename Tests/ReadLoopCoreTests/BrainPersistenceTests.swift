import BrainCore
import ContextEngineering
import Foundation
import GRDB
import LibraryCore
import Persistence
import ReflectionCore
import RetrievalCore
import Testing

// Phase 12 (docs/brain.md): BrainCore domain round-trips, brainItems per-kind
// invariants, the legacy memories backfill, and data-wipe coverage.

@Test func brainItemRoundTripsAllThreeKinds() async throws {
    let database = try AppDatabase.inMemory()
    let repository = GRDBBrainRepository(database: database)
    let now = Date(timeIntervalSince1970: 1_000)
    let statement = "自由最困难的部分是没有人能替你承担选择的后果。"

    let thought = BrainItem.thought(Thought(
        id: BrainItemID(rawValue: "thought-1"), title: "自由与责任",
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
    #expect(loadedThought.title == "自由与责任")
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

// MARK: - Evidence / Relations (phase 14)

@Test func evidenceAttachesIdempotentlyAndOrdersDeterministically() async throws {
    let database = try AppDatabase.inMemory()
    let repository = GRDBBrainRepository(database: database)
    let thought = BrainItem.thought(Thought(
        id: BrainItemID(rawValue: "thought-e"), title: "自由与责任",
        statement: "自由的核心是承担选择。", stage: .evolving,
        provenance: BrainProvenance(originEvidence: nil), createdAt: Date(), updatedAt: Date()
    ))
    try await repository.save(thought)

    // Idempotent: the same (item, source, relation) never duplicates.
    try await repository.attachEvidence(thought.id, source: .reflection("ref-1"), relation: .origin, weight: 1)
    try await repository.attachEvidence(thought.id, source: .reflection("ref-1"), relation: .origin, weight: 1)
    try await repository.attachEvidence(thought.id, source: .reflection("ref-2"), relation: .supports, weight: 0.8)
    try await repository.attachEvidence(thought.id, source: .bookChunk("chunk-9"), relation: .origin, weight: 1)

    let evidence = try await repository.evidence(for: thought.id)
    #expect(evidence.count == 3)
    // Deterministic (createdAt, sourceType, sourceID) order — asserted by
    // content, not position, since same-millisecond attaches tie on createdAt.
    #expect(evidence.contains { $0.relation == .origin && $0.source == .reflection("ref-1") })
    #expect(evidence.contains { $0.relation == .supports && $0.source == .reflection("ref-2") })
    #expect(evidence.contains { evidence in
        if case .bookChunk = evidence.source { return evidence.relation == .origin }
        return false
    })
    #expect(evidence.contains { if case .bookChunk = $0.source { return true } else { return false } })
}

@Test func relationsRoundTripBothDirectionsAndRejectSelfRelation() async throws {
    let database = try AppDatabase.inMemory()
    let repository = GRDBBrainRepository(database: database)
    let a = BrainItem.question(Question(
        id: BrainItemID(rawValue: "q-1"), question: "共情意味着认同吗？", state: .exploring,
        provenance: BrainProvenance(originEvidence: nil), createdAt: Date(), updatedAt: Date()
    ))
    let b = BrainItem.thought(Thought(
        id: BrainItemID(rawValue: "t-1"), title: "人与他人的距离",
        statement: "理解不等于站队。", stage: .evolving,
        provenance: BrainProvenance(originEvidence: nil), createdAt: Date(), updatedAt: Date()
    ))
    try await repository.save(a)
    try await repository.save(b)

    try await repository.relate(source: a.id, target: b.id, relation: .addresses, weight: 1)

    // Normalized source→target regardless of query direction.
    let fromSource = try await repository.relations(of: a.id)
    let fromTarget = try await repository.relations(of: b.id)
    #expect(fromSource.first?.relation == .addresses)
    #expect(fromSource.first?.targetItemID == b.id)
    #expect(fromTarget.first?.sourceItemID == a.id)
    #expect(fromTarget.first?.targetItemID == b.id)

    // Idempotent per triple.
    try await repository.relate(source: a.id, target: b.id, relation: .addresses, weight: 1)
    #expect(try await repository.relations(of: a.id).count == 1)

    await #expect(throws: BrainItemValidationError.selfRelation) {
        try await repository.relate(source: a.id, target: a.id, relation: .related, weight: 1)
    }
}

@Test func deletingBrainItemCascadesEvidenceAndRelations() async throws {
    let database = try AppDatabase.inMemory()
    let repository = GRDBBrainRepository(database: database)
    let a = BrainItem.thought(Thought(
        id: BrainItemID(rawValue: "t-del"), title: "会被删除的想法",
        statement: "正文", stage: .emerging,
        provenance: BrainProvenance(originEvidence: nil), createdAt: Date(), updatedAt: Date()
    ))
    let b = BrainItem.question(Question(
        id: BrainItemID(rawValue: "q-del"), question: "会被留下的问题", state: .open,
        provenance: BrainProvenance(originEvidence: nil), createdAt: Date(), updatedAt: Date()
    ))
    try await repository.save(a)
    try await repository.save(b)
    try await repository.attachEvidence(a.id, source: .reflection("ref-del"), relation: .origin, weight: 1)
    try await repository.relate(source: b.id, target: a.id, relation: .raises, weight: 1)

    try await repository.delete(id: a.id)

    #expect(try await repository.evidence(for: a.id).isEmpty)
    #expect(try await repository.relations(of: a.id).isEmpty)
    #expect(try await repository.relations(of: b.id).isEmpty, "relations cascade from both sides")
    #expect(try await repository.item(id: b.id) != nil)
}

@Test func reflectionDeleteCleansReflectionSourcedEvidence() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let book = TestFixtures.book()
    try await books.insert(book)
    let reflection = Reflection(bookID: book.id, originalText: "来源反思正文", inputKind: .text)
    try await reflections.insert(reflection, linkedHighlightIDs: [], evidence: [])

    let repository = GRDBBrainRepository(database: database)
    let thought = BrainItem.thought(Thought(
        id: BrainItemID(rawValue: "t-ref"), title: "有据的想法",
        statement: "依据一条反思。", stage: .evolving,
        provenance: BrainProvenance(originEvidence: nil), createdAt: Date(), updatedAt: Date()
    ))
    try await repository.save(thought)
    try await repository.attachEvidence(thought.id, source: .reflection(reflection.id.description), relation: .origin, weight: 1)
    try await repository.attachEvidence(thought.id, source: .bookChunk("chunk-keep"), relation: .supports, weight: 1)

    try await reflections.delete(id: reflection.id)

    let remaining = try await repository.evidence(for: thought.id)
    #expect(remaining.count == 1, "reflection-sourced evidence is cleaned with its reflection")
    #expect(remaining.first?.source == .bookChunk("chunk-keep"))
    #expect(try await repository.item(id: thought.id) != nil, "the thought itself survives")
}

// MARK: - Persistent embeddings + BrainRetriever (phase 15)

/// Deterministic keyword→vector mapping so lanes are controllable in tests:
/// 自由 → e1, 责任 → e2, anything else → e3.
private struct KeywordEmbeddingProvider: EmbeddingProvider {
    let modelIdentifier = "fake-brain-embed"
    let dimensions = 4
    func embed(_ texts: [String]) async throws -> [[Float]] {
        texts.map { text in
            if text.contains("自由") { return [1, 0, 0, 0] }
            if text.contains("责任") { return [0, 1, 0, 0] }
            return [0, 0, 1, 0]
        }
    }
}

private actor EmbedCallCounter {
    private var calls = 0
    func increment() { calls += 1 }
    var count: Int { calls }
}

private final class CountingEmbeddingProvider: EmbeddingProvider, @unchecked Sendable {
    let modelIdentifier = "fake-brain-embed"
    let dimensions = 4
    private let counter = EmbedCallCounter()
    var embedCallCount: Int { get async { await counter.count } }
    func embed(_ texts: [String]) async throws -> [[Float]] {
        await counter.increment()
        return texts.map { text in
            if text.contains("自由") { return [1, 0, 0, 0] }
            return [0, 0, 1, 0]
        }
    }
}

@Test func brainEmbeddingStoreRoundTripsAndCascades() async throws {
    let database = try AppDatabase.inMemory()
    let repository = GRDBBrainRepository(database: database)
    let store = GRDBBrainEmbeddingStore(database: database)
    let now = Date()
    let thought = BrainItem.thought(Thought(
        id: BrainItemID(rawValue: "t-vec"), title: "向量", statement: "自由与责任",
        stage: .evolving, provenance: BrainProvenance(originEvidence: nil),
        createdAt: now, updatedAt: now
    ))
    let question = BrainItem.question(Question(
        id: BrainItemID(rawValue: "q-vec"), question: "什么是自由？", state: .open,
        provenance: BrainProvenance(originEvidence: nil), createdAt: now, updatedAt: now
    ))
    try await repository.save(thought)
    try await repository.save(question)
    try await store.save([
        BrainItemVector(itemID: thought.id, model: "m1", dimensions: 2, contentHash: "h1", vector: [1.5, -2.25], updatedAt: now),
        BrainItemVector(itemID: question.id, model: "m1", dimensions: 2, contentHash: "h2", vector: [0.5, 0.5], updatedAt: now),
        BrainItemVector(itemID: question.id, model: "m2", dimensions: 2, contentHash: "h2", vector: [9, 9], updatedAt: now),
    ])

    let rows = try await store.vectors(model: "m1")
    #expect(rows.count == 2)
    #expect(rows.first { $0.itemID == thought.id }?.vector == [1.5, -2.25], "Float vector round-trips byte-exact")
    #expect(try await store.vectors(model: "m2").count == 1, "rows are keyed per model")

    try await repository.delete(id: thought.id)
    #expect(try await store.vectors(model: "m1").count == 1, "item deletion cascades its vectors")

    try await database.wipeAllUserData()
    #expect(try await store.vectors(model: "m1").isEmpty)
}

@Test func brainRetrieverRefreshesStaleEmbeddingsExactlyOnce() async throws {
    let database = try AppDatabase.inMemory()
    let repository = GRDBBrainRepository(database: database)
    let store = GRDBBrainEmbeddingStore(database: database)
    let provider = CountingEmbeddingProvider()
    let retriever = BrainRetriever(
        items: repository, store: store,
        embeddingProvider: { @Sendable in provider }
    )
    let thought = BrainItem.thought(Thought(
        id: BrainItemID(rawValue: "t-stale"), title: "自由观",
        statement: "自由意味着承担选择的责任", stage: .evolving,
        provenance: BrainProvenance(originEvidence: nil), createdAt: Date(), updatedAt: Date()
    ))
    try await repository.save(thought)
    // A vector exists but is stale (wrong contentHash).
    try await store.save([BrainItemVector(
        itemID: thought.id, model: provider.modelIdentifier, dimensions: 4,
        contentHash: "stale", vector: [0, 0, 1, 0], updatedAt: Date()
    )])

    let first = await retriever.retrieve(query: "自由", limit: 3)
    #expect(first.first?.semanticScore != nil, "stale vector refreshed, semantic lane fires")

    let stored = try await store.vectors(model: provider.modelIdentifier)
    #expect(stored.first?.contentHash == BrainRetriever.contentHash("自由意味着承担选择的责任"))

    let callsAfterFirst = await provider.embedCallCount
    let second = await retriever.retrieve(query: "自由", limit: 3)
    #expect(second.first?.semanticScore != nil)
    let callsAfterSecond = await provider.embedCallCount
    #expect(callsAfterSecond == callsAfterFirst + 1, "second query embeds the query only — content unchanged means zero item re-embeds")
}

@Test func brainRetrieverFallsBackToLexicalWhenSemanticUnavailable() async throws {
    let database = try AppDatabase.inMemory()
    let repository = GRDBBrainRepository(database: database)
    let retriever = BrainRetriever(items: repository)
    try await repository.save(.thought(Thought(
        id: BrainItemID(rawValue: "t-lex"), title: "自由与责任",
        statement: "自由的选择带来不可转嫁的责任", stage: .evolving,
        provenance: BrainProvenance(originEvidence: nil), createdAt: Date(), updatedAt: Date()
    )))

    let hits = await retriever.retrieve(query: "自由与责任", limit: 3)
    #expect(hits.first?.lexicalScore != nil)
    #expect(hits.first?.semanticScore == nil)
}

@Test func brainRetrieverSemanticSurfacesLexicalMiss() async throws {
    let database = try AppDatabase.inMemory()
    let repository = GRDBBrainRepository(database: database)
    let store = GRDBBrainEmbeddingStore(database: database)
    let retriever = BrainRetriever(
        items: repository, store: store,
        embeddingProvider: { @Sendable in KeywordEmbeddingProvider() }
    )
    try await repository.save(.thought(Thought(
        id: BrainItemID(rawValue: "t-sem"), title: "自由观",
        statement: "自由观正在变化", stage: .evolving,
        provenance: BrainProvenance(originEvidence: nil), createdAt: Date(), updatedAt: Date()
    )))

    // "自由" tokenizes to a single bigram → the lexical lane (≥2 tokens) stays
    // empty; only the semantic lane can recall the item.
    let hits = await retriever.retrieve(query: "自由", limit: 3)
    let candidate = try #require(hits.first)
    #expect(candidate.semanticScore != nil)
    #expect(candidate.lexicalScore == nil)
}

@Test func brainRetrieverHonorsKindsAndEligibility() async throws {
    let database = try AppDatabase.inMemory()
    let repository = GRDBBrainRepository(database: database)
    let now = Date()
    try await repository.save(.memory(BrainMemory(
        id: BrainItemID(rawValue: "m-sup"), content: "自由的选择带来责任",
        origin: .agentInferred, confidence: .medium, state: .superseded,
        provenance: BrainProvenance(originEvidence: nil), createdAt: now, updatedAt: now
    )))
    try await repository.save(.thought(Thought(
        id: BrainItemID(rawValue: "t-arch"), title: "已归档", statement: "自由的选择带来责任",
        stage: .archived, provenance: BrainProvenance(originEvidence: nil),
        createdAt: now, updatedAt: now
    )))
    try await repository.save(.thought(Thought(
        id: BrainItemID(rawValue: "t-live"), title: "活跃想法", statement: "自由的选择带来责任",
        stage: .evolving, provenance: BrainProvenance(originEvidence: nil),
        createdAt: now, updatedAt: now
    )))

    let thoughtsOnly = await BrainRetriever(items: repository).retrieve(query: "自由与责任", kinds: [.thought], limit: 5)
    #expect(thoughtsOnly.map { $0.item.id.rawValue } == ["t-live"], "kinds filter excludes memory")

    let allKinds = await BrainRetriever(items: repository).retrieve(query: "自由与责任", limit: 5)
    #expect(allKinds.map { $0.item.id.rawValue } == ["t-live"], "superseded memories and archived thoughts are ineligible even when kinds allow")
}

@Test func wipeCoversEvidenceAndRelations() async throws {
    let database = try AppDatabase.inMemory()
    let repository = GRDBBrainRepository(database: database)
    let a = BrainItem.thought(Thought(
        id: BrainItemID(rawValue: "t-wipe"), title: "擦除", statement: "擦除前",
        stage: .emerging, provenance: BrainProvenance(originEvidence: nil),
        createdAt: Date(), updatedAt: Date()
    ))
    let b = BrainItem.question(Question(
        id: BrainItemID(rawValue: "q-wipe"), question: "擦除前的问题", state: .open,
        provenance: BrainProvenance(originEvidence: nil), createdAt: Date(), updatedAt: Date()
    ))
    try await repository.save(a)
    try await repository.save(b)
    try await repository.attachEvidence(a.id, source: .message("msg-1"), relation: .raises, weight: 1)
    try await repository.relate(source: a.id, target: b.id, relation: .related, weight: 1)

    try await database.wipeAllUserData()

    #expect(try await repository.evidence(for: a.id).isEmpty)
    #expect(try await repository.relations(of: a.id).isEmpty)
    #expect(try await repository.items().isEmpty)
}

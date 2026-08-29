import BrainCore
import Foundation
import GRDB

/// GRDB-backed `BrainRepository` (docs/brain.md, phase 12). The `brainItems`
/// table stores all three kinds; per-kind state CHECKs plus the decode-time
/// guard below keep the strong-typed domain honest. Legacy `memories` rows are
/// carried over once by the v21 migration and stay untouched until the MyMind
/// UI switches in phase 13.
public final class GRDBBrainRepository: BrainRepository, @unchecked Sendable {
    private let db: AppDatabase
    public init(database: AppDatabase) { db = database }

    public func items() async throws -> [BrainItem] {
        try await db.writer.read { db in
            try BrainItemRecord.order(Column("createdAt"), Column("id")).fetchAll(db).map { try $0.domain() }
        }
    }

    public func items(kind: BrainItemKind) async throws -> [BrainItem] {
        try await db.writer.read { db in
            try BrainItemRecord.filter(Column("kind") == kind.rawValue)
                .order(Column("createdAt"), Column("id")).fetchAll(db).map { try $0.domain() }
        }
    }

    public func item(id: BrainItemID) async throws -> BrainItem? {
        try await db.writer.read { db in
            guard let record = try BrainItemRecord.fetchOne(db, key: id.rawValue) else { return nil }
            return try record.domain()
        }
    }

    public func save(_ item: BrainItem) async throws {
        guard !item.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BrainItemValidationError.emptyContent
        }
        try await db.writer.write { db in try BrainItemRecord(item).save(db) }
    }

    public func delete(id: BrainItemID) async throws {
        _ = try await db.writer.write { db in try BrainItemRecord.deleteOne(db, key: id.rawValue) }
    }

    // MARK: Evidence (docs/brain.md §4)

    public func evidence(for itemID: BrainItemID) async throws -> [BrainEvidence] {
        try await db.writer.read { db in
            try BrainEvidenceRecord
                .filter(Column("brainItemID") == itemID.rawValue)
                .order(Column("createdAt"), Column("sourceType"), Column("sourceID"))
                .fetchAll(db)
                .map { try $0.domain() }
        }
    }

    public func attachEvidence(_ itemID: BrainItemID, source: BrainEvidenceSource, relation: EvidenceRelation, weight: Double) async throws {
        try await db.writer.write { db in
            try BrainEvidenceRecord(itemID: itemID, source: source, relation: relation, weight: weight, createdAt: Date())
                .insert(db, onConflict: .ignore)
        }
    }

    // MARK: Relations (docs/brain.md §5)

    public func relations(of itemID: BrainItemID) async throws -> [BrainRelation] {
        try await db.writer.read { db in
            // Rows are stored in their canonical direction (relate() writes
            // source→target as given); queries from either side return them
            // unchanged so semantics like "question addresses thought" survive.
            let rows = try BrainRelationRecord
                .filter(Column("sourceItemID") == itemID.rawValue || Column("targetItemID") == itemID.rawValue)
                .fetchAll(db)
            return try rows
                .map { try $0.domain() }
                .sorted { lhs, rhs in
                    if lhs.relation.rawValue != rhs.relation.rawValue { return lhs.relation.rawValue < rhs.relation.rawValue }
                    return lhs.targetItemID.rawValue < rhs.targetItemID.rawValue
                }
        }
    }

    public func relate(source: BrainItemID, target: BrainItemID, relation: BrainRelationType, weight: Double) async throws {
        guard source != target else { throw BrainItemValidationError.selfRelation }
        try await db.writer.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO brainItemRelations (sourceItemID, targetItemID, relation, weight, createdAt)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [source.rawValue, target.rawValue, relation.rawValue, weight, Date()]
            )
        }
    }

    // MARK: Revisions (docs/brain.md §10)

    public func revisions(for itemID: BrainItemID) async throws -> [BrainItemRevision] {
        try await db.writer.read { db in
            try BrainItemRevisionRecord
                .filter(Column("brainItemID") == itemID.rawValue)
                .order(Column("revision").desc)
                .fetchAll(db)
                .map { try $0.domain() }
        }
    }

    public func recordRevision(itemID: BrainItemID, content: String, triggerEvidenceID: String?) async throws {
        try await db.writer.write { db in
            let count = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM brainItemRevisions WHERE brainItemID = ?",
                arguments: [itemID.rawValue]
            ) ?? 0
            try db.execute(
                sql: """
                INSERT INTO brainItemRevisions (brainItemID, revision, content, triggerEvidenceID, createdAt)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [itemID.rawValue, count + 1, content, triggerEvidenceID, Date()]
            )
        }
    }
}

private struct BrainItemRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "brainItems"
    var id, kind, content, state: String
    var title: String?
    var origin: String?
    var confidence: String?
    var sourceReflectionID: String?
    var contentHash: String?
    var schemaVersion: Int
    var createdAt, updatedAt: Date

    init(_ item: BrainItem) {
        id = item.id.rawValue
        kind = item.kind.rawValue
        schemaVersion = 1
        contentHash = nil
        // sourceReflectionID is RESERVED for the v21 legacy-backfill snapshot;
        // new items carry provenance in brainItemEvidence (soft-dangling by
        // design — deleting a reflection must not vaporize a formed memory).
        sourceReflectionID = nil
        switch item {
        case .thought(let thought):
            title = thought.title
            content = thought.statement
            state = thought.stage.rawValue
            origin = nil
            confidence = nil
            createdAt = thought.createdAt
            updatedAt = thought.updatedAt
        case .question(let question):
            title = nil
            content = question.question
            state = question.state.rawValue
            origin = nil
            confidence = nil
            createdAt = question.createdAt
            updatedAt = question.updatedAt
        case .memory(let memory):
            title = nil
            content = memory.content
            state = memory.state.rawValue
            origin = memory.origin.rawValue
            confidence = memory.confidence.rawValue
            createdAt = memory.createdAt
            updatedAt = memory.updatedAt
        }
    }

    func domain() throws -> BrainItem {
        let provenance = BrainProvenance(
            originEvidence: sourceReflectionID.map { BrainEvidenceSource.reflection($0) }
        )
        switch kind {
        case "memory":
            guard let origin = origin.flatMap(MemoryOrigin.init(rawValue:)),
                  let confidence = confidence.flatMap(MemoryConfidence.init(rawValue:)),
                  let state = MemoryState(rawValue: state) else {
                throw BrainItemValidationError.stateMismatch
            }
            return .memory(BrainMemory(
                id: BrainItemID(rawValue: id), content: content,
                origin: origin, confidence: confidence, state: state,
                provenance: provenance, createdAt: createdAt, updatedAt: updatedAt
            ))
        case "thought":
            guard let title, let stage = ThoughtStage(rawValue: state) else {
                throw BrainItemValidationError.stateMismatch
            }
            return .thought(Thought(
                id: BrainItemID(rawValue: id), title: title, statement: content,
                stage: stage, provenance: provenance, createdAt: createdAt, updatedAt: updatedAt
            ))
        case "question":
            guard let state = QuestionState(rawValue: state) else {
                throw BrainItemValidationError.stateMismatch
            }
            return .question(Question(
                id: BrainItemID(rawValue: id), question: content, state: state,
                provenance: provenance, createdAt: createdAt, updatedAt: updatedAt
            ))
        default:
            throw BrainItemValidationError.stateMismatch
        }
    }
}

/// GRDB-backed `BrainEmbeddingStore`. Vectors are stored per (item, model);
/// a model switch keeps old rows, and item deletion cascades via FK.
public final class GRDBBrainEmbeddingStore: BrainEmbeddingStore, @unchecked Sendable {
    private let db: AppDatabase
    public init(database: AppDatabase) { db = database }

    public func vectors(model: String) async throws -> [BrainItemVector] {
        try await db.writer.read { db in
            try BrainItemVectorRecord
                .filter(Column("model") == model)
                .order(Column("updatedAt"))
                .fetchAll(db)
                .map { try $0.domain() }
        }
    }

    public func save(_ vectors: [BrainItemVector]) async throws {
        guard !vectors.isEmpty else { return }
        try await db.writer.write { db in
            for vector in vectors {
                try BrainItemVectorRecord(vector).save(db)
            }
        }
    }
}

private struct BrainItemVectorRecord: Codable, FetchableRecord, PersistableRecord {    static let databaseTableName = "brainItemEmbeddings"
    var brainItemID: String
    var model: String
    var dimensions: Int
    var contentHash: String
    var vector: Data
    var updatedAt: Date

    init(_ vector: BrainItemVector) {
        brainItemID = vector.itemID.rawValue
        model = vector.model
        dimensions = vector.dimensions
        contentHash = vector.contentHash
        self.vector = Self.encode(vector.vector)
        updatedAt = vector.updatedAt
    }

    func domain() throws -> BrainItemVector {
        guard let decoded = Self.decode(vector, dimensions: dimensions) else {
            throw BrainItemValidationError.stateMismatch
        }
        return BrainItemVector(
            itemID: BrainItemID(rawValue: brainItemID), model: model,
            dimensions: dimensions, contentHash: contentHash,
            vector: decoded, updatedAt: updatedAt
        )
    }

    private static func encode(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func decode(_ data: Data, dimensions: Int) -> [Float]? {
        guard data.count == dimensions * MemoryLayout<Float>.size else { return nil }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}

private extension BrainItem {
    var content: String {
        switch self {
        case .thought(let item): item.statement
        case .question(let item): item.question
        case .memory(let item): item.content
        }
    }
}

private struct BrainEvidenceRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "brainItemEvidence"
    var id: Int64?
    var brainItemID: String
    var sourceType: String
    var sourceID: String
    var relation: String
    var weight: Double
    var createdAt: Date

    init(itemID: BrainItemID, source: BrainEvidenceSource, relation: EvidenceRelation, weight: Double, createdAt: Date) {
        id = nil
        brainItemID = itemID.rawValue
        switch source {
        case .reflection(let id): sourceType = "reflection"; sourceID = id
        case .bookChunk(let id): sourceType = "bookChunk"; sourceID = id
        case .message(let id): sourceType = "message"; sourceID = id
        }
        self.relation = relation.rawValue
        self.weight = weight
        self.createdAt = createdAt
    }

    func domain() throws -> BrainEvidence {
        guard let source = Self.source(sourceType: sourceType, sourceID: sourceID),
              let relation = EvidenceRelation(rawValue: relation) else {
            throw BrainItemValidationError.stateMismatch
        }
        return BrainEvidence(
            itemID: BrainItemID(rawValue: brainItemID), source: source,
            relation: relation, weight: weight, createdAt: createdAt
        )
    }

    private static func source(sourceType: String, sourceID: String) -> BrainEvidenceSource? {
        switch sourceType {
        case "reflection": .reflection(sourceID)
        case "bookChunk": .bookChunk(sourceID)
        case "message": .message(sourceID)
        default: nil
        }
    }
}

private struct BrainRelationRecord: Codable, FetchableRecord, TableRecord {
    static let databaseTableName = "brainItemRelations"
    var sourceItemID: String
    var targetItemID: String
    var relation: String
    var weight: Double
    var createdAt: Date

    func domain() throws -> BrainRelation {
        guard let relation = BrainRelationType(rawValue: relation) else {
            throw BrainItemValidationError.stateMismatch
        }
        return BrainRelation(
            sourceItemID: BrainItemID(rawValue: sourceItemID),
            targetItemID: BrainItemID(rawValue: targetItemID),
            relation: relation, weight: weight, createdAt: createdAt
        )
    }
}

private struct BrainItemRevisionRecord: Codable, FetchableRecord, TableRecord {
    static let databaseTableName = "brainItemRevisions"
    var brainItemID: String
    var revision: Int
    var content: String
    var triggerEvidenceID: String?
    var createdAt: Date

    func domain() throws -> BrainItemRevision {
        BrainItemRevision(
            itemID: BrainItemID(rawValue: brainItemID), revision: revision,
            content: content, triggerEvidenceID: triggerEvidenceID, createdAt: createdAt
        )
    }
}

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
        // Typed provenance moves to brainItemEvidence in phase 14; the memory
        // backfill's source reflection is the one provenance this phase keeps.
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
            if case .reflection(let reflectionID) = memory.provenance.originEvidence {
                sourceReflectionID = reflectionID
            }
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

private extension BrainItem {
    var content: String {
        switch self {
        case .thought(let item): item.statement
        case .question(let item): item.question
        case .memory(let item): item.content
        }
    }
}

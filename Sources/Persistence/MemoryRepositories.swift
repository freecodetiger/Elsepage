import Foundation
import GRDB
import ReflectionCore

public final class GRDBMemoryRepository: MemoryRepository, @unchecked Sendable {
    private let db: AppDatabase
    public init(database: AppDatabase) { db = database }

    public func memories() async throws -> [ReaderMemory] {
        try await db.writer.read { db in
            try MemoryRecord.order(Column("createdAt"), Column("id")).fetchAll(db).map { try $0.domain() }
        }
    }

    public func memories(kind: MemoryKind) async throws -> [ReaderMemory] {
        try await db.writer.read { db in
            try MemoryRecord.filter(Column("kind") == kind.rawValue)
                .order(Column("createdAt"), Column("id")).fetchAll(db).map { try $0.domain() }
        }
    }

    public func save(_ memory: ReaderMemory) async throws {
        try await db.writer.write { db in try MemoryRecord(memory).save(db) }
    }

    public func delete(id: UUID) async throws {
        _ = try await db.writer.write { db in try MemoryRecord.deleteOne(db, key: id.uuidString.lowercased()) }
    }

    public func deleteAll() async throws {
        try await db.writer.write { db in try db.execute(sql: "DELETE FROM memories") }
    }

    public func markInaccurate(id: UUID) async throws {
        try await db.writer.write { db in
            try db.execute(
                sql: "UPDATE memories SET status = 'superseded', updatedAt = ? WHERE id = ?",
                arguments: [Date(), id.uuidString.lowercased()]
            )
        }
    }
}

private struct MemoryRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "memories"
    var id, kind, claim, status: String
    var sourceReflectionID: String?
    var confidence: Double
    var userEdited: Bool
    var evidenceIDsJSON: Data
    var createdAt, updatedAt: Date

    init(_ memory: ReaderMemory) {
        id = memory.id.uuidString.lowercased()
        sourceReflectionID = memory.sourceReflectionID?.description
        kind = memory.kind.rawValue
        claim = memory.claim
        confidence = memory.confidence
        status = memory.status.rawValue
        userEdited = memory.userEdited
        evidenceIDsJSON = (try? JSONEncoder().encode(memory.evidenceIDs)) ?? Data("[]".utf8)
        createdAt = memory.createdAt
        updatedAt = memory.updatedAt
    }

    func domain() throws -> ReaderMemory {
        guard let decodedID = UUID(uuidString: id),
              let decodedKind = MemoryKind(rawValue: kind),
              let decodedStatus = MemoryStatus(rawValue: status) else {
            throw PersistenceError.corruptRecord(table: Self.databaseTableName, recordID: id, field: "identity")
        }
        let reflection: ReflectionID?
        if let sourceReflectionID {
            guard let uuid = UUID(uuidString: sourceReflectionID) else {
                throw PersistenceError.corruptRecord(table: Self.databaseTableName, recordID: id, field: "sourceReflectionID")
            }
            reflection = ReflectionID(rawValue: uuid)
        } else {
            reflection = nil
        }
        let decodedEvidence: [String]
        do {
            decodedEvidence = try JSONDecoder().decode([String].self, from: evidenceIDsJSON)
        } catch {
            throw PersistenceError.corruptRecord(table: Self.databaseTableName, recordID: id, field: "evidenceIDsJSON")
        }
        return ReaderMemory(
            id: decodedID,
            sourceReflectionID: reflection,
            kind: decodedKind,
            claim: claim,
            confidence: confidence,
            status: decodedStatus,
            userEdited: userEdited,
            evidenceIDs: decodedEvidence,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

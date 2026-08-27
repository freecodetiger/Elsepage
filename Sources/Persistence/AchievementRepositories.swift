import AchievementCore
import Foundation
import GRDB
import LibraryCore
import ReflectionCore

public final class GRDBAchievementRepository: AchievementRepository, @unchecked Sendable {
    private let db: AppDatabase
    public init(database: AppDatabase) { db = database }

    public func unlocked() async throws -> [AchievementRecord] {
        try await db.writer.read { db in
            try AchievementRow.order(Column("unlockedAt"), Column("id")).fetchAll(db).map { try $0.domain() }
        }
    }

    public func insert(_ record: AchievementRecord) async throws {
        try await db.writer.write { db in try AchievementRow(record).save(db) }
    }
}

private struct AchievementRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "achievements"
    var id: String
    var unlockedAt: Date
    var sourceReflectionID: String?
    var bookID: String?

    init(_ record: AchievementRecord) {
        id = record.id.rawValue
        unlockedAt = record.unlockedAt
        sourceReflectionID = record.source?.reflectionID?.description
        bookID = record.source?.bookID?.description
    }

    func domain() throws -> AchievementRecord {
        guard let decodedID = AchievementID(rawValue: id) else {
            throw PersistenceError.corruptRecord(table: Self.databaseTableName, recordID: id, field: "id")
        }
        let source: AchievementSource?
        if let sourceReflectionID, let bookID,
           let reflectionUUID = UUID(uuidString: sourceReflectionID),
           let bookUUID = UUID(uuidString: bookID) {
            source = AchievementSource(
                reflectionID: ReflectionID(rawValue: reflectionUUID),
                bookID: BookID(rawValue: bookUUID)
            )
        } else {
            source = nil
        }
        return AchievementRecord(id: decodedID, unlockedAt: unlockedAt, source: source)
    }
}

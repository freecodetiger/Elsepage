import ContextRouting
import Foundation
import GRDB

/// GRDB-backed `RoutingTraceRepository`. Traces are derived diagnostics; the
/// full `ContextPlanTrace` is stored as a single JSON column so shape changes
/// stay forward-compatible and decoding is lossless. Personal-app trace volume
/// is small, so diagnostics aggregate in Swift rather than in SQL.
public struct GRDBRoutingTraceRepository: RoutingTraceRepository, @unchecked Sendable {
    private let db: AppDatabase

    public init(database: AppDatabase) {
        db = database
    }

    public func save(_ trace: ContextPlanTrace) async throws {
        try await db.writer.write { db in
            try RoutingTraceRecord(
                id: trace.id.uuidString.lowercased(),
                reflectionID: trace.reflectionID,
                createdAt: trace.createdAt,
                traceJSON: try JSONEncoder().encode(trace)
            ).insert(db)
        }
    }

    public func latestTrace(for reflectionID: String) async throws -> ContextPlanTrace? {
        try await db.writer.read { db in
            guard let record = try RoutingTraceRecord
                .filter(Column("reflectionID") == reflectionID)
                .order(Column("createdAt").desc, Column("id").desc)
                .fetchOne(db) else { return nil }
            return try JSONDecoder().decode(ContextPlanTrace.self, from: record.traceJSON)
        }
    }

    public func diagnostics() async throws -> RoutingTraceDiagnostics {
        try await db.writer.read { db in
            let traces = try RoutingTraceRecord.fetchAll(db).map { record in
                try JSONDecoder().decode(ContextPlanTrace.self, from: record.traceJSON)
            }
            return RoutingTraceDiagnostics(traces: traces)
        }
    }
}

private struct RoutingTraceRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "routingTraces"
    var id: String
    var reflectionID: String
    var createdAt: Date
    var traceJSON: Data
}

import Foundation
import GRDB
import LibraryCore
import ReaderCore
import RetrievalCore

public final class GRDBBookIndexRepository: BookIndexRepository, @unchecked Sendable {
    private let database: AppDatabase
    public init(database: AppDatabase) { self.database = database }

    public func job(for bookID: BookID, version: Int) async throws -> BookIndexJob? {
        try await database.writer.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM bookIndexJobs WHERE bookID=? AND indexVersion=?", arguments: [bookID.description, version]) else { return nil }
            return BookIndexJob(bookID: bookID, indexVersion: version, state: BookIndexState(rawValue: row["state"]) ?? .failed,
                nextResourceOrdinal: row["nextResourceOrdinal"], lastError: row["lastError"], updatedAt: row["updatedAt"])
        }
    }

    public func save(job: BookIndexJob) async throws {
        try await database.writer.write { db in try db.execute(sql: """
            INSERT INTO bookIndexJobs(bookID,indexVersion,state,nextResourceOrdinal,lastError,updatedAt) VALUES(?,?,?,?,?,?)
            ON CONFLICT(bookID,indexVersion) DO UPDATE SET state=excluded.state,nextResourceOrdinal=excluded.nextResourceOrdinal,lastError=excluded.lastError,updatedAt=excluded.updatedAt
            """, arguments: [job.bookID.description, job.indexVersion, job.state.rawValue, job.nextResourceOrdinal, job.lastError, job.updatedAt]) }
    }

    public func replace(chunks: [BookChunk], for bookID: BookID, version: Int) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM bookChunksFTS WHERE bookID=?", arguments: [bookID.description])
            try db.execute(sql: "DELETE FROM bookChunks WHERE bookID=? AND indexVersion=?", arguments: [bookID.description, version])
            for chunk in chunks { try Self.insert(chunk, version: version, db: db) }
        }
    }

    public func replace(chunks: [BookChunk], inResource href: String, for bookID: BookID, version: Int) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM bookChunks WHERE bookID=? AND indexVersion=? AND resourceHref=?", arguments: [bookID.description, version, href])
            for chunk in chunks { try Self.insert(chunk, version: version, db: db) }
        }
    }

    public func replace(blocks: [BookTextBlock], inResource href: String, for bookID: BookID, version: Int) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM bookTextBlocks WHERE bookID=? AND indexVersion=? AND resourceHref=?", arguments: [bookID.description, version, href])
            try db.execute(sql: "DELETE FROM bookChapters WHERE bookID=? AND indexVersion=? AND resourceHref=?", arguments: [bookID.description, version, href])
            if let first = blocks.first {
                if let chapterID = first.chapterID {
                    try db.execute(sql: "INSERT OR REPLACE INTO bookChapters(bookID,indexVersion,id,title,resourceHref,ordinal) VALUES(?,?,?,?,?,?)", arguments: [bookID.description,version,chapterID,first.chapterTitle,href,first.resourceOrdinal])
                }
                for block in blocks where block.sectionID != nil {
                    try db.execute(sql: "INSERT OR REPLACE INTO bookSections(bookID,indexVersion,id,chapterID,title,ordinal) VALUES(?,?,?,?,?,?)", arguments: [bookID.description,version,block.sectionID!,block.chapterID,block.sectionTitle,block.ordinal])
                }
            }
            for block in blocks {
                try db.execute(sql: """
                    INSERT INTO bookTextBlocks(id,bookID,indexVersion,resourceHref,chapterID,sectionID,resourceOrdinal,ordinal,text,startLocatorJSON,endLocatorJSON,startHref,endHref,startProgression,endProgression)
                    VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                    """, arguments: [block.id.rawValue,bookID.description,version,href,block.chapterID,block.sectionID,block.resourceOrdinal,block.ordinal,block.text,block.startLocator.json,block.endLocator.json,block.startLocator.href,block.endLocator.href,block.startLocator.progression,block.endLocator.progression])
            }
        }
    }

    public func chunks(for bookID: BookID, version: Int) async throws -> [BookChunk] {
        try await database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM bookChunks WHERE bookID=? AND indexVersion=? ORDER BY resourceOrdinal,ordinal", arguments: [bookID.description, version]).map(Self.chunk)
        }
    }

    public func lexicalSearch(bookID: BookID, query: String, boundary: ReadingBoundary?, limit: Int, scope: BookRetrievalScope = .readSoFar) async throws -> [(BookChunk, Double)] {
        let terms = query.lowercased().split { !$0.isLetter && !$0.isNumber }
            .map(String.init).filter { $0.count >= 3 }
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        return try await database.writer.read { db in
            if terms.isEmpty {
                let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !needle.isEmpty else { return [] }
                var sql = "SELECT c.* FROM bookChunks c WHERE c.bookID=? AND instr(c.normalizedText, ?) > 0"
                var arguments: StatementArguments = [bookID.description, needle]
                if let boundary, scope == .currentResource {
                    sql += " AND c.resourceOrdinal = ? AND COALESCE(c.startProgression,0) <= ?"
                    arguments += [boundary.resourceOrdinal, boundary.progression ?? 1]
                } else if let boundary {
                    sql += " AND (c.resourceOrdinal < ? OR (c.resourceOrdinal = ? AND COALESCE(c.startProgression,0) <= ?))"
                    arguments += [boundary.resourceOrdinal, boundary.resourceOrdinal, boundary.progression ?? 1]
                }
                sql += " ORDER BY c.resourceOrdinal,c.ordinal LIMIT ?"; arguments += [max(0, limit)]
                return try Row.fetchAll(db, sql: sql, arguments: arguments).map { (try Self.chunk($0), 0.5) }
            }
            var sql = "SELECT c.*, bm25(bookChunksFTS) AS rank FROM bookChunksFTS f JOIN bookChunks c ON c.id=f.chunkID WHERE f.bookChunksFTS MATCH ? AND c.bookID=?"
            var arguments: StatementArguments = [terms.joined(separator: " OR "), bookID.description]
            if let boundary, scope == .currentResource {
                sql += " AND c.resourceOrdinal = ? AND COALESCE(c.startProgression,0) <= ?"
                arguments += [boundary.resourceOrdinal, boundary.progression ?? 1]
            } else if let boundary {
                sql += " AND (c.resourceOrdinal < ? OR (c.resourceOrdinal = ? AND COALESCE(c.startProgression,0) <= ?))"
                arguments += [boundary.resourceOrdinal, boundary.resourceOrdinal, boundary.progression ?? 1]
            }
            sql += " ORDER BY rank LIMIT ?"; arguments += [max(0, limit)]
            return try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
                let rank: Double = row["rank"]
                return (try Self.chunk(row), 1 / (1 + abs(rank)))
            }
        }
    }

    public func readingBoundary(bookID: BookID, locator: BookLocator) async throws -> ReadingBoundary? {
        try await database.writer.read { db in
            guard let ordinal = try Int.fetchOne(db, sql: "SELECT resourceOrdinal FROM bookChunks WHERE bookID=? AND resourceHref=? ORDER BY resourceOrdinal LIMIT 1", arguments: [bookID.description, locator.href]) else { return nil }
            return ReadingBoundary(resourceOrdinal: ordinal, progression: locator.progression)
        }
    }

    public func chapters(for bookID: BookID, from startLocator: BookLocator, to endLocator: BookLocator?) async throws -> [BookChapterRef] {
        try await database.writer.read { db in
            guard let lower = try Self.resourceOrdinal(bookID: bookID, href: startLocator.href, in: db) else { return [] }
            var upper = lower
            if let endLocator, let resolved = try Self.resourceOrdinal(bookID: bookID, href: endLocator.href, in: db) {
                upper = resolved
            }
            let start = min(lower, upper), end = max(lower, upper)
            return try Row.fetchAll(db, sql: """
                SELECT DISTINCT id, title, ordinal FROM bookChapters
                WHERE bookID=? AND indexVersion=? AND ordinal BETWEEN ? AND ?
                ORDER BY ordinal
                """, arguments: [bookID.description, BookIndexPipeline.currentVersion, start, end]).map { row in
                    BookChapterRef(id: row["id"], title: row["title"], resourceOrdinal: row["ordinal"])
                }
        }
    }

    private static func resourceOrdinal(bookID: BookID, href: String, in db: Database) throws -> Int? {
        let exact = try Int.fetchOne(db, sql: "SELECT resourceOrdinal FROM bookChunks WHERE bookID=? AND resourceHref=? ORDER BY resourceOrdinal LIMIT 1", arguments: [bookID.description, href])
        if let exact { return exact }
        let stripped = href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
        guard stripped != href else { return nil }
        return try Int.fetchOne(db, sql: "SELECT resourceOrdinal FROM bookChunks WHERE bookID=? AND resourceHref=? ORDER BY resourceOrdinal LIMIT 1", arguments: [bookID.description, stripped])
    }

    public func saveEmbeddings(_ embeddings: [BookChunkID: [Float]], model: String, dimensions: Int) async throws {
        try await database.writer.write { db in
            for (id, vector) in embeddings {
                guard vector.count == dimensions else { throw RetrievalError.invalidEmbeddings }
                try db.execute(sql: "INSERT OR REPLACE INTO bookChunkEmbeddings(chunkID,model,dimensions,vector) VALUES(?,?,?,?)", arguments: [id.rawValue, model, dimensions, Self.encode(vector)])
            }
        }
    }

    public func embeddings(bookID: BookID, model: String) async throws -> [BookChunkID: [Float]] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT e.chunkID,e.dimensions,e.vector FROM bookChunkEmbeddings e JOIN bookChunks c ON c.id=e.chunkID WHERE c.bookID=? AND e.model=?", arguments: [bookID.description, model])
            return try Dictionary(uniqueKeysWithValues: rows.map { row in
                let dimensions: Int = row["dimensions"], data: Data = row["vector"]
                return (BookChunkID(rawValue: row["chunkID"]), try Self.decode(data, dimensions: dimensions))
            })
        }
    }

    private static func insert(_ chunk: BookChunk, version: Int, db: Database) throws {
        let ids = try JSONEncoder().encode(chunk.sourceBlockIDs.map(\.rawValue))
        try db.execute(sql: """
            INSERT INTO bookChunks(id,bookID,indexVersion,resourceHref,chapterID,chapterTitle,sectionID,sectionTitle,resourceOrdinal,ordinal,text,normalizedText,startLocatorJSON,endLocatorJSON,startHref,endHref,startProgression,endProgression,startTotalProgression,endTotalProgression,sourceBlockIDsJSON)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, arguments: [chunk.id.rawValue,chunk.bookID.description,version,chunk.resourceHref,chunk.chapterID,chunk.chapterTitle,chunk.sectionID,chunk.sectionTitle,chunk.resourceOrdinal,chunk.ordinal,chunk.text,chunk.normalizedText,chunk.startLocator.json,chunk.endLocator.json,chunk.startLocator.href,chunk.endLocator.href,chunk.startLocator.progression,chunk.endLocator.progression,chunk.startLocator.totalProgression,chunk.endLocator.totalProgression,ids])
        try db.execute(sql: "INSERT INTO bookChunksFTS(chunkID,bookID,normalizedText) VALUES(?,?,?)", arguments: [chunk.id.rawValue,chunk.bookID.description,chunk.normalizedText])
    }

    private static func chunk(_ row: Row) throws -> BookChunk {
        let bookString: String = row["bookID"]
        guard let uuid = UUID(uuidString: bookString) else { throw PersistenceError.corruptRecord(table: "bookChunks", recordID: row["id"], field: "bookID") }
        let start = try BookLocator(json: row["startLocatorJSON"], href: row["startHref"], progression: row["startProgression"], totalProgression: row["startTotalProgression"])
        let end = try BookLocator(json: row["endLocatorJSON"], href: row["endHref"], progression: row["endProgression"], totalProgression: row["endTotalProgression"])
        let idsData: Data = row["sourceBlockIDsJSON"]
        return BookChunk(id: .init(rawValue: row["id"]), bookID: BookID(rawValue: uuid), resourceHref: row["resourceHref"],
            chapterID: row["chapterID"], chapterTitle: row["chapterTitle"], sectionID: row["sectionID"], sectionTitle: row["sectionTitle"],
            resourceOrdinal: row["resourceOrdinal"], ordinal: row["ordinal"], text: row["text"], normalizedText: row["normalizedText"],
            startLocator: start, endLocator: end, sourceBlockIDs: try JSONDecoder().decode([String].self, from: idsData).map(BookTextBlockID.init(rawValue:)))
    }

    private static func encode(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }
    private static func decode(_ data: Data, dimensions: Int) throws -> [Float] {
        guard data.count == dimensions * MemoryLayout<Float>.size else { throw RetrievalError.invalidEmbeddings }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}

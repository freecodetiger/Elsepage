import Foundation
import GRDB
import LibraryCore
import ReaderCore

public final class GRDBTextAnnotationRepository: TextAnnotationRepository, @unchecked Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func annotations(for bookID: BookID) async throws -> [TextAnnotation] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM textAnnotations WHERE bookID=? ORDER BY createdAt",
                arguments: [bookID.description]
            )
            return try rows.map { row in
                let annotationID = try annotationID(row)
                let notes = try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM annotationNotes WHERE annotationID=? ORDER BY createdAt",
                    arguments: [annotationID.uuidString.lowercased()]
                ).map { try noteEntry($0) }
                return try annotation(row, notes: notes)
            }
        }
    }

    public func save(annotation: TextAnnotation) async throws {
        try await database.writer.write { db in
            if annotation.isEmpty {
                try deleteRows(id: annotation.id, db: db)
                return
            }
            let row = TextAnnotationRow(annotation)
            try row.save(db)
            try db.execute(
                sql: "DELETE FROM annotationNotes WHERE annotationID=?",
                arguments: [annotation.id.uuidString.lowercased()]
            )
            for note in annotation.notes {
                try NoteEntryRow(annotationID: annotation.id, note: note).insert(db)
            }
            try mirrorLegacyLayers(annotation, db: db)
        }
    }

    public func deleteAnnotation(id: UUID) async throws {
        _ = try await database.writer.write { db in
            try deleteRows(id: id, db: db)
        }
    }

    private func deleteRows(id: UUID, db: Database) throws {
        let noteIDs = try String.fetchAll(
            db,
            sql: "SELECT id FROM annotationNotes WHERE annotationID=?",
            arguments: [id.uuidString.lowercased()]
        )
        for noteID in noteIDs {
            try db.execute(sql: "DELETE FROM notes WHERE id=?", arguments: [noteID])
        }
        try db.execute(sql: "DELETE FROM highlights WHERE id=?", arguments: [id.uuidString.lowercased()])
        try TextAnnotationRow.deleteOne(db, key: id.uuidString.lowercased())
    }

    private func mirrorLegacyLayers(_ annotation: TextAnnotation, db: Database) throws {
        let annotationID = annotation.id.uuidString.lowercased()
        let oldNoteIDs = try String.fetchAll(
            db,
            sql: "SELECT id FROM annotationNotes WHERE annotationID=?",
            arguments: [annotationID]
        )
        for noteID in oldNoteIDs {
            try db.execute(sql: "DELETE FROM notes WHERE id=?", arguments: [noteID])
        }

        try db.execute(sql: "DELETE FROM highlights WHERE id=?", arguments: [annotationID])
        if let highlight = annotation.highlight {
            try db.execute(sql: """
                INSERT INTO highlights
                (id,bookID,locatorJSON,href,progression,totalProgression,textBefore,textHighlight,textAfter,color,createdAt)
                VALUES(?,?,?,?,?,?,?,?,?,?,?)
                """, arguments: [
                    annotationID,
                    annotation.range.bookID.description,
                    annotation.range.startLocator.json,
                    annotation.range.startLocator.href,
                    annotation.range.startLocator.progression,
                    annotation.range.startLocator.totalProgression,
                    annotation.range.startLocator.textBefore,
                    annotation.range.startLocator.textHighlight,
                    annotation.range.startLocator.textAfter,
                    highlight.color.rawValue,
                    highlight.createdAt,
                ])
        }

        for note in annotation.notes {
            try db.execute(sql: """
                INSERT INTO notes
                (id,bookID,highlightID,locatorJSON,href,progression,totalProgression,textBefore,textHighlight,textAfter,body,createdAt,updatedAt)
                VALUES(?,?,NULL,?,?,?,?,?,?,?,?,?,?)
                """, arguments: [
                    note.id.uuidString.lowercased(),
                    annotation.range.bookID.description,
                    annotation.range.startLocator.json,
                    annotation.range.startLocator.href,
                    annotation.range.startLocator.progression,
                    annotation.range.startLocator.totalProgression,
                    annotation.range.startLocator.textBefore,
                    annotation.range.startLocator.textHighlight,
                    annotation.range.startLocator.textAfter,
                    note.body,
                    note.createdAt,
                    note.updatedAt,
                ])
        }
    }

    private func annotationID(_ row: Row) throws -> UUID {
        let raw: String = row["id"]
        guard let id = UUID(uuidString: raw) else {
            throw PersistenceError.corruptRecord(table: "textAnnotations", recordID: raw, field: "id")
        }
        return id
    }

    private func annotation(_ row: Row, notes: [NoteEntry]) throws -> TextAnnotation {
        let id = try annotationID(row)
        let bookRaw: String = row["bookID"]
        guard let bookUUID = UUID(uuidString: bookRaw) else {
            throw PersistenceError.corruptRecord(table: "textAnnotations", recordID: bookRaw, field: "bookID")
        }
        let resource: String = row["resourceHref"]
        let range = AnnotationRange(
            bookID: BookID(rawValue: bookUUID),
            resourceHref: resource,
            startLocator: try locator(row, prefix: "start", fallbackHref: resource),
            endLocator: try locator(row, prefix: "end", fallbackHref: resource)
        )
        let colorRaw: String? = row["highlightColor"]
        let highlight = colorRaw.flatMap(HighlightColor.init(rawValue:)).map {
            HighlightLayer(
                color: $0,
                createdAt: row["createdAt"],
                updatedAt: row["updatedAt"]
            )
        }
        return TextAnnotation(
            id: id,
            range: range,
            highlight: highlight,
            notes: notes,
            createdAt: row["createdAt"],
            updatedAt: row["updatedAt"]
        )
    }

    private func noteEntry(_ row: Row) throws -> NoteEntry {
        let raw: String = row["id"]
        guard let id = UUID(uuidString: raw) else {
            throw PersistenceError.corruptRecord(table: "annotationNotes", recordID: raw, field: "id")
        }
        return NoteEntry(
            id: id,
            body: row["body"],
            createdAt: row["createdAt"],
            updatedAt: row["updatedAt"]
        )
    }

    private func locator(_ row: Row, prefix: String, fallbackHref: String) throws -> BookLocator {
        let href: String? = row["\(prefix)Href"]
        let progression: Double? = row["\(prefix)Progression"]
        let totalProgression: Double? = row["\(prefix)TotalProgression"]
        let before: String? = row["\(prefix)TextBefore"]
        let highlight: String? = row["\(prefix)TextHighlight"]
        let after: String? = row["\(prefix)TextAfter"]
        return try BookLocator(
            json: row["\(prefix)LocatorJSON"],
            href: href ?? fallbackHref,
            progression: progression,
            totalProgression: totalProgression,
            textBefore: before,
            textHighlight: highlight,
            textAfter: after
        )
    }
}

private struct TextAnnotationRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "textAnnotations"

    var id, bookID, resourceHref: String
    var startLocatorJSON: Data
    var startHref: String
    var startProgression, startTotalProgression: Double?
    var startTextBefore, startTextHighlight, startTextAfter: String?
    var endLocatorJSON: Data
    var endHref: String
    var endProgression, endTotalProgression: Double?
    var endTextBefore, endTextHighlight, endTextAfter: String?
    var rangeKey: String
    var highlightColor: String?
    var createdAt, updatedAt: Date
    var legacyConflict: Bool

    init(_ annotation: TextAnnotation) {
        id = annotation.id.uuidString.lowercased()
        bookID = annotation.range.bookID.description
        resourceHref = annotation.range.resourceHref
        startLocatorJSON = annotation.range.startLocator.json
        startHref = annotation.range.startLocator.href
        startProgression = annotation.range.startLocator.progression
        startTotalProgression = annotation.range.startLocator.totalProgression
        startTextBefore = annotation.range.startLocator.textBefore
        startTextHighlight = annotation.range.startLocator.textHighlight
        startTextAfter = annotation.range.startLocator.textAfter
        endLocatorJSON = annotation.range.endLocator.json
        endHref = annotation.range.endLocator.href
        endProgression = annotation.range.endLocator.progression
        endTotalProgression = annotation.range.endLocator.totalProgression
        endTextBefore = annotation.range.endLocator.textBefore
        endTextHighlight = annotation.range.endLocator.textHighlight
        endTextAfter = annotation.range.endLocator.textAfter
        rangeKey = annotation.range.rangeKey
        highlightColor = annotation.highlight?.color.rawValue
        createdAt = annotation.createdAt
        updatedAt = annotation.updatedAt
        legacyConflict = false
    }
}

private struct NoteEntryRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "annotationNotes"

    var id, annotationID, body: String
    var createdAt, updatedAt: Date

    init(annotationID: UUID, note: NoteEntry) {
        id = note.id.uuidString.lowercased()
        self.annotationID = annotationID.uuidString.lowercased()
        body = note.body
        createdAt = note.createdAt
        updatedAt = note.updatedAt
    }
}

import Foundation
import GRDB

public final class AppDatabase: @unchecked Sendable {
    public let writer: any DatabaseWriter

    public init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    public convenience init(path: String) throws {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.prepareDatabase { db in try db.execute(sql: "PRAGMA journal_mode = WAL") }
        try self.init(writer: DatabaseQueue(path: path, configuration: configuration))
    }

    public static func inMemory() throws -> AppDatabase {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        return try AppDatabase(writer: DatabaseQueue(configuration: configuration))
    }

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_reader_foundation") { db in
            try db.create(table: "books") { t in
                t.column("id", .text).primaryKey()
                t.column("fingerprint", .text).notNull().unique()
                t.column("title", .text).notNull()
                t.column("author", .text)
                t.column("fileName", .text).notNull().unique()
                t.column("fileSize", .integer).notNull()
                t.column("importedAt", .datetime).notNull()
                t.column("lastOpenedAt", .datetime)
            }
            try db.create(table: "readingPositions") { t in
                t.column("bookID", .text).primaryKey().references("books", onDelete: .cascade)
                Self.addLocatorColumns(to: t)
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "highlights") { t in
                t.column("id", .text).primaryKey()
                t.column("bookID", .text).notNull().indexed().references("books", onDelete: .cascade)
                Self.addLocatorColumns(to: t)
                t.column("color", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "notes") { t in
                t.column("id", .text).primaryKey()
                t.column("bookID", .text).notNull().indexed().references("books", onDelete: .cascade)
                t.column("highlightID", .text).references("highlights", onDelete: .setNull)
                Self.addLocatorColumns(to: t)
                t.column("body", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v2_reader_preferences") { db in
            try db.create(table: "readerPreferences") { t in
                t.column("bookID", .text).primaryKey().references("books", onDelete: .cascade)
                t.column("theme", .text).notNull()
                t.column("fontSize", .double).notNull()
                t.column("lineHeight", .double).notNull()
                t.column("pageMargins", .double).notNull()
                t.column("readingMode", .text).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v3_reflection_loop") { db in
            try db.create(table: "readingSessions") { t in
                t.column("id", .text).primaryKey()
                t.column("bookID", .text).notNull().indexed().references("books", onDelete: .cascade)
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime)
                Self.addLocatorColumns(to: t, prefix: "start")
                Self.addOptionalLocatorColumns(to: t, prefix: "end")
                t.column("highlightCount", .integer).notNull().defaults(to: 0)
                t.column("noteCount", .integer).notNull().defaults(to: 0)
                t.column("agentDiscussionCount", .integer).notNull().defaults(to: 0)
                t.check(sql: "highlightCount >= 0 AND noteCount >= 0 AND agentDiscussionCount >= 0")
                t.check(sql: "endedAt IS NULL OR endedAt >= startedAt")
            }
            try db.create(table: "reflections") { t in
                t.column("id", .text).primaryKey()
                t.column("bookID", .text).notNull().indexed().references("books", onDelete: .cascade)
                t.column("sessionID", .text).indexed().references("readingSessions", onDelete: .setNull)
                t.column("originalText", .text).notNull()
                t.column("inputKind", .text).notNull()
                t.column("audioFileName", .text)
                t.column("createdAt", .datetime).notNull().indexed()
                t.check(sql: "length(trim(originalText)) > 0")
                t.check(sql: "inputKind IN ('text', 'voiceTranscript')")
            }
            try db.create(table: "reflectionMessages") { t in
                t.column("id", .text).primaryKey()
                t.column("reflectionID", .text).notNull().indexed().references("reflections", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.check(sql: "role IN ('agent', 'userFollowUp')")
            }
            try db.create(table: "reflectionHighlights") { t in
                t.column("reflectionID", .text).notNull().references("reflections", onDelete: .cascade)
                t.column("highlightID", .text).notNull().references("highlights", onDelete: .cascade)
                t.primaryKey(["reflectionID", "highlightID"])
            }
        }
        return migrator
    }

    private static func addLocatorColumns(to t: TableDefinition) {
        t.column("locatorJSON", .blob).notNull()
        t.column("href", .text).notNull()
        t.column("progression", .double)
        t.column("totalProgression", .double)
        t.column("textBefore", .text)
        t.column("textHighlight", .text)
        t.column("textAfter", .text)
    }

    private static func addLocatorColumns(to t: TableDefinition, prefix: String) {
        t.column("\(prefix)LocatorJSON", .blob).notNull()
        t.column("\(prefix)Href", .text).notNull()
        t.column("\(prefix)Progression", .double)
        t.column("\(prefix)TotalProgression", .double)
        t.column("\(prefix)TextBefore", .text)
        t.column("\(prefix)TextHighlight", .text)
        t.column("\(prefix)TextAfter", .text)
    }

    private static func addOptionalLocatorColumns(to t: TableDefinition, prefix: String) {
        t.column("\(prefix)LocatorJSON", .blob)
        t.column("\(prefix)Href", .text)
        t.column("\(prefix)Progression", .double)
        t.column("\(prefix)TotalProgression", .double)
        t.column("\(prefix)TextBefore", .text)
        t.column("\(prefix)TextHighlight", .text)
        t.column("\(prefix)TextAfter", .text)
    }
}

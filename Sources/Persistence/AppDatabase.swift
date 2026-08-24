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
}

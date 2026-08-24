import Foundation
import GRDB
import LibraryCore
import ReaderCore

public final class GRDBBookRepository: BookRepository, @unchecked Sendable {
    private let db: AppDatabase
    public init(database: AppDatabase) { db = database }

    public func allBooks() async throws -> [Book] { try await db.writer.read { db in try BookRecord.order(Column("lastOpenedAt").desc, Column("importedAt").desc).fetchAll(db).map(\.domain) } }
    public func book(id: BookID) async throws -> Book? { try await db.writer.read { db in try BookRecord.fetchOne(db, key: id.description)?.domain } }
    public func book(fingerprint: ContentFingerprint) async throws -> Book? { try await db.writer.read { db in try BookRecord.filter(Column("fingerprint") == fingerprint.rawValue).fetchOne(db)?.domain } }
    public func insert(_ book: Book) async throws { try await db.writer.write { db in try BookRecord(book).insert(db) } }
    public func markOpened(_ id: BookID, at date: Date) async throws { try await db.writer.write { db in try db.execute(sql: "UPDATE books SET lastOpenedAt = ? WHERE id = ?", arguments: [date, id.description]) } }
    public func delete(_ id: BookID) async throws { _ = try await db.writer.write { db in try BookRecord.deleteOne(db, key: id.description) } }
}

public final class GRDBReadingRepository: ReadingRepository, @unchecked Sendable {
    private let db: AppDatabase
    public init(database: AppDatabase) { db = database }
    public func position(for bookID: BookID) async throws -> ReadingPosition? { try await db.writer.read { db in try PositionRecord.fetchOne(db, key: bookID.description)?.domain } }
    public func positions(for bookIDs: [BookID]) async throws -> [BookID: ReadingPosition] {
        guard !bookIDs.isEmpty else { return [:] }
        let ids = Set(bookIDs)
        return try await db.writer.read { db in
            var positions: [BookID: ReadingPosition] = [:]
            for record in try PositionRecord.fetchAll(db) {
                let position = try record.domain
                if ids.contains(position.bookID) {
                    positions[position.bookID] = position
                }
            }
            return positions
        }
    }
    public func save(position: ReadingPosition) async throws { try await db.writer.write { db in try PositionRecord(position).save(db) } }
    public func highlights(for bookID: BookID) async throws -> [Highlight] { try await db.writer.read { db in try HighlightRecord.filter(Column("bookID") == bookID.description).order(Column("createdAt")).fetchAll(db).map { try $0.domain() } } }
    public func save(highlight: Highlight) async throws { try await db.writer.write { db in try HighlightRecord(highlight).save(db) } }
    public func save(highlight: Highlight, note: Note) async throws {
        guard note.highlightID == highlight.id, note.bookID == highlight.bookID else { throw PersistenceError.inconsistentHighlightNote }
        try await db.writer.write { db in
            try HighlightRecord(highlight).insert(db)
            try NoteRecord(note).insert(db)
        }
    }
    public func deleteHighlight(id: UUID) async throws { _ = try await db.writer.write { db in try HighlightRecord.deleteOne(db, key: id.uuidString.lowercased()) } }
    public func notes(for bookID: BookID) async throws -> [Note] { try await db.writer.read { db in try NoteRecord.filter(Column("bookID") == bookID.description).order(Column("createdAt")).fetchAll(db).map { try $0.domain() } } }
    public func save(note: Note) async throws { try await db.writer.write { db in try NoteRecord(note).save(db) } }
    public func deleteNote(id: UUID) async throws { _ = try await db.writer.write { db in try NoteRecord.deleteOne(db, key: id.uuidString.lowercased()) } }
    public func preferences(for bookID: BookID) async throws -> ReaderPreferences {
        try await db.writer.read { db in try PreferencesRecord.fetchOne(db, key: bookID.description)?.domain ?? .default }
    }
    public func save(preferences: ReaderPreferences, for bookID: BookID) async throws {
        try await db.writer.write { db in try PreferencesRecord(bookID: bookID, preferences: preferences).save(db) }
    }
}

public enum PersistenceError: Error {
    case inconsistentHighlightNote
    case inconsistentReflectionContext
    case missingReadingSession
    case corruptRecord(table: String, recordID: String, field: String)
}

private struct BookRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "books"
    var id, fingerprint, title: String; var author: String?; var fileName: String; var fileSize: Int64; var importedAt: Date; var lastOpenedAt: Date?
    init(_ b: Book) { id=b.id.description; fingerprint=b.fingerprint.rawValue; title=b.title; author=b.author; fileName=b.fileName; fileSize=b.fileSize; importedAt=b.importedAt; lastOpenedAt=b.lastOpenedAt }
    var domain: Book { Book(id: BookID(rawValue: UUID(uuidString: id)!), fingerprint: .init(rawValue: fingerprint), title: title, author: author, fileName: fileName, fileSize: fileSize, importedAt: importedAt, lastOpenedAt: lastOpenedAt) }
}

private protocol LocatorRecord { var locatorJSON: Data { get }; var href: String { get }; var progression: Double? { get }; var totalProgression: Double? { get }; var textBefore: String? { get }; var textHighlight: String? { get }; var textAfter: String? { get } }
private extension LocatorRecord { func locator() throws -> BookLocator { try BookLocator(json: locatorJSON, href: href, progression: progression, totalProgression: totalProgression, textBefore: textBefore, textHighlight: textHighlight, textAfter: textAfter) } }

private struct PositionRecord: Codable, FetchableRecord, PersistableRecord, LocatorRecord {
    static let databaseTableName = "readingPositions"
    var bookID: String; var locatorJSON: Data; var href: String; var progression, totalProgression: Double?; var textBefore, textHighlight, textAfter: String?; var updatedAt: Date
    init(_ p: ReadingPosition) { bookID=p.bookID.description; locatorJSON=p.locator.json; href=p.locator.href; progression=p.locator.progression; totalProgression=p.locator.totalProgression; textBefore=p.locator.textBefore; textHighlight=p.locator.textHighlight; textAfter=p.locator.textAfter; updatedAt=p.updatedAt }
    var domain: ReadingPosition { get throws { ReadingPosition(bookID: BookID(rawValue: UUID(uuidString: bookID)!), locator: try locator(), updatedAt: updatedAt) } }
}
private struct HighlightRecord: Codable, FetchableRecord, PersistableRecord, LocatorRecord {
    static let databaseTableName = "highlights"
    var id, bookID: String; var locatorJSON: Data; var href: String; var progression, totalProgression: Double?; var textBefore, textHighlight, textAfter: String?; var color: String; var createdAt: Date
    init(_ h: Highlight) { id=h.id.uuidString.lowercased(); bookID=h.bookID.description; locatorJSON=h.locator.json; href=h.locator.href; progression=h.locator.progression; totalProgression=h.locator.totalProgression; textBefore=h.locator.textBefore; textHighlight=h.locator.textHighlight; textAfter=h.locator.textAfter; color=h.color.rawValue; createdAt=h.createdAt }
    func domain() throws -> Highlight { Highlight(id: UUID(uuidString:id)!, bookID: BookID(rawValue:UUID(uuidString:bookID)!), locator:try locator(), color:HighlightColor(rawValue:color)!, createdAt:createdAt) }
}
private struct NoteRecord: Codable, FetchableRecord, PersistableRecord, LocatorRecord {
    static let databaseTableName = "notes"
    var id, bookID: String; var highlightID: String?; var locatorJSON: Data; var href: String; var progression, totalProgression: Double?; var textBefore, textHighlight, textAfter: String?; var body: String; var createdAt, updatedAt: Date
    init(_ n: Note) { id=n.id.uuidString.lowercased(); bookID=n.bookID.description; highlightID=n.highlightID?.uuidString.lowercased(); locatorJSON=n.locator.json; href=n.locator.href; progression=n.locator.progression; totalProgression=n.locator.totalProgression; textBefore=n.locator.textBefore; textHighlight=n.locator.textHighlight; textAfter=n.locator.textAfter; body=n.body; createdAt=n.createdAt; updatedAt=n.updatedAt }
    func domain() throws -> Note { Note(id:UUID(uuidString:id)!, bookID:BookID(rawValue:UUID(uuidString:bookID)!), highlightID:highlightID.flatMap(UUID.init(uuidString:)), locator:try locator(), body:body, createdAt:createdAt, updatedAt:updatedAt) }
}

private struct PreferencesRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "readerPreferences"
    var bookID, theme: String
    var fontSize, lineHeight, pageMargins: Double
    var readingMode: String
    var updatedAt: Date
    init(bookID: BookID, preferences: ReaderPreferences) {
        self.bookID = bookID.description; theme = preferences.theme.rawValue
        fontSize = preferences.fontSize; lineHeight = preferences.lineHeight; pageMargins = preferences.pageMargins
        readingMode = preferences.readingMode.rawValue; updatedAt = Date()
    }
    var domain: ReaderPreferences {
        ReaderPreferences(
            theme: ReaderTheme(rawValue: theme) ?? .system,
            fontSize: fontSize,
            lineHeight: lineHeight,
            pageMargins: pageMargins,
            readingMode: ReadingMode(rawValue: readingMode) ?? .paginated
        )
    }
}

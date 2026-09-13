import Foundation
import GRDB
import LibraryCore
import Persistence
import ReaderCore
import Testing

@Test func textAnnotationRepositoryRoundTripsIndependentLayersAndNoteEntries() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let book = TestFixtures.book(fingerprint: "annotation-roundtrip")
    try await books.insert(book)

    let locator = try annotationLocator(progression: 0.25, text: "自由与责任")
    let range = AnnotationRange(
        bookID: book.id,
        resourceHref: locator.href,
        startLocator: locator,
        endLocator: locator
    )
    let annotation = TextAnnotation(
        range: range,
        highlight: HighlightLayer(color: .yellow),
        notes: [
            NoteEntry(body: "第一条笔记"),
            NoteEntry(body: "第二条笔记"),
        ]
    )
    let repository = GRDBTextAnnotationRepository(database: database)
    try await repository.save(annotation: annotation)

    let loaded = try #require(try await repository.annotations(for: book.id).first)
    #expect(loaded.id == annotation.id)
    #expect(loaded.highlight?.color == .yellow)
    #expect(loaded.notes.map(\.body) == ["第一条笔记", "第二条笔记"])
    let legacyReading = GRDBReadingRepository(database: database)
    #expect(try await legacyReading.highlights(for: book.id).map(\.id) == [annotation.id])
    #expect(try await legacyReading.notes(for: book.id).map(\.id) == annotation.notes.map(\.id))

    var onlyNotes = loaded
    onlyNotes.highlight = nil
    try await repository.save(annotation: onlyNotes)
    let withoutHighlight = try #require(try await repository.annotations(for: book.id).first)
    #expect(withoutHighlight.highlight == nil)
    #expect(withoutHighlight.notes.count == 2)
    #expect(try await legacyReading.highlights(for: book.id).isEmpty)
    #expect(try await legacyReading.notes(for: book.id).count == 2)

    onlyNotes.notes.removeAll()
    try await repository.save(annotation: onlyNotes)
    #expect(try await repository.annotations(for: book.id).isEmpty)
}

@Test func migrationMergesLegacyHighlightAndAttachedNoteIntoOneAnnotation() async throws {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try AppDatabase.migrator.migrate(queue, upTo: "v27_reflection_message_audio")

    let book = TestFixtures.book(fingerprint: "annotation-migration")
    let locator = try annotationLocator(progression: 0.4, text: "制度与选择")
    let highlightID = UUID()
    try await queue.write { db in
        try db.execute(
            sql: "INSERT INTO books (id, fingerprint, title, fileName, fileSize, importedAt) VALUES (?, ?, ?, ?, ?, ?)",
            arguments: [book.id.description, book.fingerprint.rawValue, book.title, book.fileName, book.fileSize, book.importedAt]
        )
        try db.execute(
            sql: """
                INSERT INTO highlights
                (id,bookID,locatorJSON,href,progression,totalProgression,textBefore,textHighlight,textAfter,color,createdAt)
                VALUES(?,?,?,?,?,?,?,?,?,?,?)
                """,
            arguments: [
                highlightID.uuidString.lowercased(), book.id.description, locator.json, locator.href,
                locator.progression, locator.totalProgression, locator.textBefore, locator.textHighlight,
                locator.textAfter, HighlightColor.blue.rawValue, Date(timeIntervalSince1970: 100),
            ]
        )
        try db.execute(
            sql: """
                INSERT INTO notes
                (id,bookID,highlightID,locatorJSON,href,progression,totalProgression,textBefore,textHighlight,textAfter,body,createdAt,updatedAt)
                VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
            arguments: [
                UUID().uuidString.lowercased(), book.id.description, highlightID.uuidString.lowercased(),
                locator.json, locator.href, locator.progression, locator.totalProgression,
                locator.textBefore, locator.textHighlight, locator.textAfter, "旧笔记",
                Date(timeIntervalSince1970: 110), Date(timeIntervalSince1970: 110),
            ]
        )
    }

    try AppDatabase.migrator.migrate(queue)
    let database = try AppDatabase(writer: queue)
    let annotations = try await GRDBTextAnnotationRepository(database: database).annotations(for: book.id)

    #expect(annotations.count == 1)
    #expect(annotations.first?.id == highlightID)
    #expect(annotations.first?.highlight?.color == .blue)
    #expect(annotations.first?.notes.map(\.body) == ["旧笔记"])
}

@Test func migrationKeepsNewerHighlightWhenLegacyHighlightsCross() throws {
    let queue = try DatabaseQueue()
    try AppDatabase.migrator.migrate(queue, upTo: "v27_reflection_message_audio")
    let book = TestFixtures.book(fingerprint: "annotation-crossing")
    let olderID = UUID()
    let newerID = UUID()
    let older = try annotationLocator(progression: 0.20, text: "结构")
    let newer = try annotationLocator(progression: 0.21, text: "结构")

    try queue.write { db in
        try db.execute(
            sql: "INSERT INTO books (id, fingerprint, title, fileName, fileSize, importedAt) VALUES (?, ?, ?, ?, ?, ?)",
            arguments: [book.id.description, book.fingerprint.rawValue, book.title, book.fileName, book.fileSize, book.importedAt]
        )
        for (id, locator, date) in [
            (olderID, older, Date(timeIntervalSince1970: 100)),
            (newerID, newer, Date(timeIntervalSince1970: 200)),
        ] {
            try db.execute(
                sql: """
                    INSERT INTO highlights
                    (id,bookID,locatorJSON,href,progression,totalProgression,textBefore,textHighlight,textAfter,color,createdAt)
                    VALUES(?,?,?,?,?,?,?,?,?,?,?)
                    """,
                arguments: [
                    id.uuidString.lowercased(), book.id.description, locator.json, locator.href,
                    locator.progression, locator.totalProgression, locator.textBefore, locator.textHighlight,
                    locator.textAfter, HighlightColor.yellow.rawValue, date,
                ]
            )
        }
    }

    try AppDatabase.migrator.migrate(queue)
    let rows = try queue.read { db in
        try String.fetchAll(db, sql: "SELECT id FROM textAnnotations WHERE bookID=?", arguments: [book.id.description])
    }
    #expect(rows == [newerID.uuidString.lowercased()])
    let legacyRows = try queue.read { db in
        try String.fetchAll(db, sql: "SELECT id FROM highlights WHERE bookID=?", arguments: [book.id.description])
    }
    #expect(legacyRows == [newerID.uuidString.lowercased()])
}

private func annotationLocator(progression: Double, text: String) throws -> BookLocator {
    let json = try JSONSerialization.data(withJSONObject: [
        "href": "chapter.xhtml",
        "locations": ["progression": progression],
    ])
    return try BookLocator(
        json: json,
        href: "chapter.xhtml",
        progression: progression,
        textHighlight: text
    )
}

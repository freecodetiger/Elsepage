import AchievementCore
import Foundation
import GRDB
import LibraryCore
import Persistence
import ReflectionCore
import Testing

@Test func firstReflectionUnlocksOnce() async throws {
    let db = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: db)
    let reflections = GRDBReflectionRepository(database: db)
    let achievements = GRDBAchievementRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "first"), title: "第一", fileName: "a.epub", fileSize: 1)
    try await books.insert(book)

    let now = Date()
    let first = try reflection(book: book.id, createdAt: now)
    try await reflections.insert(first, linkedHighlightIDs: [], evidence: [])
    let service = AchievementService(repository: achievements, reflections: reflections)

    let unlocked = try await service.evaluate(event(reflection: first, now: now))
    #expect(unlocked.contains { $0.id == .firstReflection })
    let record = try #require(unlocked.first { $0.id == .firstReflection })
    #expect(record.source?.reflectionID == first.id)

    // A second reflection does not re-unlock the first.
    let second = try reflection(book: book.id, createdAt: now.addingTimeInterval(60))
    try await reflections.insert(second, linkedHighlightIDs: [], evidence: [])
    let again = try await service.evaluate(event(reflection: second, now: now.addingTimeInterval(60)))
    #expect(!again.contains { $0.id == .firstReflection })
    #expect(try await service.unlocked().count == 1)
}

@Test func sevenDaysThinkingUnlocksOnlyAtStreakSeven() async throws {
    let db = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: db)
    let reflections = GRDBReflectionRepository(database: db)
    let achievements = GRDBAchievementRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "seven"), title: "七天", fileName: "b.epub", fileSize: 1)
    try await books.insert(book)
    let service = AchievementService(repository: achievements, reflections: reflections)
    let calendar = Calendar.current
    let now = Date()

    // Six consecutive days ending today → streak 6, still locked.
    for offset in 0..<6 {
        let day = calendar.date(byAdding: .day, value: -offset, to: now)!
        let r = try reflection(book: book.id, createdAt: calendar.startOfDay(for: day).addingTimeInterval(3600))
        try await reflections.insert(r, linkedHighlightIDs: [], evidence: [])
    }
    let todayReflection = try #require(try await reflections.allReflections().first)
    let firstPass = try await service.evaluate(event(reflection: todayReflection, now: now))
    #expect(!firstPass.contains { $0.id == .sevenDaysThinking })

    // Seventh consecutive day → streak 7, unlocked.
    let seventhDay = calendar.date(byAdding: .day, value: -6, to: now)!
    let seventh = try reflection(book: book.id, createdAt: calendar.startOfDay(for: seventhDay).addingTimeInterval(3600))
    try await reflections.insert(seventh, linkedHighlightIDs: [], evidence: [])
    let last = try #require(try await reflections.allReflections().first)
    let secondPass = try await service.evaluate(event(reflection: last, now: now))
    #expect(secondPass.contains { $0.id == .sevenDaysThinking })
}

@Test func connectorUnlocksOnlyOnCrossBookConnection() async throws {
    let db = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: db)
    let reflections = GRDBReflectionRepository(database: db)
    let achievements = GRDBAchievementRepository(database: db)
    let bookA = Book(fingerprint: .init(rawValue: "cross-a"), title: "甲书", fileName: "a.epub", fileSize: 1)
    let bookB = Book(fingerprint: .init(rawValue: "cross-b"), title: "乙书", fileName: "b.epub", fileSize: 1)
    try await books.insert(bookA)
    try await books.insert(bookB)
    let service = AchievementService(repository: achievements, reflections: reflections)
    let now = Date()
    let current = try reflection(book: bookA.id, createdAt: now)
    try await reflections.insert(current, linkedHighlightIDs: [], evidence: [])

    // Same-book connection must not unlock Connector.
    let sameBookPast = try reflection(book: bookA.id, createdAt: now.addingTimeInterval(-3600))
    let sameBookPass = try await service.evaluate(event(
        reflection: current, now: now, connected: (sameBookPast, bookA.id)
    ))
    #expect(!sameBookPass.contains { $0.id == .connector })

    // Cross-book connection unlocks it.
    let otherBookPast = try reflection(book: bookB.id, createdAt: now.addingTimeInterval(-7200))
    let crossBookPass = try await service.evaluate(event(
        reflection: current, now: now, connected: (otherBookPast, bookB.id)
    ))
    #expect(crossBookPass.contains { $0.id == .connector })
}

@Test func returnToAnIdeaUnlocksOnlyAfterThirtyDays() async throws {
    let db = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: db)
    let reflections = GRDBReflectionRepository(database: db)
    let achievements = GRDBAchievementRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "return"), title: "回来", fileName: "c.epub", fileSize: 1)
    try await books.insert(book)
    let service = AchievementService(repository: achievements, reflections: reflections)
    let now = Date()
    let current = try reflection(book: book.id, createdAt: now)
    try await reflections.insert(current, linkedHighlightIDs: [], evidence: [])

    // 28 days old → not yet.
    let twentyEight = try reflection(book: book.id, createdAt: now.addingTimeInterval(-28 * 24 * 3600))
    let youngPass = try await service.evaluate(event(reflection: current, now: now, connected: (twentyEight, book.id)))
    #expect(!youngPass.contains { $0.id == .returnToAnIdea })

    // 35 days old → unlocked.
    let thirtyFive = try reflection(book: book.id, createdAt: now.addingTimeInterval(-35 * 24 * 3600))
    let oldPass = try await service.evaluate(event(reflection: current, now: now, connected: (thirtyFive, book.id)))
    #expect(oldPass.contains { $0.id == .returnToAnIdea })
}

@Test func achievementRepositoryRoundTripsUnlockOnes() async throws {
    let db = try AppDatabase.inMemory()
    let repository = GRDBAchievementRepository(database: db)
    let books = GRDBBookRepository(database: db)
    let reflections = GRDBReflectionRepository(database: db)
    let book = Book(fingerprint: .init(rawValue: "roundtrip"), title: "往返", fileName: "d.epub", fileSize: 1)
    try await books.insert(book)
    let now = Date()
    let reflection = try reflection(book: book.id, createdAt: now)
    try await reflections.insert(reflection, linkedHighlightIDs: [], evidence: [])
    let service = AchievementService(repository: repository, reflections: reflections)

    let first = try await service.evaluate(event(reflection: reflection, now: now))
    #expect(first.count == 1)
    // Idempotent: evaluating again returns nothing new and the table still has one row.
    let second = try await service.evaluate(event(reflection: reflection, now: now))
    #expect(second.isEmpty)
    let stored = try await repository.unlocked()
    #expect(stored.count == 1)
    #expect(stored.first?.id == first.first?.id)
    #expect(stored.first?.source?.reflectionID == reflection.id)
}

// MARK: - Fixtures

private func reflection(book: BookID, createdAt: Date) throws -> Reflection {
    Reflection(bookID: book, originalText: "测试反思", inputKind: .text, createdAt: createdAt)
}

private func event(
    reflection: Reflection,
    now: Date,
    connected: (reflection: Reflection, bookID: BookID)? = nil
) -> AchievementEvent {
    AchievementEvent(
        reflection: reflection,
        connectedSource: connected.map { ConnectedSource(reflection: $0.reflection, bookID: $0.bookID) },
        now: now
    )
}

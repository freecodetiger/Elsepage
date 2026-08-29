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

@Test func questionerUnlocksOnceOnExplicitUserChallenge() async throws {
    let db = try AppDatabase.inMemory()
    let reflections = GRDBReflectionRepository(database: db)
    let service = AchievementService(
        repository: GRDBAchievementRepository(database: db), reflections: reflections
    )
    let book = TestFixtures.book(fingerprint: "questioner")
    try await GRDBBookRepository(database: db).insert(book)
    let now = Date()

    // Neutral reflection does not unlock Questioner…
    let neutral = try reflection(book: book.id, createdAt: now, originalText: "这一章让我想到很多")
    try await reflections.insert(neutral, linkedHighlightIDs: [], evidence: [])
    let neutralPass = try await evaluate(service, reflection: neutral, now: now)
    #expect(!neutralPass.contains { $0.id == .questioner })

    // …and neither does a challenge that only appears in Agent output.
    try await reflections.appendMessage(.init(
        reflectionID: neutral.id, author: .agent, source: .agentGenerated,
        content: "这里值得质疑：作者的论证是否成立？", createdAt: now
    ))
    let agentTextPass = try await evaluate(service, reflection: neutral, now: now)
    #expect(!agentTextPass.contains { $0.id == .questioner })

    // An explicit challenge in the user's own words unlocks, exactly once.
    let challenge = try reflection(book: book.id, createdAt: now, originalText: "我不认同作者这个判断。")
    try await reflections.insert(challenge, linkedHighlightIDs: [], evidence: [])
    let unlocked = try await service.evaluate(event(reflection: challenge, now: now))
    let record = try #require(unlocked.first { $0.id == .questioner })
    #expect(record.source?.reflectionID == challenge.id)
    #expect(try await service.evaluate(event(reflection: challenge, now: now)).isEmpty)
}

@Test func questionerAlsoUnlocksFromUserFollowUpMessages() async throws {
    let db = try AppDatabase.inMemory()
    let reflections = GRDBReflectionRepository(database: db)
    let service = AchievementService(
        repository: GRDBAchievementRepository(database: db), reflections: reflections
    )
    let book = TestFixtures.book(fingerprint: "questioner-followup")
    try await GRDBBookRepository(database: db).insert(book)
    let now = Date()
    let neutral = try reflection(book: book.id, createdAt: now, originalText: "先记下这段")
    try await reflections.insert(neutral, linkedHighlightIDs: [], evidence: [])

    // A neutral root plus a challenging follow-up (继续说) still counts.
    try await reflections.appendMessage(.init(
        reflectionID: neutral.id, author: .user, source: .userInput,
        content: "回头再看，还是不敢苟同作者的说法。", createdAt: now.addingTimeInterval(60)
    ))
    let unlocked = try await service.evaluate(event(reflection: neutral, now: now))
    #expect(unlocked.contains { $0.id == .questioner })
}

@Test func questionerHeuristicRejectsInnocuousText() {
    // Prefer false negatives: none of these carry an explicit challenge marker.
    for text in [
        "这一段写得很好，我认同作者的角度。",
        "今天读完了第三章，明天继续。",
        "作者举的例子让我想起自己的经历。",
        "同意这个观点的前提是大家都读过前文。",
    ] {
        #expect(!QuestionerHeuristic.expressesExplicitChallenge(text), "误报：\(text)")
    }
    for text in ["我不同意作者的说法", "对此表示质疑", "作者错了", "作者忽略了最关键的前提"] {
        #expect(QuestionerHeuristic.expressesExplicitChallenge(text), "漏报：\(text)")
    }
}

@Test func changedMyMindUnlocksOnlyOnUserMemoryRevision() async throws {
    let db = try AppDatabase.inMemory()
    let reflections = GRDBReflectionRepository(database: db)
    let service = AchievementService(
        repository: GRDBAchievementRepository(database: db), reflections: reflections
    )
    let book = TestFixtures.book(fingerprint: "changed-my-mind")
    try await GRDBBookRepository(database: db).insert(book)
    let now = Date()
    let current = try reflection(book: book.id, createdAt: now)
    try await reflections.insert(current, linkedHighlightIDs: [], evidence: [])

    // Reflection moments never unlock it — not even with a connection.
    let past = try reflection(book: book.id, createdAt: now.addingTimeInterval(-40 * 24 * 3600))
    let reflectionPass = try await evaluate(service, reflection: current, now: now, connected: (past, book.id))
    #expect(!reflectionPass.contains { $0.id == .changedMyMind })

    // The user's own revise/supersede action in My Mind unlocks it, exactly once.
    let unlocked = try await service.evaluate(.userMemoryRevision(now: now))
    let record = try #require(unlocked.first { $0.id == .changedMyMind })
    #expect(record.source == nil)
    #expect(try await service.evaluate(.userMemoryRevision(now: now)).isEmpty)
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

private func evaluate(
    _ service: AchievementService,
    reflection: Reflection,
    now: Date,
    connected: (reflection: Reflection, bookID: BookID)? = nil
) async throws -> [AchievementRecord] {
    try await service.evaluate(event(reflection: reflection, now: now, connected: connected))
}

private func reflection(book: BookID, createdAt: Date, originalText: String = "测试反思") throws -> Reflection {
    Reflection(bookID: book, originalText: originalText, inputKind: .text, createdAt: createdAt)
}

private func event(
    reflection: Reflection,
    now: Date,
    connected: (reflection: Reflection, bookID: BookID)? = nil
) -> AchievementEvent {
    .reflection(
        reflection,
        connectedSource: connected.map { ConnectedSource(reflection: $0.reflection, bookID: $0.bookID) },
        now: now
    )
}

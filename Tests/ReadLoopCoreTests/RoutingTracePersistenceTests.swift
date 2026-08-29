import ContextRouting
import Foundation
import GRDB
import LibraryCore
import Persistence
import ReflectionCore
import Testing

@Test func routerTraceMigrationCreatesRoutingTracesTable() async throws {
    let database = try AppDatabase.inMemory()
    let tables = try await database.writer.read { db in
        try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
    }
    #expect(tables.contains("routingTraces"))
}

@Test func routingTraceSavesRoundTripsAndLatestTraceWins() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let book = TestFixtures.book(); try await books.insert(book)
    let reflection = Reflection(bookID: book.id, originalText: "trace me", inputKind: .text)
    try await reflections.insert(reflection, linkedHighlightIDs: [], evidence: [])

    let repository = GRDBRoutingTraceRepository(database: database)
    let reflectionID = reflection.id.description
    let first = makeTrace(reflectionID: reflectionID, detail: "network", seconds: [0.2, 0.5, 1.5], createdAt: Date(timeIntervalSince1970: 1000))
    let second = makeTrace(reflectionID: reflectionID, detail: "rateLimited", seconds: [0.3, 0.6, 2.0], createdAt: Date(timeIntervalSince1970: 2000))
    try await repository.save(first)
    try await repository.save(second)

    let latest = try #require(try await repository.latestTrace(for: reflectionID))
    #expect(latest.id == second.id)
    #expect(latest.fallbackDetail == "rateLimited")
    #expect(latest.validatedPlan.intent == .passageObservation)
    #expect(latest.selectedBookEvidenceIDs == ["chunk-1"])

    #expect(try await repository.latestTrace(for: "no-such-reflection") == nil)
}

@Test func routingTraceDiagnosticsAggregateAcrossSavedTraces() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let book = TestFixtures.book(); try await books.insert(book)
    try await reflections.insert(
        Reflection(bookID: book.id, originalText: "one", inputKind: .text),
        linkedHighlightIDs: [], evidence: []
    )
    try await reflections.insert(
        Reflection(bookID: book.id, originalText: "two", inputKind: .text),
        linkedHighlightIDs: [], evidence: []
    )

    let repository = GRDBRoutingTraceRepository(database: database)
    let all = try await reflections.recentReflections(limit: 2)
    let r1 = try #require(all.first { $0.originalText == "one" })
    let r2 = try #require(all.first { $0.originalText == "two" })
    try await repository.save(makeTrace(reflectionID: r1.id.description, detail: "network", seconds: [0.2, 0.4, 1.0]))
    try await repository.save(makeTrace(reflectionID: r2.id.description, detail: "rateLimited", seconds: [0.4, 0.8, 2.0]))

    let diagnostics = try await repository.diagnostics()
    #expect(diagnostics.totalTraces == 2)
    #expect(diagnostics.fallbackCounts == ["network": 1, "rateLimited": 1])
    let routing = try #require(diagnostics.averageRoutingDuration)
    #expect(abs(durationSeconds(routing) - 0.3) < 0.001)
}

@Test func recentTracesReturnsNewestFirstAndRespectsLimit() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let book = TestFixtures.book(); try await books.insert(book)
    let reflection = Reflection(bookID: book.id, originalText: "recent ones", inputKind: .text)
    try await reflections.insert(reflection, linkedHighlightIDs: [], evidence: [])

    let repository = GRDBRoutingTraceRepository(database: database)
    let reflectionID = reflection.id.description
    try await repository.save(makeTrace(reflectionID: reflectionID, detail: "network", seconds: [0.1, 0.1, 0.1], createdAt: Date(timeIntervalSince1970: 1000)))
    try await repository.save(makeTrace(reflectionID: reflectionID, detail: nil, seconds: [0.1, 0.1, 0.1], createdAt: Date(timeIntervalSince1970: 2000)))
    try await repository.save(makeTrace(reflectionID: reflectionID, detail: "rateLimited", seconds: [0.1, 0.1, 0.1], createdAt: Date(timeIntervalSince1970: 3000)))

    let recent = try await repository.recentTraces(limit: 2)
    #expect(recent.count == 2)
    #expect(recent.first?.fallbackDetail == "rateLimited")
    #expect(recent.last?.fallbackDetail == nil)

    let limited = try await repository.recentTraces(limit: 0)
    #expect(limited.isEmpty)
}

@Test func routingTracePersistsWithoutRawUserText() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let book = TestFixtures.book(); try await books.insert(book)
    let reflection = Reflection(bookID: book.id, originalText: "secret-user-thought", inputKind: .text)
    try await reflections.insert(reflection, linkedHighlightIDs: [], evidence: [])

    let repository = GRDBRoutingTraceRepository(database: database)
    try await repository.save(makeTrace(reflectionID: reflection.id.description, detail: nil, seconds: [0.1, 0.2, 0.3]))

    let json = try await database.writer.read { db in
        try Data.fetchOne(db, sql: "SELECT traceJSON FROM routingTraces LIMIT 1") ?? Data()
    }
    let encoded = String(decoding: json, as: UTF8.self)
    #expect(!encoded.contains("secret-user-thought"))
}

@Test func deletingReflectionCascadesItsRoutingTraces() async throws {
    let database = try AppDatabase.inMemory()
    let books = GRDBBookRepository(database: database)
    let reflections = GRDBReflectionRepository(database: database)
    let book = TestFixtures.book(); try await books.insert(book)
    let reflection = Reflection(bookID: book.id, originalText: "cascade me", inputKind: .text)
    try await reflections.insert(reflection, linkedHighlightIDs: [], evidence: [])

    let repository = GRDBRoutingTraceRepository(database: database)
    try await repository.save(makeTrace(reflectionID: reflection.id.description, detail: nil, seconds: [0.1, 0.2, 0.3]))

    try await reflections.delete(id: reflection.id)
    #expect(try await repository.latestTrace(for: reflection.id.description) == nil)
}

private func makeTrace(reflectionID: String, detail: String?, seconds: [Double], createdAt: Date = Date()) -> ContextPlanTrace {
    let semantic = SemanticContextPlan(
        intent: .passageObservation, requests: [.nearby],
        response: SemanticResponsePlan(length: .short, posture: .respondOnly)
    )
    let input = ContextRoutingInput(
        interactionMode: .reflection,
        currentReflection: "secret-user-thought",
        recentConversation: [],
        currentReading: .init(bookID: BookID(), chapterTitle: nil, selectedText: nil, nearbyTextPreview: nil, hasCurrentLocator: false),
        availableSources: .init(hasNearbyPassage: false, hasBookIndex: false, hasPastThoughts: false),
        previousAgentAskedQuestion: false
    )
    let (validated, _) = SemanticPlanValidator().validate(semantic, input: input)
    let execution = ContextPolicyCompiler().compile(validated, input: input)
    return ContextPlanTrace(
        reflectionID: reflectionID,
        createdAt: createdAt,
        proposedPlan: execution.legacyProposal,
        validatedPlan: execution.legacyValidatedPlan,
        usedFallback: detail != nil,
        fallbackReason: detail != nil ? .modelFailure : nil,
        fallbackDetail: detail,
        routingDuration: .seconds(seconds[0]),
        retrievalDuration: .seconds(seconds[1]),
        replyDuration: .seconds(seconds[2]),
        selectedBookEvidenceIDs: ["chunk-1"],
        connectedReflectionID: nil,
        routingTokenUsage: nil,
        replyTokenUsage: nil
    )
}

private func durationSeconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
}

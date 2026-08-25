import Foundation
import LibraryCore
import ReaderCore
import Testing

private actor WriteRecorder<Value: Sendable> {
    private(set) var values: [Value] = []
    func append(_ value: Value) { values.append(value) }
}

private actor PositionHarness {
    private var state = LatestValueState<Int>()
    func submit(_ value: Int) { state.submit(value) }
    func pending() -> Int? { state.pending?.value }
    func flush(using write: @Sendable (Int) async throws -> Void) async throws {
        while let target = state.beginWrite() {
            do {
                try await write(target.value)
                state.didWrite(target, succeeded: true)
            } catch {
                state.didWrite(target, succeeded: false)
                throw error
            }
        }
    }
}

@Test func failedOldFlushNeverReplacesNewPendingValue() async throws {
    enum Failure: Error { case expected }
    let writer = PositionHarness()
    let started = AsyncStream.makeStream(of: Void.self)
    let release = AsyncStream.makeStream(of: Void.self)
    await writer.submit(1)

    let oldFlush = Task {
        try await writer.flush { value in
            if value == 1 {
                started.continuation.yield()
                for await _ in release.stream { break }
            }
            throw Failure.expected
        }
    }
    for await _ in started.stream { break }
    await writer.submit(2)
    release.continuation.yield()
    await #expect(throws: Failure.self) { try await oldFlush.value }

    #expect(await writer.pending() == 2)
    try await writer.flush { #expect($0 == 2) }
    #expect(await writer.pending() == nil)
}

@Test func successfulOldFlushDoesNotClearNewPendingValue() async throws {
    let writer = PositionHarness()
    let started = AsyncStream.makeStream(of: Void.self)
    let release = AsyncStream.makeStream(of: Void.self)
    await writer.submit(1)
    let oldFlush = Task {
        try await writer.flush { value in
            if value == 1 {
                started.continuation.yield()
                for await _ in release.stream { break }
            }
        }
    }
    for await _ in started.stream { break }
    await writer.submit(2)
    release.continuation.yield()
    try await oldFlush.value
    #expect(await writer.pending() == nil)
}

@Test func overlappingFlushesCannotPersistOldValueAfterNewValue() async throws {
    let writer = PositionHarness()
    let started = AsyncStream.makeStream(of: Void.self)
    let release = AsyncStream.makeStream(of: Void.self)
    let recorder = WriteRecorder<Int>()
    await writer.submit(1)
    let first = Task {
        try await writer.flush { value in
            if value == 1 {
                started.continuation.yield()
                for await _ in release.stream { break }
            }
            await recorder.append(value)
        }
    }
    for await _ in started.stream { break }
    await writer.submit(2)
    try await writer.flush { await recorder.append($0) }
    release.continuation.yield()
    try await first.value
    #expect(await recorder.values == [1, 2])
    #expect(await writer.pending() == nil)
}

@Test func emptyOrNewSearchInvalidatesPreviousToken() {
    var state = LatestRequestState()
    let first = state.begin()
    #expect(state.isLoading)
    state.invalidate()
    #expect(!state.isLoading)
    let acceptedFirst = state.finish(first)
    #expect(!acceptedFirst)

    let second = state.begin()
    let third = state.begin()
    let acceptedSecond = state.finish(second)
    let acceptedThird = state.finish(third)
    #expect(!acceptedSecond)
    #expect(acceptedThird)
    #expect(!state.isLoading)
}

@Test func locatorIdentityIgnoresJSONKeyOrderButPreservesUnknownReadiumFields() throws {
    let first = try BookLocator(
        json: Data(#"{"href":"chapter.xhtml","locations":{"progression":0.2},"future":{"a":1}}"#.utf8),
        href: "chapter.xhtml",
        progression: 0.2
    )
    let reordered = try BookLocator(
        json: Data(#"{"future":{"a":1},"locations":{"progression":0.2},"href":"chapter.xhtml"}"#.utf8),
        href: "chapter.xhtml",
        progression: 0.2
    )
    let different = try BookLocator(
        json: Data(#"{"href":"chapter.xhtml","locations":{"progression":0.3},"future":{"a":1}}"#.utf8),
        href: "chapter.xhtml",
        progression: 0.3
    )

    #expect(first.identifiesSameAnchor(as: reordered))
    #expect(!first.identifiesSameAnchor(as: different))
}

@Test func locatorHistoryIsBoundedDeduplicatedAndReturnsNewestFirst() throws {
    func locator(_ progression: Double) throws -> BookLocator {
        try BookLocator(
            json: Data("{\"href\":\"chapter.xhtml\",\"locations\":{\"progression\":\(progression)}}".utf8),
            href: "chapter.xhtml",
            progression: progression
        )
    }

    var history = LocatorHistory(capacity: 2)
    let first = try locator(0.1)
    let second = try locator(0.2)
    let third = try locator(0.3)
    history.record(first)
    history.record(first)
    history.record(second)
    history.record(third)

    #expect(history.entries.count == 2)
    #expect(history.pop()?.identifiesSameAnchor(as: third) == true)
    #expect(history.pop()?.identifiesSameAnchor(as: second) == true)
    #expect(!history.canGoBack)
}

@Test func highlightAnchorIdentityPreventsDuplicateDecorationCreation() throws {
    let bookID = BookID()
    let locator = try BookLocator(
        json: Data(#"{"href":"chapter.xhtml","locations":{"progression":0.2}}"#.utf8),
        href: "chapter.xhtml",
        progression: 0.2
    )
    let reordered = try BookLocator(
        json: Data(#"{"locations":{"progression":0.2},"href":"chapter.xhtml"}"#.utf8),
        href: "chapter.xhtml",
        progression: 0.2
    )

    let highlights = [Highlight(bookID: bookID, locator: locator)]
    #expect(highlights.containsHighlight(at: reordered))
}

@Test func readerDefaultsFavorComfortableLongFormTypography() {
    let preferences = ReaderPreferences.default
    #expect(preferences.fontSize == 1.05)
    #expect(preferences.lineHeight == 1.2)
    #expect(preferences.pageMargins == 1.1)
    #expect(preferences.readingMode == .paginated)
}

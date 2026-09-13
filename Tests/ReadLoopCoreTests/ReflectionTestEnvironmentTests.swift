#if DEBUG
import Persistence
import ReflectionCore
import Testing

@Test func debugFixturePersistsRealReflectionAndEvidence() async throws {
    let fixture = try await ReflectionTestEnvironment.make()
    let service = TextReflectionSubmissionService(repository: fixture.reflections)
    let draft = TextReflectionDraft(bookID: fixture.book.id, sessionID: fixture.session.id,
                                    locator: fixture.locator, originalText: "自动化测试：阅读后的思考")
    let saved = try await service.submit(draft)
    #expect(try await fixture.reflections.reflection(id: saved.id)?.originalText == draft.originalText)
    #expect(try await fixture.reflections.evidence(for: saved.id).count == 2)
    let retry = try await service.submit(draft)
    #expect(retry.id == saved.id)
    #expect(try await fixture.reflections.allReflections().count == 1)
}

@Test func debugFixturesAreIsolatedAndRejectEmptyInput() async throws {
    let first = try await ReflectionTestEnvironment.make()
    let second = try await ReflectionTestEnvironment.make()
    let service = TextReflectionSubmissionService(repository: first.reflections)
    _ = try await service.submit(.init(bookID: first.book.id, sessionID: first.session.id,
                                      locator: first.locator, originalText: "独立测试"))
    #expect(try await second.reflections.allReflections().isEmpty)
    await #expect(throws: TextReflectionSubmissionError.emptyText) {
        try await TextReflectionSubmissionService(repository: second.reflections).submit(
            .init(bookID: second.book.id, sessionID: second.session.id,
                  locator: second.locator, originalText: "  "))
    }
    #expect(try await second.reflections.allReflections().isEmpty)
}
#endif

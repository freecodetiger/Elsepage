import AgentRuntime
import BrainCore
import ContextEngineering
import ContextRouting
import Foundation
import GRDB
import LibraryCore
import Persistence
import ReaderAgent
import ReflectionCore
import Testing

// Phase 17 (docs/brain.md §8-9): BrainProjectionService — the single production
// writer for the Brain. LLM proposes, deterministic code validates and executes.

private func makeProjectionFixture() async throws -> (BrainProjectionService, GRDBBrainRepository) {
    let database = try AppDatabase.inMemory()
    let repository = GRDBBrainRepository(database: database)
    let service = BrainProjectionService(items: repository, retriever: BrainRetriever(items: repository))
    return (service, repository)
}

private final class ProjectionScriptedClient: ModelClient, @unchecked Sendable {
    let descriptor = ModelDescriptor(provider: "fake", model: "scripted", capabilities: .init(supportsStreaming: true))
    private let responses: [String]
    private var count = 0

    init(responses: [String]) { self.responses = responses }

    func stream(request: ModelRequest) -> AsyncThrowingStream<ModelEvent, Error> {
        let index = min(count, responses.count - 1)
        count += 1
        let content = responses[index]
        return AsyncThrowingStream { continuation in
            continuation.yield(.started)
            continuation.yield(.completed(ModelResponse(content: content)))
            continuation.finish()
        }
    }
}

@Test func projectionCreatesThoughtWithOriginEvidence() async throws {
    let (service, repository) = try await makeProjectionFixture()
    let outcome = await service.observe(
        observation: "我又想到了自由与责任",
        reflectionID: ReflectionID(),
        using: ProjectionScriptedClient(responses: [
            "{\"action\":\"createThought\",\"title\":\"自由意味着责任\",\"content\":\"自由的核心不是拥有选择，而是没有人能替你承担选择的后果。\",\"stage\":\"evolving\"}"
        ])
    )
    #expect(outcome.applied, "corrections: \(outcome.corrections)")

    let items = try await repository.items()
    #expect(items.count == 1)
    guard case .thought(let thought) = try #require(items.first) else {
        Issue.record("expected thought")
        return
    }
    #expect(thought.title == "自由意味着责任")
    #expect(thought.stage == .evolving)
    let evidence = try await repository.evidence(for: thought.id)
    #expect(evidence.count == 1)
    #expect(evidence.first?.relation == .origin)
    guard case .reflection = evidence.first?.source else {
        Issue.record("expected reflection source")
        return
    }
}

@Test func projectionUpdatesThoughtAndAttachesRevises() async throws {
    let (service, repository) = try await makeProjectionFixture()
    let existing = BrainItem.thought(Thought(
        id: BrainItemID(rawValue: "t-seed"), title: "自由观", statement: "自由就是不受束缚",
        stage: .evolving, provenance: BrainProvenance(originEvidence: nil),
        createdAt: Date(), updatedAt: Date()
    ))
    try await repository.save(existing)

    // The observation must share the seed's wording so the retriever surfaces
    // the seed as a candidate — otherwise the fragmentation guard correctly
    // rejects the update (target not among candidates).
    let outcome = await service.observe(
        observation: "自由就是不受束缚吗，我觉得不止如此",
        reflectionID: ReflectionID(),
        using: ProjectionScriptedClient(responses: [
            "{\"action\":\"updateThought\",\"itemID\":\"t-seed\",\"content\":\"自由的核心是承担选择，而不是免于束缚。\"}"
        ])
    )
    #expect(outcome.applied, "corrections: \(outcome.corrections)")

    guard case .thought(let updated) = try #require(try await repository.item(id: existing.id)) else {
        Issue.record("expected thought")
        return
    }
    #expect(updated.statement == "自由的核心是承担选择，而不是免于束缚。")
    let evidence = try await repository.evidence(for: existing.id)
    #expect(evidence.contains { $0.relation == .revises })
}

@Test func projectionUpdateWithForeignTargetIsRejected() async throws {
    let (service, repository) = try await makeProjectionFixture()
    let outcome = await service.observe(
        observation: "自由就是不受束缚吗，我觉得不止如此",
        reflectionID: ReflectionID(),
        using: ProjectionScriptedClient(responses: [
            "{\"action\":\"updateThought\",\"itemID\":\"t-ghost\",\"content\":\"幽灵目标的更新。\"}"
        ])
    )
    #expect(!outcome.applied)
    #expect(outcome.corrections.contains { $0.contains("target not among") })
    #expect(try await repository.items().isEmpty)
}

@Test func projectionProposesMemoryAsNeedsReview() async throws {
    let (service, repository) = try await makeProjectionFixture()
    let outcome = await service.observe(
        observation: "用户似乎总是从责任角度理解自由",
        reflectionID: ReflectionID(),
        using: ProjectionScriptedClient(responses: [
            "{\"action\":\"proposeMemory\",\"content\":\"用户倾向从责任角度理解自由\"}"
        ])
    )
    #expect(outcome.applied, "corrections: \(outcome.corrections)")

    let items = try await repository.items(kind: .memory)
    guard case .memory(let memory) = try #require(items.first) else {
        Issue.record("expected memory")
        return
    }
    #expect(memory.state == .needsReview, "AI-inferred memories start as needsReview for the user to confirm")
    #expect(memory.origin == .agentInferred)
    #expect(memory.confidence == .medium)
    #expect(try await repository.evidence(for: memory.id).first?.relation == .origin)
}

@Test func projectionNoChangeAndDecodeFailureTouchNothing() async throws {
    let (service, repository) = try await makeProjectionFixture()
    let noChange = await service.observe(
        observation: "随便聊聊", reflectionID: ReflectionID(),
        using: ProjectionScriptedClient(responses: ["{\"action\":\"noChange\"}"])
    )
    #expect(noChange.proposal == .noChange)
    #expect(try await repository.items().isEmpty)

    // Malformed JSON: the maintenance path degrades to noChange, never throws.
    let (service2, repository2) = try await makeProjectionFixture()
    let garbage = await service2.observe(
        observation: "随便聊聊", reflectionID: ReflectionID(),
        using: ProjectionScriptedClient(responses: ["这不是 JSON"])
    )
    #expect(!garbage.applied)
    #expect(try await repository2.items().isEmpty)
}

// MARK: - Revisions (phase 18 — 变化可追溯)

@Test func projectionUpdateRecordsPreviousStatementAsRevision() async throws {
    let (service, repository) = try await makeProjectionFixture()
    let existing = BrainItem.thought(Thought(
        id: BrainItemID(rawValue: "t-rev"), title: "自由观", statement: "自由就是不受束缚",
        stage: .evolving, provenance: BrainProvenance(originEvidence: nil),
        createdAt: Date(), updatedAt: Date()
    ))
    try await repository.save(existing)
    let reflectionID = ReflectionID()

    _ = await service.observe(
        observation: "自由就是不受束缚吗，我觉得不止如此",
        reflectionID: reflectionID,
        using: ProjectionScriptedClient(responses: [
            "{\"action\":\"updateThought\",\"itemID\":\"t-rev\",\"content\":\"自由的核心是承担选择。\"}"
        ])
    )

    let revisions = try await repository.revisions(for: existing.id)
    #expect(revisions.count == 1)
    #expect(revisions.first?.revision == 1)
    #expect(revisions.first?.content == "自由就是不受束缚", "the REPLACED wording is preserved")
    #expect(revisions.first?.triggerEvidenceID == reflectionID.description)
    // A second rewrite numbers incrementally. The observation must resonate
    // with the CURRENT statement for retrieval to link them.
    _ = await service.observe(
        observation: "自由的核心是承担选择，这一点我现在更确定了",
        reflectionID: ReflectionID(),
        using: ProjectionScriptedClient(responses: [
            "{\"action\":\"updateThought\",\"itemID\":\"t-rev\",\"content\":\"自由的核心是承担选择，而不是免于束缚。\"}"
        ])
    )
    let afterSecond = try await repository.revisions(for: existing.id)
    #expect(afterSecond.count == 2)
    #expect(afterSecond.map(\.revision) == [2, 1], "newest first")
    #expect(afterSecond.first?.content == "自由的核心是承担选择。")
}

@Test func revisionsRoundTripCascadeAndWipe() async throws {
    let database = try AppDatabase.inMemory()
    let repository = GRDBBrainRepository(database: database)
    let thought = BrainItem.thought(Thought(
        id: BrainItemID(rawValue: "t-hist"), title: "历史", statement: "第一版",
        stage: .emerging, provenance: BrainProvenance(originEvidence: nil),
        createdAt: Date(), updatedAt: Date()
    ))
    try await repository.save(thought)
    try await repository.recordRevision(itemID: thought.id, content: "第一版", triggerEvidenceID: "ref-x")
    try await repository.recordRevision(itemID: thought.id, content: "第一版", triggerEvidenceID: nil)

    let revisions = try await repository.revisions(for: thought.id)
    #expect(revisions.map(\.revision) == [2, 1], "numbering assigned by the store, newest first")
    #expect(revisions.last?.triggerEvidenceID == "ref-x")

    try await repository.delete(id: thought.id)
    #expect(try await repository.revisions(for: thought.id).isEmpty, "revisions cascade with their item")

    try await database.wipeAllUserData()
    #expect(try await repository.items().isEmpty)
}

import AgentRuntime
import ContextEngineering
import ContextRouting
import Foundation
import LibraryCore
import ReaderCore
import ReadingSessionCore
import ReflectionCore
import RetrievalCore

public enum ReaderAgentEvent: Equatable, Sendable {
    case started
    case contextPrepared(ReflectionConnection?)
    case textDelta(String)
    /// The evidence actually sent for this reply, plus the citations the model used.
    /// Carried to the UI so it can render provenance without a separate query.
    case citationsValidated(AgentResponseProvenance)
    case completed(ReflectionMessage)
    case contextDisclosed(ContextDisclosure)
    case cancelled
    case failed(ReaderAgentFailure)
}

/// User-visible summary of the context the reply actually drew on. Delivered
/// after a successful reply so the conversation can surface what was used.
public struct ContextDisclosure: Equatable, Sendable {
    public let includedNearbyPassage: Bool
    public let retrievedBookEvidenceCount: Int
    public let connectedReflectionID: ReflectionID?
    public let usedFallback: Bool
    public let fallbackReason: RoutingFallbackReason?
    public let routingDuration: Duration
    public let retrievalDuration: Duration
    /// True when the provider stopped the reply at maxOutputTokens; the response
    /// may end mid-sentence and its citation block may be missing.
    public let replyTruncated: Bool

    public init(
        includedNearbyPassage: Bool,
        retrievedBookEvidenceCount: Int,
        connectedReflectionID: ReflectionID?,
        usedFallback: Bool,
        fallbackReason: RoutingFallbackReason?,
        routingDuration: Duration,
        retrievalDuration: Duration,
        replyTruncated: Bool = false
    ) {
        self.includedNearbyPassage = includedNearbyPassage
        self.retrievedBookEvidenceCount = retrievedBookEvidenceCount
        self.connectedReflectionID = connectedReflectionID
        self.usedFallback = usedFallback
        self.fallbackReason = fallbackReason
        self.routingDuration = routingDuration
        self.retrievalDuration = retrievalDuration
        self.replyTruncated = replyTruncated
    }
}

public enum ReaderAgentFailure: Error, Equatable, Sendable {
    case missingReflection
    case providerNotConfigured
    case runtime(AgentFailure)
    case emptyResponse
    case emptyUserMessage
    case persistence
}

/// Product module for optional feedback on a Reflection already stored locally.
public struct ReaderAgent: Sendable {
    private let reflections: any ReflectionRepository
    private let models: any ModelClientFactory
    private let policy: ReaderAgentPolicy
    private let budget: ExecutionBudget
    private let contextBuilder: ReaderAgentContextBuilder?
    private let sessionContextBuilder: SessionContextBuilder?
    private let contextRouter: any ReaderContextRouting
    private let contextValidator: ContextPlanValidator
    private let traceRepository: (any RoutingTraceRepository)?
    private let memories: (any MemoryRepository)?
    /// Optional semantic recall lane for reflection/memory retrieval (Phase 5).
    /// Nil → the existing lexical-only behavior, unchanged.
    private let semanticRanking: (any SemanticRanking)?

    public init(
        reflections: any ReflectionRepository,
        models: any ModelClientFactory,
        policy: ReaderAgentPolicy = .init(),
        budget: ExecutionBudget = .readerReply,
        contextBuilder: ReaderAgentContextBuilder? = nil,
        sessionContextBuilder: SessionContextBuilder? = nil,
        contextRouter: any ReaderContextRouting = LLMReaderContextRouter(),
        contextValidator: ContextPlanValidator = .init(),
        traceRepository: (any RoutingTraceRepository)? = nil,
        memories: (any MemoryRepository)? = nil,
        semanticRanking: (any SemanticRanking)? = nil
    ) {
        self.reflections = reflections
        self.models = models
        self.policy = policy
        self.budget = budget
        self.contextBuilder = contextBuilder
        self.sessionContextBuilder = sessionContextBuilder
        self.contextRouter = contextRouter
        self.contextValidator = contextValidator
        self.traceRepository = traceRepository
        self.memories = memories
        self.semanticRanking = semanticRanking
    }

    public func respond(to reflectionID: ReflectionID) -> AsyncStream<ReaderAgentEvent> {
        run(reflectionID: reflectionID, followUp: nil)
    }

    /// Persists the user's continuation before making an optional model request.
    /// A stable message ID makes UI retries idempotent.
    public func continueDiscussion(
        on reflectionID: ReflectionID,
        messageID: UUID,
        text: String
    ) -> AsyncStream<ReaderAgentEvent> {
        run(reflectionID: reflectionID, followUp: (messageID, text))
    }

    private func run(
        reflectionID: ReflectionID,
        followUp: (id: UUID, text: String)?
    ) -> AsyncStream<ReaderAgentEvent> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    guard let reflection = try await reflections.reflection(id: reflectionID) else {
                        continuation.yield(.failed(.missingReflection))
                        continuation.finish()
                        return
                    }
                    var messages = try await reflections.messages(for: reflectionID)
                    if let followUp {
                        let content = followUp.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !content.isEmpty else {
                            continuation.yield(.failed(.emptyUserMessage))
                            continuation.finish()
                            return
                        }
                        let userMessage = try ReflectionMessage(
                            id: followUp.id,
                            reflectionID: reflectionID,
                            author: .user,
                            source: .userInput,
                            content: content
                        )
                        try await reflections.appendMessage(userMessage)
                        messages = try await reflections.messages(for: reflectionID)
                        if let index = messages.firstIndex(where: { $0.id == followUp.id }),
                           let completed = messages.dropFirst(index + 1).first(where: { $0.author == .agent }) {
                            continuation.yield(.completed(completed))
                            continuation.finish()
                            return
                        }
                    } else if let completed = messages.last(where: { $0.author == .agent }) {
                        continuation.yield(.completed(completed))
                        continuation.finish()
                        return
                    }

                    let client: any ModelClient
                    do { client = try await models.makeClient() }
                    catch {
                        continuation.yield(.failed(.providerNotConfigured))
                        continuation.finish()
                        return
                    }
                    // Routing is part of the optional Agent request; surface the
                    // loading state before its bounded model call begins.
                    continuation.yield(.started)
                    let evidence = (try? await reflections.evidence(for: reflection.id)) ?? []
                    let currentLocator = evidence.compactMap(\.locator).first
                    // Past-thought retrieval spans all books (WS3): same-book
                    // reflections stay preferred, cross-book ones become eligible,
                    // and long-term memories surface as evidence only.
                    let allCandidates = (try? await reflections.allReflections())?
                        .filter { $0.id != reflection.id } ?? []
                    let sameBookCandidates = allCandidates.filter { $0.bookID == reflection.bookID }
                    let crossBookCandidates = allCandidates.filter { $0.bookID != reflection.bookID }
                    let sessionContext = await sessionContextBuilder?.build(
                        bookID: reflection.bookID,
                        sessionID: reflection.sessionID,
                        excluding: reflection.id
                    ) ?? .empty
                    let routingText = followUp?.text ?? reflection.originalText
                    let matchedMemories = await MemoryRetriever(semantic: semanticRanking).matchingMemories(
                        routingText: routingText,
                        in: memories,
                        topN: 2
                    )
                    let routingInput = ContextRoutingInput(
                        interactionMode: followUp == nil ? .reflection : .conversation,
                        currentReflection: routingText,
                        recentConversation: messages.suffix(6).map {
                            RoutingMessage(role: $0.author == .user ? "user" : "agent", content: String($0.content.prefix(500)))
                        },
                        currentReading: .init(
                            bookID: reflection.bookID,
                            selectedText: currentLocator?.textHighlight,
                            nearbyTextPreview: Self.nearbyPreview(currentLocator),
                            hasCurrentLocator: currentLocator != nil
                        ),
                        availableSources: .init(
                            hasNearbyPassage: currentLocator != nil,
                            hasBookIndex: await contextBuilder?.isAvailable(for: reflection.bookID) ?? false,
                            hasPastThoughts: !allCandidates.isEmpty,
                            hasSessionHighlight: sessionContext.hasSessionHighlight,
                            hasSessionNote: sessionContext.hasSessionNote,
                            hasBookReflections: !sameBookCandidates.isEmpty
                        ),
                        previousAgentAskedQuestion: Self.previousAgentAskedQuestion(in: messages)
                    )
                    let clock = ContinuousClock()
                    let routingStart = clock.now
                    let routingResult = await contextRouter.route(routingInput, using: client)
                    let routingDuration = routingStart.duration(to: clock.now)
                    let plan = contextValidator.validate(routingResult.plan, input: routingInput)
                    let connection: ReflectionConnection?
                    if let pastPlan = plan.pastThoughtRetrieval {
                        // Same-book preference is strict (WS3): a same-book match wins
                        // even over a stronger cross-book one. Each lane fuses lexical +
                        // semantic when a SemanticRanking is configured.
                        if let sameBookMatch = await strongestConnection(for: reflection, query: pastPlan.query, among: sameBookCandidates) {
                            connection = sameBookMatch
                        } else {
                            connection = await strongestConnection(for: reflection, query: pastPlan.query, among: crossBookCandidates)
                        }
                    } else {
                        connection = nil
                    }
                    if let connection { try await reflections.saveConnection(connection) }
                    continuation.yield(.contextPrepared(connection))
                    let prior = connection.flatMap { id in allCandidates.first { $0.id == id.sourceReflectionID } }
                    let retrievalStart = clock.now
                    let bookContext: ReaderAgentBookContext?
                    if let contextBuilder, let retrieval = plan.bookRetrieval {
                        bookContext = try? await contextBuilder.build(
                            bookID: reflection.bookID,
                            reflection: retrieval.query,
                            currentLocator: currentLocator,
                            evidenceLimit: retrieval.maximumEvidenceCount,
                            characterBudget: plan.budget.bookEvidenceCharacters,
                            scope: retrieval.preferredScope == .readSoFar ? .readSoFar : .currentResource
                        )
                    } else {
                        bookContext = nil
                    }
                    let messageID = UUID()
                    let responseEvidence = Self.responseEvidence(
                        messageID: messageID,
                        reflection: reflection,
                        currentEvidence: evidence,
                        previousReflection: prior,
                        longTermMemories: matchedMemories,
                        bookEvidence: bookContext?.evidence ?? [],
                        includeNearbyPassage: plan.nearbyPassage == .include,
                        nearbyCharacterBudget: plan.budget.nearbyCharacters,
                        pastThoughtCharacterBudget: plan.budget.pastThoughtCharacters
                    )
                    let citationBoundary: ReadingBoundary?
                    if let currentLocator, let contextBuilder {
                        citationBoundary = await contextBuilder.readingBoundary(for: reflection.bookID, locator: currentLocator)
                    } else {
                        citationBoundary = nil
                    }
                    let retrievalDuration = retrievalStart.duration(to: clock.now)
                    var completedMessage: ReflectionMessage?
                    var replyUsage: TokenUsage?
                    var replyTruncated = false
                    let replyStart = clock.now
                    for await event in AgentExecutor(client: client, budget: budget).run(
                        input: policy.input(
                            for: reflection,
                            messages: messages,
                            currentEvidence: evidence,
                            previousReflection: prior,
                            bookEvidence: bookContext?.evidence ?? [],
                            responseEvidence: responseEvidence,
                            includeNearbyPassage: plan.nearbyPassage == .include,
                            responseGuidance: plan.responseGuidance,
                            nearbyCharacterBudget: plan.budget.nearbyCharacters,
                            pastThoughtCharacterBudget: plan.budget.pastThoughtCharacters,
                            conversationCharacterBudget: plan.budget.conversationCharacters,
                            sessionContext: sessionContext
                        )
                    ) {
                        switch event {
                        case .textDelta(let text): continuation.yield(.textDelta(text))
                        case .truncated: replyTruncated = true
                        case .usageUpdated(let usage): replyUsage = usage
                        case .completed(let result):
                            let validated = await AgentCitationValidator().validate(
                                content: result.response.content,
                                messageID: messageID,
                                evidence: responseEvidence,
                                bookIndex: contextBuilder?.repository,
                                readingBoundary: citationBoundary
                            )
                            let content = validated.content
                            guard !content.isEmpty else {
                                continuation.yield(.failed(.emptyResponse))
                                continuation.finish()
                                return
                            }
                            let message = try ReflectionMessage(
                                id: messageID,
                                reflectionID: reflection.id,
                                author: .agent,
                                source: .agentGenerated,
                                content: content
                            )
                            continuation.yield(.citationsValidated(.init(
                                evidence: responseEvidence,
                                citations: validated.citations
                            )))
                            do {
                                try await reflections.appendAgentMessage(
                                    message,
                                    evidence: responseEvidence,
                                    citations: validated.citations
                                )
                            }
                            catch {
                                continuation.yield(.failed(.persistence))
                                continuation.finish()
                                return
                            }
                            continuation.yield(.completed(message))
                            completedMessage = message
                        case .cancelled: continuation.yield(.cancelled)
                        case .failed(let failure): continuation.yield(.failed(.runtime(failure)))
                        case .runStarted, .modelStarted: break
                        }
                    }
                    let replyDuration = replyStart.duration(to: clock.now)
                    if completedMessage != nil {
                        continuation.yield(.contextDisclosed(ContextDisclosure(
                            includedNearbyPassage: plan.nearbyPassage == .include,
                            retrievedBookEvidenceCount: bookContext?.evidence.count ?? 0,
                            connectedReflectionID: connection?.sourceReflectionID,
                            usedFallback: routingResult.usedFallback,
                            fallbackReason: routingResult.fallbackReason,
                            routingDuration: routingDuration,
                            retrievalDuration: retrievalDuration,
                            replyTruncated: replyTruncated
                        )))
                        await saveTrace(
                            reflection: reflection,
                            routingResult: routingResult,
                            plan: plan,
                            bookContext: bookContext,
                            connection: connection,
                            routingDuration: routingDuration,
                            retrievalDuration: retrievalDuration,
                            replyDuration: replyDuration,
                            replyUsage: replyUsage
                        )
                    }
                } catch is CancellationError {
                    continuation.yield(.cancelled)
                } catch {
                    continuation.yield(.failed(.persistence))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func saveTrace(
        reflection: Reflection,
        routingResult: ContextRoutingResult,
        plan: ValidatedContextPlan,
        bookContext: ReaderAgentBookContext?,
        connection: ReflectionConnection?,
        routingDuration: Duration,
        retrievalDuration: Duration,
        replyDuration: Duration,
        replyUsage: TokenUsage?
    ) async {
        guard let traceRepository else { return }
        let trace = ContextPlanTrace(
            reflectionID: reflection.id.description,
            proposedPlan: routingResult.plan,
            validatedPlan: plan,
            usedFallback: routingResult.usedFallback,
            fallbackReason: routingResult.fallbackReason,
            fallbackDetail: routingResult.fallbackDetail,
            routingDuration: routingDuration,
            retrievalDuration: retrievalDuration,
            replyDuration: replyDuration,
            selectedBookEvidenceIDs: bookContext?.evidence.map(\.id.rawValue) ?? [],
            connectedReflectionID: connection?.sourceReflectionID.description,
            routingTokenUsage: routingResult.tokenUsage,
            replyTokenUsage: replyUsage
        )
        // Best-effort: a trace-save failure must never break the reply.
        try? await traceRepository.save(trace)
    }

    private func strongestConnection(for reflection: Reflection, query: String, among candidates: [Reflection]) async -> ReflectionConnection? {
        guard let match = await ReflectionRetriever(semantic: semanticRanking).strongestMatch(
            for: query,
            among: candidates
        ) else { return nil }
        return ReflectionConnection(
            reflectionID: reflection.id,
            sourceReflectionID: match.reflection.id,
            relevance: match.relevance
        )
    }

    private static func nearbyPreview(_ locator: BookLocator?) -> String? {
        guard let locator else { return nil }
        let text = [locator.textBefore, locator.textHighlight, locator.textAfter].compactMap { $0 }.joined()
        return text.isEmpty ? nil : String(text.prefix(600))
    }

    private static func previousAgentAskedQuestion(in messages: [ReflectionMessage]) -> Bool {
        guard let agent = messages.last(where: { $0.author == .agent }) else { return false }
        return agent.content.contains("？") || agent.content.contains("?")
    }

    private static func responseEvidence(
        messageID: UUID,
        reflection: Reflection,
        currentEvidence: [ReflectionEvidence],
        previousReflection: Reflection?,
        longTermMemories: [ReaderMemory] = [],
        bookEvidence: [BookEvidence],
        includeNearbyPassage: Bool,
        nearbyCharacterBudget: Int,
        pastThoughtCharacterBudget: Int
    ) -> [AgentResponseEvidence] {
        var snapshots: [(AgentEvidenceKind, String, BookID, String?, String, BookLocator?)] = []
        if includeNearbyPassage, let source = currentEvidence.first(where: { $0.locator != nil }),
           let locator = source.locator {
            let text = [locator.textBefore, locator.textHighlight, locator.textAfter].compactMap { $0 }.joined()
            let excerpt = String(text.prefix(max(0, nearbyCharacterBudget)))
            if !excerpt.isEmpty {
                snapshots.append((.nearbyPassage, source.id.uuidString.lowercased(), reflection.bookID, "当前阅读位置", excerpt, locator))
            }
        }
        snapshots.append(contentsOf: bookEvidence.map { item in
            let title = [item.chapterTitle, item.sectionTitle].compactMap { $0 }.joined(separator: " / ")
            return (.bookPassage, item.id.rawValue, item.bookID, title.isEmpty ? item.locator.href : title, item.excerpt, item.locator)
        })
        if let previousReflection {
            snapshots.append((
                .pastReflection, previousReflection.id.description, previousReflection.bookID, "过去的想法",
                String(previousReflection.originalText.prefix(max(0, pastThoughtCharacterBudget))), nil
            ))
        }
        // Long-term memories are evidence only: they have no source Reflection,
        // so they never create a ReflectionConnection. Memories carry no book;
        // reuse the current reflection's bookID so the persisted row satisfies
        // the agentResponseEvidence.bookID foreign key.
        for memory in longTermMemories {
            snapshots.append((
                .pastReflection, memory.id.uuidString.lowercased(), reflection.bookID, "长期记忆",
                String(memory.claim.prefix(max(0, pastThoughtCharacterBudget))), nil
            ))
        }
        return snapshots.enumerated().map { offset, item in
            AgentResponseEvidence(
                id: "E\(offset + 1)", messageID: messageID, kind: item.0, sourceID: item.1,
                bookID: item.2, title: item.3, excerpt: item.4, locator: item.5
            )
        }
    }

}

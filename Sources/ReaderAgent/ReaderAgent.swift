import AgentRuntime
import ContextRouting
import Foundation
import ReaderCore
import ReflectionCore
import RetrievalCore

public enum ReaderAgentEvent: Equatable, Sendable {
    case started
    case contextPrepared(ReflectionConnection?)
    case textDelta(String)
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

    public init(
        includedNearbyPassage: Bool,
        retrievedBookEvidenceCount: Int,
        connectedReflectionID: ReflectionID?,
        usedFallback: Bool,
        fallbackReason: RoutingFallbackReason?,
        routingDuration: Duration,
        retrievalDuration: Duration
    ) {
        self.includedNearbyPassage = includedNearbyPassage
        self.retrievedBookEvidenceCount = retrievedBookEvidenceCount
        self.connectedReflectionID = connectedReflectionID
        self.usedFallback = usedFallback
        self.fallbackReason = fallbackReason
        self.routingDuration = routingDuration
        self.retrievalDuration = retrievalDuration
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
    private let contextRouter: any ReaderContextRouting
    private let contextValidator: ContextPlanValidator
    private let traceRepository: (any RoutingTraceRepository)?

    public init(
        reflections: any ReflectionRepository,
        models: any ModelClientFactory,
        policy: ReaderAgentPolicy = .init(),
        budget: ExecutionBudget = .readerReply,
        contextBuilder: ReaderAgentContextBuilder? = nil,
        contextRouter: any ReaderContextRouting = LLMReaderContextRouter(),
        contextValidator: ContextPlanValidator = .init(),
        traceRepository: (any RoutingTraceRepository)? = nil
    ) {
        self.reflections = reflections
        self.models = models
        self.policy = policy
        self.budget = budget
        self.contextBuilder = contextBuilder
        self.contextRouter = contextRouter
        self.contextValidator = contextValidator
        self.traceRepository = traceRepository
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
                    let candidates = (try? await reflections.recentReflections(limit: 50))?
                        .filter { $0.id != reflection.id } ?? []
                    let routingText = followUp?.text ?? reflection.originalText
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
                            hasPastThoughts: !candidates.isEmpty
                        ),
                        previousAgentAskedQuestion: Self.previousAgentAskedQuestion(in: messages)
                    )
                    let clock = ContinuousClock()
                    let routingStart = clock.now
                    let routingResult = await contextRouter.route(routingInput, using: client)
                    let routingDuration = routingStart.duration(to: clock.now)
                    let plan = contextValidator.validate(routingResult.plan, input: routingInput)
                    let connection = plan.pastThoughtRetrieval.flatMap { pastPlan in
                        strongestConnection(for: reflection, query: pastPlan.query, among: candidates)
                    }
                    if let connection { try await reflections.saveConnection(connection) }
                    continuation.yield(.contextPrepared(connection))
                    let prior = connection.flatMap { id in candidates.first { $0.id == id.sourceReflectionID } }
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
                    let retrievalDuration = retrievalStart.duration(to: clock.now)
                    var completedMessage: ReflectionMessage?
                    var replyUsage: TokenUsage?
                    let replyStart = clock.now
                    for await event in AgentExecutor(client: client, budget: budget).run(
                        input: policy.input(
                            for: reflection,
                            messages: messages,
                            currentEvidence: evidence,
                            previousReflection: prior,
                            bookEvidence: bookContext?.evidence ?? [],
                            includeNearbyPassage: plan.nearbyPassage == .include,
                            responseGuidance: plan.responseGuidance,
                            nearbyCharacterBudget: plan.budget.nearbyCharacters,
                            pastThoughtCharacterBudget: plan.budget.pastThoughtCharacters,
                            conversationCharacterBudget: plan.budget.conversationCharacters
                        )
                    ) {
                        switch event {
                        case .textDelta(let text): continuation.yield(.textDelta(text))
                        case .usageUpdated(let usage): replyUsage = usage
                        case .completed(let result):
                            let content = result.response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !content.isEmpty else {
                                continuation.yield(.failed(.emptyResponse))
                                continuation.finish()
                                return
                            }
                            let message = try ReflectionMessage(
                                reflectionID: reflection.id,
                                author: .agent,
                                source: .agentGenerated,
                                content: content
                            )
                            do { try await reflections.appendMessage(message) }
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
                            retrievalDuration: retrievalDuration
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

    private func strongestConnection(for reflection: Reflection, query: String, among candidates: [Reflection]) -> ReflectionConnection? {
        guard let match = ReflectionLexicalMatcher.strongestMatch(
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
}

public enum ReflectionLexicalMatcher {
    public struct Match: Hashable, Sendable {
        public let reflection: Reflection
        public let relevance: Double
    }

    /// Conservative lexical retrieval: at least two shared meaningful tokens and
    /// a 40% overlap against the smaller thought. This favors silence over a weak
    /// or performative personal connection.
    public static func strongestMatch(
        for query: String,
        among candidates: [Reflection]
    ) -> Match? {
        let queryTokens = tokens(in: query)
        guard queryTokens.count >= 2 else { return nil }
        return candidates.compactMap { reflection -> Match? in
            let candidateTokens = tokens(in: reflection.originalText)
            let overlap = queryTokens.intersection(candidateTokens).count
            guard overlap >= 2 else { return nil }
            let relevance = Double(overlap) / Double(max(1, min(queryTokens.count, candidateTokens.count)))
            guard relevance >= 0.40 else { return nil }
            return Match(reflection: reflection, relevance: relevance)
        }
        .max { lhs, rhs in
            if lhs.relevance == rhs.relevance {
                return lhs.reflection.createdAt < rhs.reflection.createdAt
            }
            return lhs.relevance < rhs.relevance
        }
    }

    private static func tokens(in text: String) -> Set<String> {
        let lowered = text.lowercased()
        let words = lowered.split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 2 }
        let cjk = lowered.unicodeScalars.filter { scalar in
            (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
        }
        let bigrams = zip(cjk, cjk.dropFirst()).map { String($0) + String($1) }
        return Set(words + bigrams)
    }
}

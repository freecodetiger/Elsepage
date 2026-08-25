import AgentRuntime
import ContextRouting
import Foundation
import LibraryCore
import ReaderCore
import ReflectionCore
import RetrievalCore

public enum ReaderAgentEvent: Equatable, Sendable {
    case started
    case contextPrepared(ReflectionConnection?)
    case textDelta(String)
    case completed(ReflectionMessage)
    case cancelled
    case failed(ReaderAgentFailure)
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

    public init(
        reflections: any ReflectionRepository,
        models: any ModelClientFactory,
        policy: ReaderAgentPolicy = .init(),
        budget: ExecutionBudget = .readerReply,
        contextBuilder: ReaderAgentContextBuilder? = nil,
        contextRouter: any ReaderContextRouting = LLMReaderContextRouter(),
        contextValidator: ContextPlanValidator = .init()
    ) {
        self.reflections = reflections
        self.models = models
        self.policy = policy
        self.budget = budget
        self.contextBuilder = contextBuilder
        self.contextRouter = contextRouter
        self.contextValidator = contextValidator
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
                    let routingResult = await contextRouter.route(routingInput, using: client)
                    let plan = contextValidator.validate(routingResult.plan, input: routingInput)
                    let connection = plan.pastThoughtRetrieval.flatMap { pastPlan in
                        strongestConnection(for: reflection, query: pastPlan.query, among: candidates)
                    }
                    if let connection { try await reflections.saveConnection(connection) }
                    continuation.yield(.contextPrepared(connection))
                    let prior = connection.flatMap { id in candidates.first { $0.id == id.sourceReflectionID } }
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
                        bookEvidence: bookContext?.evidence ?? [],
                        includeNearbyPassage: plan.nearbyPassage == .include,
                        nearbyCharacterBudget: plan.budget.nearbyCharacters,
                        pastThoughtCharacterBudget: plan.budget.pastThoughtCharacters
                    )
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
                            conversationCharacterBudget: plan.budget.conversationCharacters
                        )
                    ) {
                        switch event {
                        case .textDelta(let text): continuation.yield(.textDelta(text))
                        case .completed(let result):
                            let validated = AgentCitationValidator().validate(
                                content: result.response.content,
                                messageID: messageID,
                                evidence: responseEvidence
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
                        case .cancelled: continuation.yield(.cancelled)
                        case .failed(let failure): continuation.yield(.failed(.runtime(failure)))
                        case .runStarted, .modelStarted, .usageUpdated: break
                        }
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

    private static func responseEvidence(
        messageID: UUID,
        reflection: Reflection,
        currentEvidence: [ReflectionEvidence],
        previousReflection: Reflection?,
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
        return snapshots.enumerated().map { offset, item in
            AgentResponseEvidence(
                id: "E\(offset + 1)", messageID: messageID, kind: item.0, sourceID: item.1,
                bookID: item.2, title: item.3, excerpt: item.4, locator: item.5
            )
        }
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

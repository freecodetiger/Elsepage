import AgentRuntime
import Foundation
import ReflectionCore

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

    public init(
        reflections: any ReflectionRepository,
        models: any ModelClientFactory,
        policy: ReaderAgentPolicy = .init(),
        budget: ExecutionBudget = .readerReply
    ) {
        self.reflections = reflections
        self.models = models
        self.policy = policy
        self.budget = budget
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

                    let connection = try? await strongestConnection(for: reflection)
                    if let connection { try await reflections.saveConnection(connection) }
                    continuation.yield(.contextPrepared(connection))
                    let client: any ModelClient
                    do { client = try await models.makeClient() }
                    catch {
                        continuation.yield(.failed(.providerNotConfigured))
                        continuation.finish()
                        return
                    }

                    continuation.yield(.started)
                    let prior: Reflection?
                    if let connection {
                        prior = try? await awaitReflection(connection.sourceReflectionID)
                    } else {
                        prior = nil
                    }
                    let evidence = (try? await reflections.evidence(for: reflection.id)) ?? []
                    for await event in AgentExecutor(client: client, budget: budget).run(
                        input: policy.input(
                            for: reflection,
                            messages: messages,
                            currentEvidence: evidence,
                            previousReflection: prior
                        )
                    ) {
                        switch event {
                        case .textDelta(let text): continuation.yield(.textDelta(text))
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

    private func awaitReflection(_ id: ReflectionID) async throws -> Reflection? {
        try await reflections.reflection(id: id)
    }

    private func strongestConnection(for reflection: Reflection) async throws -> ReflectionConnection? {
        let candidates = try await reflections.recentReflections(limit: 50)
            .filter { $0.id != reflection.id }
        guard let match = ReflectionLexicalMatcher.strongestMatch(
            for: reflection.originalText,
            among: candidates
        ) else { return nil }
        return ReflectionConnection(
            reflectionID: reflection.id,
            sourceReflectionID: match.reflection.id,
            relevance: match.relevance
        )
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

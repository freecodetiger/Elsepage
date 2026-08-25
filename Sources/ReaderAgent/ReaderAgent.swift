import AgentRuntime
import Foundation
import ReflectionCore

public enum ReaderAgentEvent: Equatable, Sendable {
    case started
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
        AsyncStream { continuation in
            let task = Task {
                do {
                    guard let reflection = try await reflections.reflection(id: reflectionID) else {
                        continuation.yield(.failed(.missingReflection))
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

                    continuation.yield(.started)
                    for await event in AgentExecutor(client: client, budget: budget).run(input: policy.input(for: reflection)) {
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
}

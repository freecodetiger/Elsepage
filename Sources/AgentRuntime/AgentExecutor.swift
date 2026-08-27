import Foundation

/// Bounded, streaming-first execution for the current deterministic one-model workflow.
public struct AgentExecutor: Sendable {
    private let client: any ModelClient
    private let budget: ExecutionBudget

    public init(client: any ModelClient, budget: ExecutionBudget) {
        self.client = client
        self.budget = budget
    }

    public func run(input: AgentInput) -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            let task = Task {
                let runID = AgentRunID()
                continuation.yield(.runStarted(runID))
                guard budget.maxModelCalls > 0 else {
                    continuation.yield(.failed(.budgetExceeded))
                    continuation.finish()
                    return
                }

                do {
                    let response = try await executeModelCall(input: input, continuation: continuation)
                    try Task.checkCancellation()
                    if response.finishReason == "length" { continuation.yield(.truncated) }
                    continuation.yield(.completed(.init(
                        runID: runID,
                        metadata: input.metadata,
                        response: response
                    )))
                } catch is CancellationError {
                    continuation.yield(.cancelled)
                } catch let failure as AgentFailure {
                    continuation.yield(.failed(failure))
                } catch let failure as ModelFailure {
                    continuation.yield(.failed(Self.normalize(failure)))
                } catch {
                    continuation.yield(.failed(.unknown))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func executeModelCall(
        input: AgentInput,
        continuation: AsyncStream<AgentEvent>.Continuation
    ) async throws -> ModelResponse {
        continuation.yield(.modelStarted(.init()))
        return try await withThrowingTaskGroup(of: ModelResponse.self) { group in
            group.addTask {
                var completed: ModelResponse?
                let request = ModelRequest(
                    messages: input.messages,
                    temperature: input.temperature,
                    maxOutputTokens: budget.maxOutputTokens,
                    responseFormat: input.responseFormat
                )
                for try await event in client.stream(request: request) {
                    try Task.checkCancellation()
                    guard completed == nil else { throw AgentFailure.malformedProviderResponse }
                    switch event {
                    case .started: break
                    case .textDelta(let text): continuation.yield(.textDelta(text))
                    case .usage(let usage): continuation.yield(.usageUpdated(usage))
                    case .completed(let response):
                        guard completed == nil else { throw AgentFailure.malformedProviderResponse }
                        completed = response
                    }
                }
                guard let completed else { throw AgentFailure.malformedProviderResponse }
                return completed
            }
            group.addTask {
                try await Task.sleep(for: budget.maxWallTime)
                throw AgentFailure.budgetExceeded
            }
            guard let first = try await group.next() else { throw AgentFailure.malformedProviderResponse }
            group.cancelAll()
            return first
        }
    }

    private static func normalize(_ failure: ModelFailure) -> AgentFailure {
        switch failure {
        case .authentication: .authentication
        case .rateLimited: .rateLimited
        case .providerUnavailable: .providerUnavailable
        case .network: .network
        case .invalidConfiguration: .providerUnavailable
        case .invalidResponse: .malformedProviderResponse
        case .providerMessage: .providerUnavailable
        }
    }
}

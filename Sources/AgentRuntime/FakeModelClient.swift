import Foundation

/// Deterministic model adapter for runtime and product tests.
public struct FakeModelClient: ModelClient {
    public let descriptor: ModelDescriptor
    private let events: [ModelEvent]
    private let terminalFailure: ModelFailure?
    private let eventDelay: Duration

    public init(
        events: [ModelEvent],
        terminalFailure: ModelFailure? = nil,
        eventDelay: Duration = .zero
    ) {
        descriptor = ModelDescriptor(provider: "fake", model: "scripted", capabilities: .init(supportsStreaming: true))
        self.events = events
        self.terminalFailure = terminalFailure
        self.eventDelay = eventDelay
    }

    public func stream(request: ModelRequest) -> AsyncThrowingStream<ModelEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for event in events {
                        try Task.checkCancellation()
                        if eventDelay > .zero { try await Task.sleep(for: eventDelay) }
                        continuation.yield(event)
                    }
                    if let terminalFailure { throw terminalFailure }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

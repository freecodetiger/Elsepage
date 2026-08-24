import Foundation

/// Deterministic model client for Agent and feature tests. It has no network or
/// secret dependency and never records request content.
public struct FakeModelClient: ModelClient {
    public let capabilities: ModelCapabilities
    private let script: [ModelEvent]

    public init(script: [ModelEvent], capabilities: ModelCapabilities = .init()) {
        self.script = script
        self.capabilities = capabilities
    }

    public func stream(request: ModelRequest) -> AsyncThrowingStream<ModelEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in script { continuation.yield(event) }
            continuation.finish()
        }
    }
}

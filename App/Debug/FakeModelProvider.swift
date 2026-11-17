#if DEBUG
import AgentRuntime
import Foundation

/// Deterministic AI chain for UI tests. `-fake-provider` streams a short answer,
/// `-fake-provider slow` streams long enough to press stop, and
/// `-fake-provider failure` fails after starting so the retry path is reachable.
///
/// DEBUG-only and opt-in: without the launch argument the real factory is used.
enum FakeModelProvider {
    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> (any ModelClientFactory)? {
        guard let index = arguments.firstIndex(of: "-fake-provider") else { return nil }
        let raw = arguments.indices.contains(index + 1) ? arguments[index + 1] : ""
        return FakeModelClientFactory(mode: Mode(rawValue: raw) ?? .normal)
    }

    enum Mode: String {
        case normal
        case slow
        case failure
    }
}

struct FakeModelClientFactory: ModelClientFactory {
    let mode: FakeModelProvider.Mode

    func makeClient() async throws -> any ModelClient {
        FakeModelClient(mode: mode)
    }
}

struct FakeModelClient: ModelClient {
    let mode: FakeModelProvider.Mode

    var descriptor: ModelDescriptor {
        ModelDescriptor(
            provider: "fake",
            model: "fake-reader",
            capabilities: ModelCapabilities(supportsStreaming: true)
        )
    }

    func stream(request: ModelRequest) -> AsyncThrowingStream<ModelEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.started)
                do {
                    if mode == .failure {
                        try await Task.sleep(for: .milliseconds(200))
                        throw ModelFailure.network
                    }

                    let chunks =
                        mode == .slow
                        ? Array(repeating: "这一段还可以继续展开，", count: 12) + ["收束 [E1]。"]
                        : ["重读的代价在于，", "你已经知道后面会发生什么，", "惊喜因此变弱 [E1]。"]
                    for chunk in chunks {
                        try await Task.sleep(for: .milliseconds(mode == .slow ? 500 : 350))
                        continuation.yield(.textDelta(chunk))
                    }
                    continuation.yield(
                        .completed(
                            ModelResponse(
                                content: chunks.joined(),
                                finishReason: "stop",
                                usage: TokenUsage(inputTokens: 12, outputTokens: 24, totalTokens: 36)
                            )))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
#endif

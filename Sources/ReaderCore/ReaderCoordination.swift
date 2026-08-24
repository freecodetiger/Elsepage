/// Generation state for keeping the newest value across overlapping writes.
public struct LatestValueState<Value: Sendable>: Sendable {
    public struct Ticket: Sendable {
        fileprivate let generation: UInt64
        public let value: Value
    }

    private var generation: UInt64 = 0
    private var isWriting = false
    public private(set) var pending: Ticket?

    public init() {}

    public mutating func submit(_ value: Value) {
        generation &+= 1
        pending = Ticket(generation: generation, value: value)
    }

    public mutating func beginWrite() -> Ticket? {
        guard !isWriting, let pending else { return nil }
        isWriting = true
        return pending
    }

    public mutating func didWrite(_ target: Ticket, succeeded: Bool) {
        isWriting = false
        if succeeded, pending?.generation == target.generation {
            pending = nil
        }
    }
}

/// Token state for rejecting stale asynchronous request results.
public struct LatestRequestState: Sendable {
    public private(set) var token: UInt64 = 0
    public private(set) var isLoading = false

    public init() {}

    public mutating func begin() -> UInt64 {
        token &+= 1
        isLoading = true
        return token
    }

    public mutating func invalidate() {
        token &+= 1
        isLoading = false
    }

    public mutating func finish(_ candidate: UInt64) -> Bool {
        guard candidate == token else { return false }
        isLoading = false
        return true
    }
}

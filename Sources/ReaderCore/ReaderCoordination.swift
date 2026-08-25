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

/// Small in-memory return stack for explicit TOC, search, and annotation jumps.
public struct LocatorHistory: Sendable {
    private let capacity: Int
    public private(set) var entries: [BookLocator] = []

    public init(capacity: Int = 12) {
        self.capacity = max(1, capacity)
    }

    public var canGoBack: Bool { !entries.isEmpty }

    public mutating func record(_ locator: BookLocator) {
        guard entries.last?.identifiesSameAnchor(as: locator) != true else { return }
        entries.append(locator)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    public mutating func pop() -> BookLocator? {
        entries.popLast()
    }
}

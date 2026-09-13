import Foundation

/// Accumulates model text deltas separately from the text currently shown by
/// the conversation view. This lets the UI coalesce frequent deltas without
/// changing the final visible string or the caller's filtering rules.
public struct StreamingResponseBuffer: Equatable, Sendable {
    public private(set) var visibleText = ""

    private var sourceText = ""
    private var hasUnflushedText = false

    public init() {}

    public var hasPendingText: Bool { hasUnflushedText }

    /// Starts a new response and drops any state left by the previous one.
    public mutating func begin() {
        visibleText.removeAll()
        sourceText.removeAll()
        hasUnflushedText = false
    }

    /// Appends a provider delta without asking the UI to render yet.
    public mutating func append(_ delta: String) {
        sourceText.append(contentsOf: delta)
        hasUnflushedText = true
    }

    /// Publishes all pending text after applying the caller's display filter.
    /// The filter runs once per flush, rather than once per provider delta.
    @discardableResult
    public mutating func flush(using transform: (String) -> String) -> String {
        guard hasUnflushedText else { return visibleText }
        visibleText = transform(sourceText)
        hasUnflushedText = false
        return visibleText
    }

    /// Drops pending text while preserving the last visible partial response.
    /// This is used when a stream fails or is cancelled after a final flush.
    public mutating func discardPending() {
        hasUnflushedText = false
    }

    /// Ends the response and clears both pending and visible text.
    public mutating func complete() {
        visibleText.removeAll()
        sourceText.removeAll()
        hasUnflushedText = false
    }
}

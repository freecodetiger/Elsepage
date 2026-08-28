import Foundation

/// Per-book card statistics for the library grid (PRD §6.2 V1). Derived only
/// from existing tables — reading session durations, highlights and
/// reflections — so it adds no new data collection and works offline.
public struct BookLibraryStats: Hashable, Sendable {
    /// Cumulative wall-clock reading time across ended sessions, in seconds.
    public var readingSeconds: TimeInterval
    public var highlightCount: Int
    public var reflectionCount: Int

    public init(readingSeconds: TimeInterval = 0, highlightCount: Int = 0, reflectionCount: Int = 0) {
        self.readingSeconds = readingSeconds
        self.highlightCount = highlightCount
        self.reflectionCount = reflectionCount
    }

    /// Compact, quiet card copy such as "读过 24 分钟 · 划线 3 · 想法 2".
    /// Zero values are omitted instead of shown, so a fresh book renders no
    /// metadata line at all (PRD §10.1: metadata, not a dashboard).
    public var metadataDescription: String? {
        var parts: [String] = []
        if let duration = readingDurationDescription { parts.append("读过 \(duration)") }
        if highlightCount > 0 { parts.append("划线 \(highlightCount)") }
        if reflectionCount > 0 { parts.append("想法 \(reflectionCount)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "24 分钟" / "3 小时 12 分" / "3 小时"。Sub-minute time stays quiet (nil).
    public var readingDurationDescription: String? {
        let minutes = Int(readingSeconds / 60)
        guard minutes >= 1 else { return nil }
        guard minutes >= 60 else { return "\(minutes) 分钟" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) 小时" : "\(hours) 小时 \(remainder) 分"
    }
}

import Foundation

/// Consecutive days (ending today, or yesterday as grace) with at least one reading session.
public struct ReadingStreak: Hashable, Sendable {
    public let days: Int
    public init(days: Int) { self.days = days }
}

/// Consecutive days (ending today, or yesterday as grace) with at least one reflection.
/// The product's core differentiator — must stay at least as visible as `ReadingStreak`.
public struct ThinkingStreak: Hashable, Sendable {
    public let days: Int
    public init(days: Int) { self.days = days }
}

/// Deterministic, pure streak derivation from repository timestamps.
/// Each day counts once no matter how many entries; a gap breaks the streak;
/// empty history is 0. The streak is anchored at today, or yesterday as a grace
/// so an early-morning user (today at ~00:30) does not lose it.
public enum StreakCalculator {
    public static func readingStreak(
        sessionStartDates: [Date], now: Date, calendar: Calendar
    ) -> ReadingStreak {
        ReadingStreak(days: consecutiveDays(sessionStartDates, now: now, calendar: calendar))
    }

    public static func thinkingStreak(
        reflectionDates: [Date], now: Date, calendar: Calendar
    ) -> ThinkingStreak {
        ThinkingStreak(days: consecutiveDays(reflectionDates, now: now, calendar: calendar))
    }

    private static func consecutiveDays(_ dates: [Date], now: Date, calendar: Calendar) -> Int {
        let days = Set(dates.map { calendar.startOfDay(for: $0) })
        guard !days.isEmpty else { return 0 }
        let today = calendar.startOfDay(for: now)
        if days.contains(today) {
            return countBackwards(from: today, in: days, calendar: calendar)
        }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              days.contains(yesterday) else { return 0 }
        return countBackwards(from: yesterday, in: days, calendar: calendar)
    }

    private static func countBackwards(from anchor: Date, in days: Set<Date>, calendar: Calendar) -> Int {
        var count = 0
        var day = anchor
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}

import Foundation
import LibraryCore
import ReflectionCore

/// Deterministic, low-key achievement badges (PRD F13). They reward meaningful
/// thinking behaviors and never influence the Agent's content judgment.
///
/// Questioner / Changed My Mind need content judgment (Agent structured output);
/// they are deliberately not part of the first deterministic batch and can be
/// added as new `AchievementID` cases plus an `AchievementEvent` extension once
/// the ReaderAgentBench harness exists.
public enum AchievementID: String, CaseIterable, Hashable, Codable, Sendable {
    case firstReflection
    case connector
    case sevenDaysThinking
    case returnToAnIdea
}

public struct Achievement: Hashable, Sendable, Identifiable {
    public let id: AchievementID
    public let title: String
    public let systemImage: String
    public let blurb: String

    public init(id: AchievementID, title: String, systemImage: String, blurb: String) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.blurb = blurb
    }
}

public extension Achievement {
    static let all: [Achievement] = [
        Achievement(id: .firstReflection, title: "第一次留下想法", systemImage: "quote.bubble", blurb: "完成第一次阅读反思"),
        Achievement(id: .connector, title: "连接两本书", systemImage: "link", blurb: "第一次把当前读到的东西和另一本书联系起来"),
        Achievement(id: .sevenDaysThinking, title: "连续思考七天", systemImage: "calendar", blurb: "连续 7 天完成有效反思"),
        Achievement(id: .returnToAnIdea, title: "回到一个旧想法", systemImage: "clock.arrow.circlepath", blurb: "重新讨论了 30 天前的想法"),
    ]
}

/// Where an unlock came from, so the record stays traceable to evidence (P7 spirit).
public struct AchievementSource: Hashable, Codable, Sendable {
    public let reflectionID: ReflectionID?
    public let bookID: BookID?

    public init(reflectionID: ReflectionID? = nil, bookID: BookID? = nil) {
        self.reflectionID = reflectionID
        self.bookID = bookID
    }
}

/// One unlocked badge. `id` is the primary key: an achievement unlocks exactly once.
public struct AchievementRecord: Hashable, Codable, Sendable, Identifiable {
    public let id: AchievementID
    public let unlockedAt: Date
    public let source: AchievementSource?

    public init(id: AchievementID, unlockedAt: Date, source: AchievementSource? = nil) {
        self.id = id
        self.unlockedAt = unlockedAt
        self.source = source
    }
}

/// A past reflection the Agent surfaced during this discussion (「过去的你」).
public struct ConnectedSource: Hashable, Sendable {
    public let reflection: Reflection
    public let bookID: BookID

    public init(reflection: Reflection, bookID: BookID) {
        self.reflection = reflection
        self.bookID = bookID
    }
}

/// A behavior moment the achievement system reacts to. Emitted from the App layer
/// at the exact places a reflection is saved or a cross-reflection connection is
/// established — the ReaderAgent pipeline itself is untouched.
public struct AchievementEvent: Sendable {
    public let reflection: Reflection
    public let connectedSource: ConnectedSource?
    public let now: Date

    public init(reflection: Reflection, connectedSource: ConnectedSource?, now: Date) {
        self.reflection = reflection
        self.connectedSource = connectedSource
        self.now = now
    }
}

public protocol AchievementRepository: Sendable {
    func unlocked() async throws -> [AchievementRecord]
    func insert(_ record: AchievementRecord) async throws
}

/// Deterministic trigger evaluation. A not-yet-unlocked achievement is recorded
/// the first time its predicate passes; unlock-once is enforced by the PK.
public struct AchievementService: Sendable {
    private let repository: any AchievementRepository
    private let reflections: any ReflectionRepository

    public init(repository: any AchievementRepository, reflections: any ReflectionRepository) {
        self.repository = repository
        self.reflections = reflections
    }

    public func unlocked() async throws -> [AchievementRecord] {
        try await repository.unlocked()
    }

    /// Evaluates the event against every still-locked achievement, persists new
    /// unlocks, and returns them so the UI can surface a toast.
    public func evaluate(_ event: AchievementEvent) async throws -> [AchievementRecord] {
        let already = Set(try await repository.unlocked().map(\.id))
        var created: [AchievementRecord] = []
        for definition in Achievement.all where !already.contains(definition.id) {
            if try await triggers(definition.id, event: event) {
                let record = AchievementRecord(
                    id: definition.id,
                    unlockedAt: event.now,
                    source: source(for: definition.id, event: event)
                )
                try await repository.insert(record)
                created.append(record)
            }
        }
        return created
    }

    private func triggers(_ id: AchievementID, event: AchievementEvent) async throws -> Bool {
        switch id {
        case .firstReflection:
            return try await reflections.allReflections().count == 1
        case .sevenDaysThinking:
            let dates = try await reflections.allReflections().map(\.createdAt)
            return StreakCalculator.thinkingStreak(reflectionDates: dates, now: event.now, calendar: .current).days >= 7
        case .connector:
            guard let source = event.connectedSource else { return false }
            return source.bookID != event.reflection.bookID
        case .returnToAnIdea:
            guard let source = event.connectedSource else { return false }
            return event.now.timeIntervalSince(source.reflection.createdAt) >= Self.thirtyDays
        }
    }

    private func source(for id: AchievementID, event: AchievementEvent) -> AchievementSource? {
        switch id {
        case .firstReflection, .sevenDaysThinking:
            return AchievementSource(reflectionID: event.reflection.id, bookID: event.reflection.bookID)
        case .connector, .returnToAnIdea:
            guard let connected = event.connectedSource else { return nil }
            return AchievementSource(reflectionID: connected.reflection.id, bookID: connected.bookID)
        }
    }

    private static let thirtyDays: TimeInterval = 30 * 24 * 60 * 60
}

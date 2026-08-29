import Foundation
import LibraryCore
import ReflectionCore

/// Deterministic, low-key achievement badges (PRD F13). They reward meaningful
/// thinking behaviors and never influence the Agent's content judgment.
public enum AchievementID: String, CaseIterable, Hashable, Codable, Sendable {
    case firstReflection
    case connector
    case questioner
    case changedMyMind
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
        Achievement(id: .questioner, title: "第一次质疑作者", systemImage: "questionmark.circle", blurb: "第一次明确质疑作者的说法"),
        Achievement(id: .changedMyMind, title: "改变了想法", systemImage: "arrow.triangle.2.circlepath", blurb: "主动修改了自己先前的一个观点"),
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
/// at the exact places a reflection is saved, a user message is sent, a
/// cross-reflection connection is established, or the user revises a memory —
/// the ReaderAgent pipeline itself is untouched.
public enum AchievementEvent: Sendable {
    /// A reflection moment: the user's output exists (and optionally connects to
    /// a past reflection the Agent surfaced during this discussion).
    case reflection(Reflection, connectedSource: ConnectedSource?, now: Date)
    /// The user revised or retired a memory themselves (My Mind 修改 / 不准确).
    /// Deterministic on the user action — never on Agent inference (FIX-03).
    case userMemoryRevision(now: Date)
}

/// Conservative, documented trigger for the Questioner badge (PRD F13
/// 「第一次明确质疑作者」). Deliberately a narrow keyword heuristic, not NLP:
/// only explicit, hard-to-misread challenge markers count, and they are only ever
/// matched against the user's own words (the Reflection text and the user's
/// follow-up messages) — never against Agent output (F13: achievements do not
/// judge content quality). Chinese-only because the product language is Chinese;
/// false negatives are preferred over false positives by design.
public enum QuestionerHeuristic {
    /// Explicit disagreement/challenge markers.
    static let markers: [String] = [
        // Direct first-person disagreement.
        "不认同", "不同意", "不敢苟同", "恰恰相反",
        // Generic challenge.
        "质疑",
        // Author-directed objections.
        "作者错了", "作者说错", "作者搞错", "作者忽略", "作者忽视",
        "怀疑作者", "反驳作者",
    ]

    public static func expressesExplicitChallenge(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return markers.contains { lowered.contains($0) }
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
                    unlockedAt: eventDate(event),
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
            guard case .reflection = event else { return false }
            return try await reflections.allReflections().count == 1
        case .sevenDaysThinking:
            guard case .reflection = event else { return false }
            let dates = try await reflections.allReflections().map(\.createdAt)
            return StreakCalculator.thinkingStreak(reflectionDates: dates, now: eventDate(event), calendar: .current).days >= 7
        case .connector:
            guard case .reflection(_, let connectedSource, _) = event, let connectedSource else { return false }
            return connectedSource.bookID != eventReflection(event).bookID
        case .returnToAnIdea:
            guard case .reflection(_, let connectedSource, _) = event, let connectedSource else { return false }
            return eventDate(event).timeIntervalSince(connectedSource.reflection.createdAt) >= Self.thirtyDays
        case .questioner:
            guard case .reflection(let reflection, _, _) = event else { return false }
            // Only the user's own words qualify: the Reflection text (both the raw
            // transcript and the kept version) plus the user's follow-up messages.
            var texts = [reflection.originalText, reflection.displayText]
            let messages = try await reflections.messages(for: reflection.id)
            texts += messages.filter { $0.author == .user }.map(\.content)
            return texts.contains { QuestionerHeuristic.expressesExplicitChallenge($0) }
        case .changedMyMind:
            // Exclusively the user's own revise/supersede action in My Mind.
            guard case .userMemoryRevision = event else { return false }
            return true
        }
    }

    private func source(for id: AchievementID, event: AchievementEvent) -> AchievementSource? {
        switch id {
        case .firstReflection, .sevenDaysThinking, .questioner:
            let reflection = eventReflection(event)
            return AchievementSource(reflectionID: reflection.id, bookID: reflection.bookID)
        case .connector, .returnToAnIdea:
            guard case .reflection(_, let connectedSource, _) = event, let connectedSource else { return nil }
            return AchievementSource(reflectionID: connectedSource.reflection.id, bookID: connectedSource.bookID)
        case .changedMyMind:
            // A pure user action; no reflection needs to be attached.
            return nil
        }
    }

    private func eventReflection(_ event: AchievementEvent) -> Reflection {
        guard case .reflection(let reflection, _, _) = event else {
            preconditionFailure("Reflection event field accessed for a non-reflection event")
        }
        return reflection
    }

    private func eventDate(_ event: AchievementEvent) -> Date {
        switch event {
        case .reflection(_, _, let now): now
        case .userMemoryRevision(let now): now
        }
    }

    private static let thirtyDays: TimeInterval = 30 * 24 * 60 * 60
}

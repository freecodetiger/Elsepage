import Foundation
import LibraryCore
import ReadingSessionCore

/// Repository-derived state for the product entry point. It contains no UI or
/// navigation concepts and is deterministic for a supplied clock/calendar.
public enum TodayProductState: Hashable, Sendable {
    case noCurrentBook
    case continueReading(Book)
    case offerReflection(Book, ReadingSession)
    case reflectionComplete(Book)
}

public enum TodayProductStateResolver {
    /// `dismissedSessionIDs` carries the sessions the user explicitly chose not
    /// to reflect on ("今天先不了"); completion is normally derived from the
    /// reflections table, so only an explicit dismissal needs this input.
    public static func resolve(
        currentBook: Book?,
        sessions: [ReadingSession],
        reflections: [Reflection],
        dismissedSessionIDs: Set<ReadingSessionID> = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TodayProductState {
        guard let currentBook else { return .noCurrentBook }
        if let session = sessions
            .filter({ SessionEndingSummary(session: $0).shouldOfferReflection })
            .sorted(by: { $0.startedAt > $1.startedAt })
            .first(where: { session in
                !dismissedSessionIDs.contains(session.id)
                    && !reflections.contains(where: { $0.sessionID == session.id })
            }) {
            return .offerReflection(currentBook, session)
        }
        if reflections.contains(where: { calendar.isDate($0.createdAt, inSameDayAs: now) }) {
            return .reflectionComplete(currentBook)
        }
        return .continueReading(currentBook)
    }
}

/// Remembers the sessions for which the user explicitly declined the Today
/// reflection prompt ("今天先不了"), so the 补写 card does not reappear for the
/// same session. Everything else — completing, editing, deleting a reflection —
/// stays derived from the reflections table by session id. Pure local
/// UserDefaults storage; offline by construction and bounded in size.
public struct ReflectionPromptDismissalStore: @unchecked Sendable {
    public static let storageKey = "today.reflectionDismissedSessionIDs"
    /// Only recent sessions matter for the Today card; the cap keeps the flag
    /// list from growing without bound.
    private let capacity: Int
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard, capacity: Int = 50) {
        self.defaults = defaults
        self.capacity = max(1, capacity)
    }

    public func dismissedSessionIDs() -> Set<ReadingSessionID> {
        guard let raw = defaults.stringArray(forKey: Self.storageKey) else { return [] }
        return Set(raw.compactMap { id in UUID(uuidString: id).map(ReadingSessionID.init(rawValue:)) })
    }

    public func dismiss(_ sessionID: ReadingSessionID) {
        var ids = defaults.stringArray(forKey: Self.storageKey) ?? []
        ids.removeAll { $0 == sessionID.description }
        ids.append(sessionID.description)
        if ids.count > capacity {
            ids.removeFirst(ids.count - capacity)
        }
        defaults.set(ids, forKey: Self.storageKey)
    }
}

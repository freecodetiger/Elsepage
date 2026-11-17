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

/// Sessions dismissed by an older build, back when "这次不写" was a permanent
/// opt-out. Nothing writes here any more: a skip now lasts for one run and the
/// prompt returns on the next launch. The stored ids stay readable so those
/// earlier choices are not quietly re-surfaced. Completing, editing, or
/// deleting a reflection is still derived from the reflections table.
public struct ReflectionPromptDismissalStore: @unchecked Sendable {
    public static let storageKey = "today.reflectionDismissedSessionIDs"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func dismissedSessionIDs() -> Set<ReadingSessionID> {
        guard let raw = defaults.stringArray(forKey: Self.storageKey) else { return [] }
        return Set(raw.compactMap { id in UUID(uuidString: id).map(ReadingSessionID.init(rawValue:)) })
    }
}

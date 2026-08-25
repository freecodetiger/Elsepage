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
    public static func resolve(
        currentBook: Book?,
        sessions: [ReadingSession],
        reflections: [Reflection],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TodayProductState {
        guard let currentBook else { return .noCurrentBook }
        if let session = sessions
            .filter({ SessionEndingSummary(session: $0).shouldOfferReflection })
            .sorted(by: { $0.startedAt > $1.startedAt })
            .first(where: { session in
                !reflections.contains(where: { $0.sessionID == session.id })
            }) {
            return .offerReflection(currentBook, session)
        }
        if reflections.contains(where: { calendar.isDate($0.createdAt, inSameDayAs: now) }) {
            return .reflectionComplete(currentBook)
        }
        return .continueReading(currentBook)
    }
}

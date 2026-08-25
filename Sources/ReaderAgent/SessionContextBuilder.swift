import Foundation
import LibraryCore
import ReaderCore
import ReadingSessionCore
import ReflectionCore

/// The bounded, session-scoped context bundle handed to the Agent prompt.
/// All fields are raw domain values; formatting happens in `ReaderAgentPolicy`.
public struct SessionContext: Hashable, Sendable {
    public let session: ReadingSession?
    public let sessionHighlights: [Highlight]
    public let sessionNotes: [Note]
    public let bookReflections: [Reflection]

    public init(
        session: ReadingSession?,
        sessionHighlights: [Highlight] = [],
        sessionNotes: [Note] = [],
        bookReflections: [Reflection] = []
    ) {
        self.session = session
        self.sessionHighlights = sessionHighlights
        self.sessionNotes = sessionNotes
        self.bookReflections = bookReflections
    }

    public static let empty = SessionContext(session: nil)

    public var hasSessionHighlight: Bool { !sessionHighlights.isEmpty }
    public var hasSessionNote: Bool { !sessionNotes.isEmpty }
    public var hasBookReflections: Bool { !bookReflections.isEmpty }
}

/// Gathers the reading-session range, session-scoped highlights/notes, and this
/// book's prior reflections into a single place so `ReaderAgent.run` stays lean.
public struct SessionContextBuilder: Sendable {
    private let sessions: any ReadingSessionRepository
    private let reading: any ReadingRepository
    private let reflections: any ReflectionRepository

    public init(
        sessions: any ReadingSessionRepository,
        reading: any ReadingRepository,
        reflections: any ReflectionRepository
    ) {
        self.sessions = sessions
        self.reading = reading
        self.reflections = reflections
    }

    public func build(
        bookID: BookID,
        sessionID: ReadingSessionID?,
        excluding reflectionID: ReflectionID
    ) async -> SessionContext {
        let session: ReadingSession?
        if let sessionID {
            session = try? await sessions.session(id: sessionID)
        } else {
            session = nil
        }

        let highlights = (try? await reading.highlights(for: bookID)) ?? []
        let notes = (try? await reading.notes(for: bookID)) ?? []
        let allReflections = (try? await reflections.reflections(for: bookID)) ?? []

        // highlights/notes carry no sessionID foreign key; attribute them to the
        // session by the time window since the session started.
        let sessionHighlights: [Highlight]
        let sessionNotes: [Note]
        if let startedAt = session?.startedAt {
            sessionHighlights = highlights.filter { $0.createdAt >= startedAt }
            sessionNotes = notes.filter { $0.createdAt >= startedAt }
        } else {
            sessionHighlights = []
            sessionNotes = []
        }

        return SessionContext(
            session: session,
            sessionHighlights: sessionHighlights,
            sessionNotes: sessionNotes,
            bookReflections: allReflections.filter { $0.id != reflectionID }
        )
    }
}

import Foundation
import LibraryCore

public enum ThoughtsArchiveFilter: String, CaseIterable, Sendable {
    case all
    case hasAgentResponse
    case hasConnection
}

public struct ThoughtsArchiveMonthSection: Sendable, Identifiable {
    public let month: Date
    public let entries: [ReflectionArchiveEntry]
    public var id: Date { month }
}

public struct ThoughtsArchiveBookSection: Sendable, Identifiable {
    public let book: Book
    public let entries: [ReflectionArchiveEntry]
    public var id: BookID { book.id }
}

/// Deterministic, read-only projections used by the Thoughts archive UI.
public enum ThoughtsArchiveProjection {
    public static func entries(
        _ entries: [ReflectionArchiveEntry],
        matching query: String,
        filter: ThoughtsArchiveFilter
    ) -> [ReflectionArchiveEntry] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            let passesFilter = switch filter {
            case .all: true
            case .hasAgentResponse: entry.derivedAgentResponse != nil
            case .hasConnection: !entry.connections.isEmpty
            }
            guard passesFilter else { return false }
            guard !term.isEmpty else { return true }
            return entry.book.title.localizedCaseInsensitiveContains(term)
                || entry.reflection.displayText.localizedCaseInsensitiveContains(term)
                || entry.reflection.originalText.localizedCaseInsensitiveContains(term)
                || entry.messages.contains { $0.content.localizedCaseInsensitiveContains(term) }
        }
        .sorted { $0.reflection.createdAt > $1.reflection.createdAt }
    }

    public static func monthSections(
        _ entries: [ReflectionArchiveEntry],
        calendar: Calendar = .current
    ) -> [ThoughtsArchiveMonthSection] {
        let grouped = Dictionary(grouping: entries) { entry in
            let components = calendar.dateComponents([.year, .month], from: entry.reflection.createdAt)
            return calendar.date(from: components) ?? entry.reflection.createdAt
        }
        return grouped.map { month, entries in
            ThoughtsArchiveMonthSection(
                month: month,
                entries: entries.sorted { $0.reflection.createdAt > $1.reflection.createdAt }
            )
        }
        .sorted { $0.month > $1.month }
    }

    public static func bookSections(_ entries: [ReflectionArchiveEntry]) -> [ThoughtsArchiveBookSection] {
        Dictionary(grouping: entries, by: { $0.book.id }).compactMap { _, entries in
            guard let book = entries.first?.book else { return nil }
            return ThoughtsArchiveBookSection(
                book: book,
                entries: entries.sorted { $0.reflection.createdAt > $1.reflection.createdAt }
            )
        }
        .sorted {
            ($0.entries.first?.reflection.createdAt ?? .distantPast)
                > ($1.entries.first?.reflection.createdAt ?? .distantPast)
        }
    }
}

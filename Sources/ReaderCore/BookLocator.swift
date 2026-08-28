import Foundation
import LibraryCore

/// Stable reading anchor. `json` is the lossless Readium Locator representation.
public struct BookLocator: Hashable, Codable, Sendable {
    public let json: Data
    public let href: String
    public let progression: Double?
    public let totalProgression: Double?
    public let textBefore: String?
    public let textHighlight: String?
    public let textAfter: String?

    public init(
        json: Data, href: String, progression: Double? = nil,
        totalProgression: Double? = nil, textBefore: String? = nil,
        textHighlight: String? = nil, textAfter: String? = nil
    ) throws {
        guard (try JSONSerialization.jsonObject(with: json)) is [String: Any] else {
            throw BookLocatorError.invalidJSON
        }
        self.json = json
        self.href = href
        self.progression = progression
        self.totalProgression = totalProgression
        self.textBefore = textBefore
        self.textHighlight = textHighlight
        self.textAfter = textAfter
    }

    /// Compares the complete Readium anchor without depending on JSON key order.
    public func identifiesSameAnchor(as other: BookLocator) -> Bool {
        guard let lhs = try? Self.canonicalJSON(json),
              let rhs = try? Self.canonicalJSON(other.json) else { return false }
        return lhs == rhs
    }

    private static func canonicalJSON(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

public enum BookLocatorError: Error { case invalidJSON }

public struct ReadingPosition: Hashable, Codable, Sendable {
    public let bookID: BookID
    public let locator: BookLocator
    public let updatedAt: Date
    public init(bookID: BookID, locator: BookLocator, updatedAt: Date = Date()) {
        self.bookID = bookID
        self.locator = locator
        self.updatedAt = updatedAt
    }
}

public enum HighlightColor: String, Codable, Sendable, CaseIterable { case yellow, green, blue, pink }

public struct Highlight: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let bookID: BookID
    public let locator: BookLocator
    public var color: HighlightColor
    public let createdAt: Date
    public init(id: UUID = UUID(), bookID: BookID, locator: BookLocator, color: HighlightColor = .yellow, createdAt: Date = Date()) {
        self.id = id; self.bookID = bookID; self.locator = locator; self.color = color; self.createdAt = createdAt
    }
}

public extension Collection where Element == Highlight {
    func containsHighlight(at locator: BookLocator) -> Bool {
        contains { $0.locator.identifiesSameAnchor(as: locator) }
    }
}

public struct Note: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let bookID: BookID
    public let highlightID: UUID?
    public let locator: BookLocator
    public var body: String
    public let createdAt: Date
    public var updatedAt: Date
    public init(id: UUID = UUID(), bookID: BookID, highlightID: UUID? = nil, locator: BookLocator, body: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.bookID = bookID; self.highlightID = highlightID; self.locator = locator
        self.body = body; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public protocol ReadingRepository: Sendable {
    func position(for bookID: BookID) async throws -> ReadingPosition?
    func positions(for bookIDs: [BookID]) async throws -> [BookID: ReadingPosition]
    func save(position: ReadingPosition) async throws
    func highlights(for bookID: BookID) async throws -> [Highlight]
    func save(highlight: Highlight) async throws
    func save(highlight: Highlight, note: Note) async throws
    func deleteHighlight(id: UUID) async throws
    func notes(for bookID: BookID) async throws -> [Note]
    func save(note: Note) async throws
    func deleteNote(id: UUID) async throws
    func preferences(for bookID: BookID) async throws -> ReaderPreferences
    func save(preferences: ReaderPreferences, for bookID: BookID) async throws
}

public extension ReadingRepository {
    func positions(for bookIDs: [BookID]) async throws -> [BookID: ReadingPosition] {
        var result: [BookID: ReadingPosition] = [:]
        for bookID in bookIDs {
            if let position = try await position(for: bookID) {
                result[bookID] = position
            }
        }
        return result
    }
}

public enum ReaderTheme: String, Codable, Sendable, CaseIterable { case system, light, dark, sepia }
public enum ReadingMode: String, Codable, Sendable, CaseIterable { case paginated, scroll }

public struct ReaderPreferences: Hashable, Codable, Sendable {
    public var theme: ReaderTheme
    public var fontSize: Double
    public var lineHeight: Double
    public var pageMargins: Double
    public var readingMode: ReadingMode
    public var lastUsedHighlightColor: HighlightColor

    public init(
        theme: ReaderTheme = .system,
        fontSize: Double = 1.05,
        lineHeight: Double = 1.2,
        pageMargins: Double = 1.1,
        readingMode: ReadingMode = .paginated,
        lastUsedHighlightColor: HighlightColor = .yellow
    ) {
        self.theme = theme
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.pageMargins = pageMargins
        self.readingMode = readingMode
        self.lastUsedHighlightColor = lastUsedHighlightColor
    }

    public static let `default` = ReaderPreferences()
}

/// Readium-independent data required to restore persisted highlight decorations.
public struct HighlightDecoration: Hashable, Sendable, Identifiable {
    public let id: String
    public let locator: BookLocator
    public let color: HighlightColor
    public init(highlight: Highlight) {
        id = highlight.id.uuidString.lowercased()
        locator = highlight.locator
        color = highlight.color
    }
}

public struct HighlightRestorationService: Sendable {
    private let repository: any ReadingRepository
    public init(repository: any ReadingRepository) { self.repository = repository }
    public func decorations(for bookID: BookID) async throws -> [HighlightDecoration] {
        try await repository.highlights(for: bookID).map(HighlightDecoration.init)
    }
}

/// Readium-independent search result used by Reader feature state and tests.
public struct ReaderSearchResult: Hashable, Sendable, Identifiable {
    public let id: String
    public let locator: BookLocator
    public let excerpt: String

    public init(locator: BookLocator, excerpt: String) {
        self.locator = locator
        self.excerpt = excerpt
        id = locator.json.base64EncodedString()
    }
}

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
    func save(position: ReadingPosition) async throws
    func highlights(for bookID: BookID) async throws -> [Highlight]
    func save(highlight: Highlight) async throws
    func deleteHighlight(id: UUID) async throws
    func notes(for bookID: BookID) async throws -> [Note]
    func save(note: Note) async throws
    func deleteNote(id: UUID) async throws
}

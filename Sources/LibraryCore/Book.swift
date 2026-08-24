import Foundation

public struct BookID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID() }
    public var description: String { rawValue.uuidString.lowercased() }
}

public struct ContentFingerprint: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue.lowercased() }
}

public struct Book: Hashable, Codable, Sendable, Identifiable {
    public let id: BookID
    public let fingerprint: ContentFingerprint
    public var title: String
    public var author: String?
    public let fileName: String
    public let fileSize: Int64
    public let importedAt: Date
    public var lastOpenedAt: Date?

    public init(
        id: BookID = BookID(), fingerprint: ContentFingerprint, title: String,
        author: String? = nil, fileName: String, fileSize: Int64,
        importedAt: Date = Date(), lastOpenedAt: Date? = nil
    ) {
        self.id = id
        self.fingerprint = fingerprint
        self.title = title
        self.author = author
        self.fileName = fileName
        self.fileSize = fileSize
        self.importedAt = importedAt
        self.lastOpenedAt = lastOpenedAt
    }
}

public struct ImportedBookMetadata: Sendable {
    public var title: String
    public var author: String?
    public init(title: String, author: String? = nil) {
        self.title = title
        self.author = author
    }
}

public enum BookImportResult: Sendable, Equatable {
    case imported(Book)
    case duplicate(Book)
}

public protocol BookRepository: Sendable {
    func allBooks() async throws -> [Book]
    func book(id: BookID) async throws -> Book?
    func book(fingerprint: ContentFingerprint) async throws -> Book?
    func insert(_ book: Book) async throws
    func markOpened(_ id: BookID, at date: Date) async throws
    func delete(_ id: BookID) async throws
}

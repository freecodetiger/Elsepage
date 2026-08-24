import CryptoKit
import Foundation
import LibraryCore

public struct BookFileStore: Sendable {
    public let directory: URL
    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    public func url(for bookID: BookID) -> URL { directory.appendingPathComponent(bookID.description).appendingPathExtension("epub") }
    public func fingerprint(of source: URL) throws -> ContentFingerprint {
        let handle = try FileHandle(forReadingFrom: source); defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hasher.update(data: data) }
        return ContentFingerprint(rawValue: hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }
    public func copy(from source: URL, bookID: BookID) throws -> URL {
        let destination = url(for: bookID)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }
    public func remove(bookID: BookID) { try? FileManager.default.removeItem(at: url(for: bookID)) }
}

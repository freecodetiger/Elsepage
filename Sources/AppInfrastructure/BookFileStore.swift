import CryptoKit
import Foundation
import LibraryCore

public struct StagedBookFile: Hashable, Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
}

public protocol BookFileManaging: Sendable {
    func url(for bookID: BookID) -> URL
    func fingerprint(of source: URL) throws -> ContentFingerprint
    func stageCopy(from source: URL, bookID: BookID) throws -> StagedBookFile
    func promote(_ staged: StagedBookFile, bookID: BookID) throws
    func cleanup(_ staged: StagedBookFile?, bookID: BookID)
}

public struct BookFileStore: BookFileManaging, Sendable {
    public let directory: URL
    private let stagingDirectory: URL
    public init(directory: URL) throws {
        self.directory = directory
        stagingDirectory = directory.appendingPathComponent(".staging", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
    }
    public func url(for bookID: BookID) -> URL { directory.appendingPathComponent(bookID.description).appendingPathExtension("epub") }
    public func fingerprint(of source: URL) throws -> ContentFingerprint {
        let handle = try FileHandle(forReadingFrom: source); defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hasher.update(data: data) }
        return ContentFingerprint(rawValue: hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }
    public func stageCopy(from source: URL, bookID: BookID) throws -> StagedBookFile {
        let staged = StagedBookFile(url: stagingDirectory.appendingPathComponent(bookID.description).appendingPathExtension("epub.partial"))
        try? FileManager.default.removeItem(at: staged.url)
        do {
            try FileManager.default.copyItem(at: source, to: staged.url)
            return staged
        } catch {
            try? FileManager.default.removeItem(at: staged.url)
            throw error
        }
    }
    public func promote(_ staged: StagedBookFile, bookID: BookID) throws {
        try FileManager.default.moveItem(at: staged.url, to: url(for: bookID))
    }
    public func remove(bookID: BookID) { try? FileManager.default.removeItem(at: url(for: bookID)) }
    public func cleanup(_ staged: StagedBookFile?, bookID: BookID) {
        if let staged { try? FileManager.default.removeItem(at: staged.url) }
        remove(bookID: bookID)
    }
}

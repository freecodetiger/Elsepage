import CryptoKit
import Foundation
import LibraryCore

public struct StagedBookFile: Hashable, Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
}

/// A book file moved aside while its database record is being deleted.
/// Keeping it recoverable until the database write succeeds avoids a Book
/// record pointing at a missing EPUB when that write fails.
public struct TrashedBookFile: Hashable, Sendable {
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
    private let trashDirectory: URL
    public init(directory: URL) throws {
        self.directory = directory
        stagingDirectory = directory.appendingPathComponent(".staging", isDirectory: true)
        trashDirectory = directory.appendingPathComponent(".trash", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
        // A completed database deletion may have been interrupted before this
        // best-effort cleanup. These files are no longer user-visible books.
        for file in try FileManager.default.contentsOfDirectory(at: trashDirectory, includingPropertiesForKeys: nil) {
            try? FileManager.default.removeItem(at: file)
        }
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

    public func stageDeletion(bookID: BookID) throws -> TrashedBookFile? {
        let source = url(for: bookID)
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        let trashed = TrashedBookFile(url: trashDirectory.appendingPathComponent(bookID.description).appendingPathExtension("epub"))
        try? FileManager.default.removeItem(at: trashed.url)
        try FileManager.default.moveItem(at: source, to: trashed.url)
        return trashed
    }

    public func restore(_ trashed: TrashedBookFile, for bookID: BookID) throws {
        try FileManager.default.moveItem(at: trashed.url, to: url(for: bookID))
    }

    public func commitDeletion(_ trashed: TrashedBookFile?) {
        guard let trashed else { return }
        try? FileManager.default.removeItem(at: trashed.url)
    }
    public func cleanup(_ staged: StagedBookFile?, bookID: BookID) {
        if let staged { try? FileManager.default.removeItem(at: staged.url) }
        remove(bookID: bookID)
    }
}

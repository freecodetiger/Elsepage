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

    /// Removes every book artifact (EPUBs, staged and trashed leftovers) while
    /// keeping the store's own directory structure — used by 清除所有本地数据 after
    /// the database wipe so orphaned files from interrupted imports cannot
    /// outlive it. The container itself is never deleted.
    public func removeAllBookFiles() {
        let directories = [directory, stagingDirectory, trashDirectory]
        for directory in directories {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            )) ?? []
            for item in contents where item.pathExtension == "epub" || item.pathExtension == "partial" {
                try? FileManager.default.removeItem(at: item)
            }
        }
    }

    /// Repairs an interrupted two-phase deletion. A book still present in the
    /// database gets its EPUB restored; an orphaned trash entry is safe to drop.
    public func reconcilePendingDeletions(existingBookIDs: [BookID]) throws {
        let known = Set(existingBookIDs.map(\.description))
        for trashed in try FileManager.default.contentsOfDirectory(at: trashDirectory, includingPropertiesForKeys: nil) {
            let id = trashed.deletingPathExtension().lastPathComponent
            guard known.contains(id), let uuid = UUID(uuidString: id) else {
                try? FileManager.default.removeItem(at: trashed)
                continue
            }
            let bookID = BookID(rawValue: uuid)
            let destination = url(for: bookID)
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: trashed)
            } else {
                try FileManager.default.moveItem(at: trashed, to: destination)
            }
        }
    }
    public func cleanup(_ staged: StagedBookFile?, bookID: BookID) {
        if let staged { try? FileManager.default.removeItem(at: staged.url) }
        remove(bookID: bookID)
    }
}

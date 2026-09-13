import AVFoundation
import CryptoKit
import Foundation

public struct AudioFileMetadata: Hashable, Sendable {
    public let fileName: String
    public let duration: TimeInterval
    public let byteSize: Int64
    public let format: String
    public let checksum: String

    public init(fileName: String, duration: TimeInterval, byteSize: Int64, format: String, checksum: String) {
        self.fileName = fileName
        self.duration = duration
        self.byteSize = byteSize
        self.format = format
        self.checksum = checksum
    }
}

public struct AudioStorageSummary: Hashable, Sendable {
    public let fileCount: Int
    public let byteSize: Int64

    public init(fileCount: Int, byteSize: Int64) {
        self.fileCount = fileCount
        self.byteSize = byteSize
    }
}

/// Owns every filesystem transition for optional Reflection audio.
///
/// Recording writes into `.drafts`. A successful Reflection submission stages
/// that draft under its database filename, commits it into the audio root, and a
/// failure rolls it back for retry. Deletions move files to `.trash` so database
/// failures can restore them before committing the removal.
public struct AudioFileStore: Sendable {
    public struct StagedPromotion: Hashable, Sendable {
        public let draftURL: URL
        public let stagedURL: URL
        public let finalURL: URL
    }

    public struct StagedDeletion: Hashable, Sendable {
        public let fileName: String
        public let originalURL: URL
        public let trashedURL: URL
    }

    public let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public static func live() -> AudioFileStore {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return AudioFileStore(rootDirectory: documents.appendingPathComponent("Reflections", isDirectory: true))
    }

    public func newDraftURL(fileExtension: String = "m4a") throws -> URL {
        try ensureDirectories()
        let suffix = sanitizedExtension(fileExtension)
        return draftsDirectory
            .appendingPathComponent(UUID().uuidString.lowercased())
            .appendingPathExtension(suffix)
    }

    public func url(for fileName: String) throws -> URL {
        try safeFileURL(named: fileName)
    }

    public func fileExists(named fileName: String) -> Bool {
        (try? safeFileURL(named: fileName))
            .map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    public func discardDraft(at url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    public func stagePromotion(draftURL: URL, finalFileName: String) throws -> StagedPromotion {
        try ensureDirectories()
        let destination = try safeFileURL(named: finalFileName)
        guard FileManager.default.fileExists(atPath: draftURL.path) else {
            throw AudioFileStoreError.missingDraft
        }
        let stagedURL = stagingDirectory.appendingPathComponent(destination.lastPathComponent)
        try? FileManager.default.removeItem(at: stagedURL)
        try FileManager.default.moveItem(at: draftURL, to: stagedURL)
        return StagedPromotion(draftURL: draftURL, stagedURL: stagedURL, finalURL: destination)
    }

    public func commitPromotion(_ promotion: StagedPromotion) throws {
        guard FileManager.default.fileExists(atPath: promotion.stagedURL.path) else {
            throw AudioFileStoreError.missingStagedFile
        }
        try? FileManager.default.removeItem(at: promotion.finalURL)
        try FileManager.default.moveItem(at: promotion.stagedURL, to: promotion.finalURL)
    }

    public func rollbackPromotion(_ promotion: StagedPromotion) {
        guard FileManager.default.fileExists(atPath: promotion.stagedURL.path) else { return }
        try? FileManager.default.removeItem(at: promotion.draftURL)
        try? FileManager.default.moveItem(at: promotion.stagedURL, to: promotion.draftURL)
    }

    public func discardSaved(fileName: String?) {
        guard let fileName, let url = try? safeFileURL(named: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    public func stageAllSavedFiles() throws -> [StagedDeletion] {
        try ensureDirectories()
        let names = try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: []
        )
        .filter { Self.audioExtensions.contains($0.pathExtension.lowercased()) }
        .map(\.lastPathComponent)
        return try stageDeletion(fileNames: names)
    }

    public func stageDeletion(fileNames: [String]) throws -> [StagedDeletion] {
        try ensureDirectories()
        var staged: [StagedDeletion] = []
        for fileName in fileNames {
            let original = try safeFileURL(named: fileName)
            guard FileManager.default.fileExists(atPath: original.path) else { continue }
            let trashed = trashDirectory.appendingPathComponent(original.lastPathComponent)
            try? FileManager.default.removeItem(at: trashed)
            try FileManager.default.moveItem(at: original, to: trashed)
            staged.append(.init(fileName: fileName, originalURL: original, trashedURL: trashed))
        }
        return staged
    }

    public func commitDeletion(_ staged: [StagedDeletion]) {
        for item in staged {
            try? FileManager.default.removeItem(at: item.trashedURL)
        }
    }

    public func restoreDeletion(_ staged: [StagedDeletion]) {
        for item in staged.reversed() {
            guard FileManager.default.fileExists(atPath: item.trashedURL.path) else { continue }
            try? FileManager.default.removeItem(at: item.originalURL)
            try? FileManager.default.moveItem(at: item.trashedURL, to: item.originalURL)
        }
    }

    public func storageSummary() throws -> AudioStorageSummary {
        try ensureDirectories()
        let files = try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: []
        ).filter { Self.audioExtensions.contains($0.pathExtension.lowercased()) }
        let bytes = try files.reduce(into: Int64(0)) { total, url in
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values.fileSize ?? 0)
        }
        return AudioStorageSummary(fileCount: files.count, byteSize: bytes)
    }

    public func metadata(for fileName: String) async throws -> AudioFileMetadata {
        try await metadata(forDraftURL: safeFileURL(named: fileName), fileName: fileName)
    }

    public func metadata(forDraftURL url: URL, fileName: String) async throws -> AudioFileMetadata {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioFileStoreError.missingDraft
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let byteSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw AudioFileStoreError.audioMergeFailed("录音文件为空")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        let checksum = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return AudioFileMetadata(
            fileName: fileName,
            duration: duration,
            byteSize: byteSize,
            format: url.pathExtension.lowercased(),
            checksum: checksum
        )
    }

    /// Combines sequential voice takes into one M4A draft. A single segment is
    /// returned unchanged; only multi-take recordings pay the export cost.
    public func mergeDraftSegments(_ segments: [URL]) async throws -> URL {
        guard let first = segments.first else { throw AudioFileStoreError.missingDraft }
        let firstDuration = try await AVURLAsset(url: first).load(.duration).seconds
        guard firstDuration > 0 else {
            throw AudioFileStoreError.audioMergeFailed("录音文件为空")
        }
        guard segments.count > 1 else { return first }

        let output = try newDraftURL(fileExtension: "m4a")
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AudioFileStoreError.audioMergeFailed("无法创建音频轨道")
        }

        var cursor = CMTime.zero
        for segment in segments {
            let asset = AVURLAsset(url: segment)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first else {
                throw AudioFileStoreError.audioMergeFailed("录音片段没有音频轨道")
            }
            let duration = try await asset.load(.duration)
            guard duration.seconds > 0 else {
                throw AudioFileStoreError.audioMergeFailed("录音片段为空")
            }
            try track.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: source,
                at: cursor
            )
            cursor = CMTimeAdd(cursor, duration)
        }

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioFileStoreError.audioMergeFailed("无法创建音频导出器")
        }
        exporter.outputURL = output
        exporter.outputFileType = .m4a

        await withCheckedContinuation { continuation in
            exporter.exportAsynchronously {
                continuation.resume()
            }
        }
        guard exporter.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw AudioFileStoreError.audioMergeFailed(
                exporter.error?.localizedDescription ?? "音频合并未完成"
            )
        }
        return output
    }

    public func removeAllAudio() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return }
        for item in try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: []
        ) {
            try fileManager.removeItem(at: item)
        }
    }

    /// Reconciles interrupted promotions and draft files after the database is
    /// available. A staged file is committed only when a Reflection references
    /// it; unreferenced staged/final files and all drafts are discarded.
    @discardableResult
    public func recover(referencedFileNames: Set<String>) throws -> Int {
        try ensureDirectories()
        let fileManager = FileManager.default
        var recovered = 0

        for staged in try fileManager.contentsOfDirectory(
            at: stagingDirectory,
            includingPropertiesForKeys: nil,
            options: []
        ) {
            let fileName = staged.lastPathComponent
            if referencedFileNames.contains(fileName) {
                let destination = try safeFileURL(named: fileName)
                try? fileManager.removeItem(at: destination)
                try fileManager.moveItem(at: staged, to: destination)
                recovered += 1
            } else {
                try? fileManager.removeItem(at: staged)
            }
        }

        for trash in try fileManager.contentsOfDirectory(
            at: trashDirectory,
            includingPropertiesForKeys: nil,
            options: []
        ) {
            let fileName = trash.lastPathComponent
            if referencedFileNames.contains(fileName) {
                let destination = try safeFileURL(named: fileName)
                try? fileManager.removeItem(at: destination)
                try fileManager.moveItem(at: trash, to: destination)
                recovered += 1
            } else {
                try? fileManager.removeItem(at: trash)
            }
        }

        for draft in try fileManager.contentsOfDirectory(
            at: draftsDirectory,
            includingPropertiesForKeys: nil,
            options: []
        ) {
            try? fileManager.removeItem(at: draft)
        }

        for file in try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: []
        ) where Self.audioExtensions.contains(file.pathExtension.lowercased()) {
            if !referencedFileNames.contains(file.lastPathComponent) {
                try? fileManager.removeItem(at: file)
            }
        }
        return recovered
    }

    private static let audioExtensions: Set<String> = ["m4a", "caf", "mp3"]

    private var draftsDirectory: URL {
        rootDirectory.appendingPathComponent(".drafts", isDirectory: true)
    }

    private var stagingDirectory: URL {
        rootDirectory.appendingPathComponent(".staging", isDirectory: true)
    }

    private var trashDirectory: URL {
        rootDirectory.appendingPathComponent(".trash", isDirectory: true)
    }

    private func ensureDirectories() throws {
        for directory in [rootDirectory, draftsDirectory, stagingDirectory, trashDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func safeFileURL(named fileName: String) throws -> URL {
        guard !fileName.isEmpty,
              URL(fileURLWithPath: fileName).lastPathComponent == fileName,
              !fileName.hasPrefix(".") else {
            throw AudioFileStoreError.invalidFileName
        }
        try ensureDirectories()
        return rootDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    private func sanitizedExtension(_ value: String) -> String {
        let allowed = value.lowercased().filter { $0.isLetter || $0.isNumber }
        return allowed.isEmpty ? "m4a" : allowed
    }
}

public enum AudioFileStoreError: Error, Equatable, Sendable {
    case invalidFileName
    case missingDraft
    case missingStagedFile
    case audioMergeFailed(String)
}

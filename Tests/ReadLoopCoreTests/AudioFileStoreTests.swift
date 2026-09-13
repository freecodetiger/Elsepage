import AVFoundation
import AppInfrastructure
import Foundation
import Testing

private func makeAudioStore() throws -> (AudioFileStore, URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("readloop-audio-store-\(UUID().uuidString)", isDirectory: true)
    let store = AudioFileStore(rootDirectory: root)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return (store, root)
}

@Test func audioDraftPromotesAndRollsBack() throws {
    let (store, root) = try makeAudioStore()
    defer { try? FileManager.default.removeItem(at: root) }

    let draft = try store.newDraftURL()
    try Data("voice".utf8).write(to: draft)
    let promotion = try store.stagePromotion(draftURL: draft, finalFileName: "reflection.m4a")
    #expect(!FileManager.default.fileExists(atPath: draft.path))

    store.rollbackPromotion(promotion)
    #expect(FileManager.default.fileExists(atPath: draft.path))

    let second = try store.stagePromotion(draftURL: draft, finalFileName: "reflection.m4a")
    try store.commitPromotion(second)
    #expect(store.fileExists(named: "reflection.m4a"))
    #expect(!FileManager.default.fileExists(atPath: second.stagedURL.path))
}

@Test func stageDeletionRestoresAndCommits() throws {
    let (store, root) = try makeAudioStore()
    defer { try? FileManager.default.removeItem(at: root) }

    let draft = try store.newDraftURL()
    try Data("voice".utf8).write(to: draft)
    let promotion = try store.stagePromotion(draftURL: draft, finalFileName: "reflection.m4a")
    try store.commitPromotion(promotion)

    let staged = try store.stageDeletion(fileNames: ["reflection.m4a"])
    #expect(!store.fileExists(named: "reflection.m4a"))
    store.restoreDeletion(staged)
    #expect(store.fileExists(named: "reflection.m4a"))

    let second = try store.stageDeletion(fileNames: ["reflection.m4a"])
    store.commitDeletion(second)
    #expect(!store.fileExists(named: "reflection.m4a"))
}

@Test func recoveryCommitsReferencedStageAndRemovesOrphans() throws {
    let (store, root) = try makeAudioStore()
    defer { try? FileManager.default.removeItem(at: root) }

    let referenced = try store.newDraftURL()
    try Data("keep".utf8).write(to: referenced)
    _ = try store.stagePromotion(draftURL: referenced, finalFileName: "keep.m4a")

    let orphan = try store.newDraftURL()
    try Data("drop".utf8).write(to: orphan)

    let recovered = try store.recover(referencedFileNames: ["keep.m4a"])

    #expect(recovered == 1)
    #expect(store.fileExists(named: "keep.m4a"))
    #expect(!FileManager.default.fileExists(atPath: orphan.path))
}

@Test func unsafeAudioFileNamesAreRejected() throws {
    let (store, root) = try makeAudioStore()
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(throws: AudioFileStoreError.invalidFileName) {
        _ = try store.url(for: "../outside.m4a")
    }
}


private func writeTone(to url: URL, seconds: Double) throws {
    let format = try #require(AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 44_100,
        channels: 1,
        interleaved: false
    ))
    let frameCount = AVAudioFrameCount(44_100 * seconds)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
    buffer.frameLength = frameCount
    let channel = try #require(buffer.floatChannelData?[0])
    for index in 0..<Int(frameCount) {
        channel[index] = sin(Float(index) * 0.01) * 0.1
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
}

@Test func multipleAudioDraftsMergeIntoOnePlayableFile() async throws {
    let (store, root) = try makeAudioStore()
    defer { try? FileManager.default.removeItem(at: root) }

    let first = try store.newDraftURL(fileExtension: "caf")
    let second = try store.newDraftURL(fileExtension: "caf")
    try writeTone(to: first, seconds: 0.2)
    try writeTone(to: second, seconds: 0.3)

    let merged = try await store.mergeDraftSegments([first, second])
    let duration = try await AVURLAsset(url: merged).load(.duration).seconds

    #expect(duration > 0.45)
    #expect(merged.pathExtension == "m4a")
}

@Test func recoveryRestoresReferencedTrashAndDropsUnreferencedTrash() throws {
    let (store, root) = try makeAudioStore()
    defer { try? FileManager.default.removeItem(at: root) }

    func writeSaved(_ name: String) throws {
        let draft = try store.newDraftURL()
        try Data(name.utf8).write(to: draft)
        let promotion = try store.stagePromotion(draftURL: draft, finalFileName: name)
        try store.commitPromotion(promotion)
    }

    try writeSaved("keep.m4a")
    try writeSaved("drop.m4a")
    _ = try store.stageDeletion(fileNames: ["keep.m4a", "drop.m4a"])

    let recovered = try store.recover(referencedFileNames: ["keep.m4a"])

    #expect(recovered == 1)
    #expect(store.fileExists(named: "keep.m4a"))
    #expect(!store.fileExists(named: "drop.m4a"))
}

@Test func allSavedFilesIncludesLegacyAudioExtensions() throws {
    let (store, root) = try makeAudioStore()
    defer { try? FileManager.default.removeItem(at: root) }

    for name in ["new.m4a", "legacy.caf", "older.mp3"] {
        let draft = try store.newDraftURL()
        try Data(name.utf8).write(to: draft)
        let promotion = try store.stagePromotion(draftURL: draft, finalFileName: name)
        try store.commitPromotion(promotion)
    }

    let staged = try store.stageAllSavedFiles()
    #expect(Set(staged.map(\.fileName)) == ["new.m4a", "legacy.caf", "older.mp3"])
}

import AppInfrastructure
import Foundation
import LibraryCore
import Testing

@Test func realEPUBFingerprintAndDuplicateImportAreStable() async throws {
    let root = try TestFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let renamed = root.appendingPathComponent("different-name.epub")
    try FileManager.default.copyItem(at: TestFixtures.minimalEPUB, to: renamed)
    let repository = InMemoryBookRepository()
    let store = try BookFileStore(directory: root.appendingPathComponent("Books"))
    let importer = BookImporter(repository: repository, files: store)

    let first = try await importer.importEPUB(at: TestFixtures.minimalEPUB, metadata: .init(title: "ReadLoop Foundation Fixture", author: "ReadLoop Contributors"))
    let second = try await importer.importEPUB(at: renamed)
    let third = try await importer.importEPUB(at: TestFixtures.minimalEPUB)
    guard case .imported(let imported) = first,
          case .duplicate(let duplicate) = second,
          case .duplicate(let repeated) = third else {
        Issue.record("Expected one import followed by idempotent duplicates"); return
    }
    #expect(imported.id == duplicate.id)
    #expect(imported.id == repeated.id)
    #expect(await repository.count == 1)
    #expect(FileManager.default.fileExists(atPath: store.url(for: imported.id).path))
}

@Test func unsupportedAndCorruptedInputsAreRejectedWithoutArtifacts() async throws {
    let root = try TestFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = InMemoryBookRepository()
    let store = try BookFileStore(directory: root.appendingPathComponent("Books"))
    let importer = BookImporter(repository: repository, files: store)
    let text = root.appendingPathComponent("plain.txt")
    try Data("not an epub".utf8).write(to: text)
    await #expect(throws: BookImportError.unsupportedFormat) { try await importer.importEPUB(at: text) }

    let corrupted = root.appendingPathComponent("corrupted.epub")
    let real = try Data(contentsOf: TestFixtures.minimalEPUB)
    try real.prefix(80).write(to: corrupted)
    await #expect(throws: BookImportError.invalidEPUB) { try await importer.importEPUB(at: corrupted) }
    #expect(await repository.count == 0)
    #expect(try FileManager.default.contentsOfDirectory(at: store.directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "epub" }.isEmpty)
}

@Test(arguments: [FileFailure.stage, .promote])
func fileFailureLeavesNoBookOrPermanentFile(failure: FileFailure) async throws {
    let root = try TestFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = InMemoryBookRepository()
    let files = FaultingBookFiles(root: root, failure: failure)
    let importer = BookImporter(repository: repository, files: files)
    await #expect(throws: (any Error).self) { try await importer.importEPUB(at: TestFixtures.minimalEPUB) }
    #expect(await repository.count == 0)
    #expect(files.artifactPaths.isEmpty)
}

@Test func databaseFailureCompensatesPromotedFileAndBookRecord() async throws {
    let root = try TestFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = InMemoryBookRepository(failInsert: true)
    let files = FaultingBookFiles(root: root)
    let importer = BookImporter(repository: repository, files: files)
    await #expect(throws: (any Error).self) { try await importer.importEPUB(at: TestFixtures.minimalEPUB) }
    #expect(await repository.count == 0)
    #expect(files.artifactPaths.isEmpty)
}

@Test func databaseFailureRemovesRealPromotedAndStagedFiles() async throws {
    let root = try TestFixtures.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = InMemoryBookRepository(failInsert: true)
    let store = try BookFileStore(directory: root.appendingPathComponent("Books"))
    let importer = BookImporter(repository: repository, files: store)
    await #expect(throws: (any Error).self) { try await importer.importEPUB(at: TestFixtures.minimalEPUB) }
    let permanent = try FileManager.default.contentsOfDirectory(at: store.directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "epub" }
    let staging = store.directory.appendingPathComponent(".staging", isDirectory: true)
    #expect(permanent.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil).isEmpty)
    #expect(await repository.count == 0)
}

private enum FixtureFailure: Error { case injected }
enum FileFailure: Sendable, Equatable { case stage, promote }

private final class FaultingBookFiles: BookFileManaging, @unchecked Sendable {
    private let root: URL
    private let failure: FileFailure?
    private let lock = NSLock()
    private var artifacts: Set<String> = []
    init(root: URL, failure: FileFailure? = nil) { self.root = root; self.failure = failure }
    var artifactPaths: Set<String> { lock.withLock { artifacts } }
    func url(for bookID: BookID) -> URL { root.appendingPathComponent("\(bookID).epub") }
    func fingerprint(of source: URL) throws -> ContentFingerprint { .init(rawValue: "fixture-fingerprint") }
    func stageCopy(from source: URL, bookID: BookID) throws -> StagedBookFile {
        let staged = StagedBookFile(url: root.appendingPathComponent("\(bookID).partial"))
        if failure == .stage { throw FixtureFailure.injected }
        lock.withLock { _ = artifacts.insert(staged.url.path) }
        return staged
    }
    func promote(_ staged: StagedBookFile, bookID: BookID) throws {
        lock.withLock {
            artifacts.remove(staged.url.path)
            _ = artifacts.insert(url(for: bookID).path)
        }
        if failure == .promote { throw FixtureFailure.injected }
    }
    func cleanup(_ staged: StagedBookFile?, bookID: BookID) {
        lock.withLock {
            if let staged { artifacts.remove(staged.url.path) }
            artifacts.remove(url(for: bookID).path)
        }
    }
}

private actor InMemoryBookRepository: BookRepository {
    private var books: [BookID: Book] = [:]
    private let failInsert: Bool
    init(failInsert: Bool = false) { self.failInsert = failInsert }
    var count: Int { books.count }
    func allBooks() -> [Book] { Array(books.values) }
    func book(id: BookID) -> Book? { books[id] }
    func book(fingerprint: ContentFingerprint) -> Book? { books.values.first { $0.fingerprint == fingerprint } }
    func insert(_ book: Book) throws { if failInsert { throw FixtureFailure.injected }; books[book.id] = book }
    func markOpened(_ id: BookID, at date: Date) {}
    func delete(_ id: BookID) { books[id] = nil }
}

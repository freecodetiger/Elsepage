import Foundation
import LibraryCore

public actor BookImporter {
    private let repository: any BookRepository
    private let files: any BookFileManaging
    private let validator: EPUBContainerValidator
    public init(repository: any BookRepository, files: any BookFileManaging, validator: EPUBContainerValidator = .init()) {
        self.repository = repository; self.files = files; self.validator = validator
    }

    public func importEPUB(at source: URL, metadata: ImportedBookMetadata? = nil) async throws -> BookImportResult {
        try validator.validate(source)
        let fingerprint = try files.fingerprint(of: source)
        if let existing = try await repository.book(fingerprint: fingerprint) { return .duplicate(existing) }
        let id = BookID()
        let values = try source.resourceValues(forKeys: [.fileSizeKey])
        let fallbackTitle = source.deletingPathExtension().lastPathComponent
        let book = Book(id: id, fingerprint: fingerprint, title: metadata?.title ?? fallbackTitle, author: metadata?.author, fileName: "\(id.description).epub", fileSize: Int64(values.fileSize ?? 0))
        var staged: StagedBookFile?
        do {
            staged = try files.stageCopy(from: source, bookID: id)
            try files.promote(staged!, bookID: id)
            try await repository.insert(book)
            return .imported(book)
        } catch {
            files.cleanup(staged, bookID: id)
            if let existing = try? await repository.book(fingerprint: fingerprint) { return .duplicate(existing) }
            throw error
        }
    }
}
public enum BookImportError: Error, Equatable { case unsupportedFormat, unreadableFile, invalidEPUB }

public struct EPUBContainerValidator: Sendable {
    public init() {}
    public func validate(_ source: URL) throws {
        guard source.pathExtension.lowercased() == "epub" else { throw BookImportError.unsupportedFormat }
        guard FileManager.default.isReadableFile(atPath: source.path) else { throw BookImportError.unreadableFile }
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        let localHeader = Data([0x50, 0x4b, 0x03, 0x04])
        let endOfCentralDirectory = Data([0x50, 0x4b, 0x05, 0x06])
        guard data.starts(with: localHeader),
              data.range(of: endOfCentralDirectory, options: .backwards) != nil,
              data.prefix(512).range(of: Data("mimetype".utf8)) != nil,
              data.prefix(1024).range(of: Data("application/epub+zip".utf8)) != nil
        else { throw BookImportError.invalidEPUB }
    }
}

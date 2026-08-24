import Foundation
import LibraryCore

public actor BookImporter {
    private let repository: any BookRepository
    private let files: BookFileStore
    public init(repository: any BookRepository, files: BookFileStore) { self.repository = repository; self.files = files }

    public func importEPUB(at source: URL, metadata: ImportedBookMetadata? = nil) async throws -> BookImportResult {
        guard source.pathExtension.lowercased() == "epub" else { throw BookImportError.unsupportedFormat }
        guard FileManager.default.isReadableFile(atPath: source.path) else { throw BookImportError.unreadableFile }
        let header = try Data(contentsOf: source, options: .mappedIfSafe).prefix(64 * 1024)
        guard header.starts(with: [0x50, 0x4b]),
              String(decoding: header, as: UTF8.self).contains("application/epub+zip")
        else { throw BookImportError.invalidEPUB }
        let fingerprint = try files.fingerprint(of: source)
        if let existing = try await repository.book(fingerprint: fingerprint) { return .duplicate(existing) }
        let id = BookID()
        let values = try source.resourceValues(forKeys: [.fileSizeKey])
        let fallbackTitle = source.deletingPathExtension().lastPathComponent
        let book = Book(id: id, fingerprint: fingerprint, title: metadata?.title ?? fallbackTitle, author: metadata?.author, fileName: "\(id.description).epub", fileSize: Int64(values.fileSize ?? 0))
        do {
            _ = try files.copy(from: source, bookID: id)
            try await repository.insert(book)
            return .imported(book)
        } catch {
            files.remove(bookID: id)
            if let existing = try? await repository.book(fingerprint: fingerprint) { return .duplicate(existing) }
            throw error
        }
    }
}
public enum BookImportError: Error { case unsupportedFormat, unreadableFile, invalidEPUB }

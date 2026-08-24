import Foundation
import LibraryCore

@MainActor final class ReadiumMetadataReader {
    private let readium: ReadiumServices
    init(readium: ReadiumServices) { self.readium = readium }

    func metadata(at url: URL) async throws -> ImportedBookMetadata {
        let publication = try await readium.open(url, allowUserInteraction: false)
        guard !publication.isRestricted else { throw ReadiumMetadataError.drmProtected }
        return ImportedBookMetadata(
            title: publication.metadata.title ?? url.deletingPathExtension().lastPathComponent,
            author: publication.metadata.authors.first?.name
        )
    }
}

enum ReadiumMetadataError: Error { case drmProtected }

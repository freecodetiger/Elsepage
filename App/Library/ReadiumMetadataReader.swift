import Foundation
import LibraryCore
@preconcurrency import ReadiumShared
import UIKit

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

    /// Uses Readium's publication service instead of parsing the EPUB archive in
    /// the UI layer. A missing cover is a valid EPUB condition and falls back to
    /// the library's generated cover treatment.
    func cover(at url: URL, fitting size: CGSize) async throws -> UIImage? {
        let publication = try await readium.open(url, allowUserInteraction: false)
        guard !publication.isRestricted else { throw ReadiumMetadataError.drmProtected }
        switch await publication.coverFitting(maxSize: size) {
        case .success(let image): return image
        case .failure(let error): throw error
        }
    }
}

enum ReadiumMetadataError: Error { case drmProtected }

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
    ///
    /// Deliberately not `coverFitting(maxSize:)`: that helper centres the artwork
    /// inside `maxSize` with `AVMakeRect` and then renders *from that centred
    /// rect* into a canvas only as tall as the artwork. The canvas is therefore
    /// offset by the centring gap, so a cover whose aspect differs from the
    /// requested box comes back with a transparent band across the top and its
    /// bottom edge cut off — visible as a washed-out stripe on the shelf.
    func cover(at url: URL, fitting size: CGSize) async throws -> UIImage? {
        let publication = try await readium.open(url, allowUserInteraction: false)
        guard !publication.isRestricted else { throw ReadiumMetadataError.drmProtected }
        switch await publication.cover() {
        case .success(let image): return image.flatMap { scaled($0, toFit: size) }
        case .failure(let error): throw error
        }
    }

    /// Aspect-preserving downscale to fit `maxSize`; never enlarges. `opaque` is
    /// deliberate — with an alpha channel an uncovered region would show through
    /// as a faint band instead of being impossible by construction.
    private func scaled(_ image: UIImage, toFit maxSize: CGSize) -> UIImage {
        let factor = min(maxSize.width / image.size.width, maxSize.height / image.size.height)
        guard factor < 1 else { return image }
        let target = CGSize(width: (image.size.width * factor).rounded(),
                            height: (image.size.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

enum ReadiumMetadataError: Error { case drmProtected }

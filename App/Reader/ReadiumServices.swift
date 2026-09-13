import Foundation
@preconcurrency import ReadiumAdapterGCDWebServer
@preconcurrency import ReadiumShared
@preconcurrency import ReadiumStreamer

@MainActor
final class ReadiumServices {
    private struct FileSignature: Hashable {
        let path: String
        let size: Int64
        let modificationTime: TimeInterval
    }

    private struct PublicationCacheKey: Hashable {
        let file: FileSignature
        let allowUserInteraction: Bool
    }

    private struct PublicationCacheEntry {
        let publication: Publication
        var lastUsed: UInt64
    }

    private let publicationCacheCapacity = 4
    private var publicationCache: [PublicationCacheKey: PublicationCacheEntry] = [:]
    private var publicationOpeningTasks: [PublicationCacheKey: Task<Publication, Error>] = [:]
    private var publicationCacheClock: UInt64 = 0

    let httpClient: HTTPClient
    let assetRetriever: AssetRetriever
    let publicationOpener: PublicationOpener
    let httpServer: HTTPServer

    init() {
        let httpClient = DefaultHTTPClient()
        let assetRetriever = AssetRetriever(httpClient: httpClient)
        self.httpClient = httpClient
        self.assetRetriever = assetRetriever
        publicationOpener = PublicationOpener(
            parser: DefaultPublicationParser(
                httpClient: httpClient,
                assetRetriever: assetRetriever,
                pdfFactory: DefaultPDFDocumentFactory()
            )
        )
        httpServer = GCDHTTPServer(assetRetriever: assetRetriever)
    }

    func open(_ url: URL, allowUserInteraction: Bool) async throws -> Publication {
        guard let key = cacheKey(for: url, allowUserInteraction: allowUserInteraction) else {
            return try await openUncached(url, allowUserInteraction: allowUserInteraction)
        }
        if let cached = publicationCache[key] {
            publicationCacheClock &+= 1
            publicationCache[key]?.lastUsed = publicationCacheClock
            Perf.shared.event("reader.publicationCache.hit interaction=\(allowUserInteraction)")
            return cached.publication
        }
        if let opening = publicationOpeningTasks[key] {
            let publication = try await opening.value
            publicationCacheClock &+= 1
            publicationCache[key]?.lastUsed = publicationCacheClock
            return publication
        }

        let assetRetriever = self.assetRetriever
        let publicationOpener = self.publicationOpener
        let opening = Task {
            let fileURL = FileURL(url: url)!
            let asset = try await assetRetriever.retrieve(url: fileURL).get()
            return try await publicationOpener.open(asset: asset, allowUserInteraction: allowUserInteraction).get()
        }
        publicationOpeningTasks[key] = opening
        do {
            let publication = try await opening.value
            publicationOpeningTasks[key] = nil
            store(publication, for: key, interaction: allowUserInteraction)
            return publication
        } catch {
            publicationOpeningTasks[key] = nil
            throw error
        }
    }

    /// Starts parsing without delaying the ReaderModel preparation gate. A
    /// later `open` call joins the same in-flight task instead of parsing twice.
    func preload(_ url: URL, allowUserInteraction: Bool) {
        guard cacheKey(for: url, allowUserInteraction: allowUserInteraction) != nil else { return }
        Perf.shared.event("reader.publicationCache.preload interaction=\(allowUserInteraction)")
        Task { [weak self] in
            _ = try? await self?.open(url, allowUserInteraction: allowUserInteraction)
        }
    }

    /// Drops all cached parses for a file that is being deleted or replaced.
    func invalidate(_ url: URL) {
        guard let path = standardizedPath(for: url) else { return }
        publicationCache = publicationCache.filter { $0.key.file.path != path }
        let openingKeys = publicationOpeningTasks.keys.filter { $0.file.path == path }
        for key in openingKeys {
            publicationOpeningTasks[key]?.cancel()
            publicationOpeningTasks.removeValue(forKey: key)
        }
    }

    private func openUncached(_ url: URL, allowUserInteraction: Bool) async throws -> Publication {
        let fileURL = FileURL(url: url)!
        let asset = try await assetRetriever.retrieve(url: fileURL).get()
        return try await publicationOpener.open(asset: asset, allowUserInteraction: allowUserInteraction).get()
    }

    private func store(_ publication: Publication, for key: PublicationCacheKey, interaction: Bool) {
        publicationCacheClock &+= 1
        publicationCache[key] = .init(publication: publication, lastUsed: publicationCacheClock)
        Perf.shared.event("reader.publicationCache.store interaction=\(interaction)")
        while publicationCache.count > publicationCacheCapacity,
              let leastRecentlyUsed = publicationCache.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key {
            publicationCache.removeValue(forKey: leastRecentlyUsed)
        }
    }

    private func cacheKey(for url: URL, allowUserInteraction: Bool) -> PublicationCacheKey? {
        guard let path = standardizedPath(for: url),
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              let modificationDate = attributes[.modificationDate] as? Date else {
            return nil
        }
        return .init(
            file: .init(path: path, size: size, modificationTime: modificationDate.timeIntervalSinceReferenceDate),
            allowUserInteraction: allowUserInteraction
        )
    }

    private func standardizedPath(for url: URL) -> String? {
        guard url.isFileURL else { return nil }
        return url.standardizedFileURL.path
    }
}

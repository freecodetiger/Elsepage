import Foundation
@preconcurrency import ReadiumAdapterGCDWebServer
@preconcurrency import ReadiumShared
@preconcurrency import ReadiumStreamer

@MainActor
final class ReadiumServices {
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
        let fileURL = FileURL(url: url)!
        let asset = try await assetRetriever.retrieve(url: fileURL).get()
        return try await publicationOpener.open(asset: asset, allowUserInteraction: allowUserInteraction).get()
    }
}

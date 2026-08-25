import AppInfrastructure
import Foundation
import LibraryCore
import ReaderCore
import RetrievalCore
@preconcurrency import ReadiumShared

/// The only Readium-facing adapter in local retrieval. RetrievalCore never
/// imports Readium and persists the complete Locator JSON produced here.
@MainActor
final class ReadiumBookContentExtractor: BookContentExtractor {
    private let bookID: BookID
    private let publication: Publication

    init(bookID: BookID, publication: Publication) {
        self.bookID = bookID; self.publication = publication
    }

    func blocks(for bookID: BookID, startingAtResource start: Int) async throws -> AsyncThrowingStream<BookTextBlock, Error> {
        guard bookID == self.bookID else { return AsyncThrowingStream(BookTextBlock.self) { $0.finish() } }
        let readingOrder = publication.manifest.readingOrder
        let resourceOrdinals = Dictionary(uniqueKeysWithValues: readingOrder.enumerated().map { ($0.element.href, $0.offset) })
        let chapterTitles = Self.chapterTitles(publication.manifest.tableOfContents)
        guard let content = publication.content() else { return AsyncThrowingStream(BookTextBlock.self) { $0.finish() } }
        return AsyncThrowingStream(BookTextBlock.self, bufferingPolicy: .unbounded) { continuation in
            let task = Task { @MainActor in
                do {
                    var ordinals: [String: Int] = [:]
                    var sections: [String: (id: String, title: String)] = [:]
                    let iterator = content.iterator()
                    while let element = try await iterator.next() {
                        try Task.checkCancellation()
                        guard let textual = element as? TextualContentElement,
                              let text = textual.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { continue }
                        let href = element.locator.href.string
                        guard let resourceOrdinal = resourceOrdinals[href], resourceOrdinal >= start else { continue }
                        let ordinal = ordinals[href, default: 0]; ordinals[href] = ordinal + 1
                        if let textElement = element as? TextContentElement,
                           case .heading = textElement.role {
                            sections[href] = ("\(href)#heading-\(ordinal)", text)
                        }
                        let locators: [Locator]
                        if let textElement = element as? TextContentElement, !textElement.segments.isEmpty {
                            locators = [textElement.segments.first!.locator, textElement.segments.last!.locator]
                        } else { locators = [element.locator, element.locator] }
                        continuation.yield(BookTextBlock(
                            id: .init(rawValue: "v1|\(bookID)|\(resourceOrdinal)|\(ordinal)"), bookID: bookID,
                            resourceHref: href, chapterID: href, chapterTitle: chapterTitles[href],
                            sectionID: sections[href]?.id, sectionTitle: sections[href]?.title,
                            resourceOrdinal: resourceOrdinal, ordinal: ordinal, text: text,
                            startLocator: try Self.anchor(locators[0]), endLocator: try Self.anchor(locators[1])))
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func chapterTitles(_ links: [Link]) -> [String: String] {
        links.reduce(into: [:]) { result, link in
            if let title = link.title { result[link.href] = title }
            result.merge(chapterTitles(link.children)) { current, _ in current }
        }
    }

    private static func anchor(_ locator: Locator) throws -> BookLocator {
        try BookLocator(json: JSONSerialization.data(withJSONObject: locator.json), href: locator.href.string,
            progression: locator.locations.progression, totalProgression: locator.locations.totalProgression,
            textBefore: locator.text.before, textHighlight: locator.text.highlight, textAfter: locator.text.after)
    }
}

/// In-memory task ownership plus persistent job checkpoints. Import calls only
/// enqueue; opening the EPUB is never delayed by indexing.
@MainActor
final class BookIndexCoordinator {
    private let repository: any BookIndexRepository
    private let readium: ReadiumServices
    private let files: BookFileStore
    private var tasks: [BookID: Task<Void, Never>] = [:]

    init(repository: any BookIndexRepository, readium: ReadiumServices, files: BookFileStore) {
        self.repository = repository; self.readium = readium; self.files = files
    }

    func enqueue(_ book: Book) {
        guard tasks[book.id] == nil else { return }
        tasks[book.id] = Task { [weak self] in
            guard let self else { return }
            defer { tasks[book.id] = nil }
            do {
                let publication = try await readium.open(files.url(for: book.id), allowUserInteraction: false)
                let extractor = ReadiumBookContentExtractor(bookID: book.id, publication: publication)
                try await BookIndexPipeline(extractor: extractor, repository: repository).index(bookID: book.id)
            } catch is CancellationError { return }
            catch { /* Persistent BookIndexJob contains the diagnostic and retry cursor. */ }
        }
    }

    func resume(_ books: [Book]) async {
        for book in books {
            let state = try? await repository.job(for: book.id, version: BookIndexPipeline.currentVersion)?.state
            if state != .ready && state != .lexicalReady { enqueue(book) }
        }
    }
}

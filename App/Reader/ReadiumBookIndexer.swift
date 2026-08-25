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
    /// Resolves the configured embedding provider at run time so enabling,
    /// disabling, or switching the embedding model in Settings takes effect on
    /// the next enqueue/resume without rebuilding the coordinator.
    private let embeddings: (@Sendable () async -> (any EmbeddingProvider)?)?
    private var tasks: [BookID: Task<Void, Never>] = [:]

    init(
        repository: any BookIndexRepository,
        readium: ReadiumServices,
        files: BookFileStore,
        embeddings: (@Sendable () async -> (any EmbeddingProvider)?)? = nil
    ) {
        self.repository = repository; self.readium = readium; self.files = files; self.embeddings = embeddings
    }

    func enqueue(_ book: Book) {
        enqueue(bookID: book.id, forcingEmbed: false)
    }

    func resume(_ books: [Book]) async {
        let embeddingModel = await embeddings?()?.modelIdentifier
        for book in books {
            let job = try? await repository.job(for: book.id, version: BookIndexPipeline.currentVersion)
            if action(for: job, embeddingModel: embeddingModel) != .skip { enqueue(bookID: book.id, forcingEmbed: false) }
        }
    }

    /// Force a semantic re-embed of an already-indexed book, ignoring the
    /// "already embedded with this model" skip (used by the RAG management page).
    func reembed(bookID: BookID) {
        enqueue(bookID: bookID, forcingEmbed: true)
    }

    /// Full rebuild: clear the persisted index for the current version, then
    /// re-enqueue from scratch (re-extract, re-chunk, re-embed).
    func reindex(bookID: BookID) async {
        try? await repository.deleteIndex(for: bookID, version: BookIndexPipeline.currentVersion)
        enqueue(bookID: bookID, forcingEmbed: false)
    }

    /// Cancels all in-flight indexing tasks (e.g. when every book is deleted).
    /// The DB-side `bookIndexJobs`/`bookChunks` rows are cleared by the FK cascade.
    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    private func enqueue(bookID: BookID, forcingEmbed: Bool) {
        guard tasks[bookID] == nil else { return }
        tasks[bookID] = Task { [weak self] in
            guard let self else { return }
            defer { tasks[bookID] = nil }
            do {
                if forcingEmbed {
                    try await BookIndexPipeline(repository: repository, embeddings: embeddings).embed(bookID: bookID, force: true)
                    return
                }
                let job = try? await repository.job(for: bookID, version: BookIndexPipeline.currentVersion)
                let embeddingModel = await embeddings?()?.modelIdentifier
                switch action(for: job, embeddingModel: embeddingModel) {
                case .skip:
                    return
                case .embed:
                    try await BookIndexPipeline(repository: repository, embeddings: embeddings).embed(bookID: bookID)
                case .index:
                    let publication = try await readium.open(files.url(for: bookID), allowUserInteraction: false)
                    let extractor = ReadiumBookContentExtractor(bookID: bookID, publication: publication)
                    try await BookIndexPipeline(extractor: extractor, repository: repository, embeddings: embeddings).index(bookID: bookID)
                }
            } catch is CancellationError { return }
            catch { /* Persistent BookIndexJob contains the diagnostic and retry cursor. */ }
        }
    }

    private enum Action { case skip, embed, index }

    private func action(for job: BookIndexJob?, embeddingModel: String?) -> Action {
        guard let job else { return .index }
        switch job.state {
        case .pending, .extracting, .failed:
            return .index
        case .lexicalReady, .embedding:
            // Lexical is done; only embed — a no-op if semantic indexing is disabled.
            return embeddingModel == nil ? .skip : .embed
        case .ready:
            if let embeddingModel, job.embeddingModel != embeddingModel { return .embed }
            return .skip
        }
    }
}

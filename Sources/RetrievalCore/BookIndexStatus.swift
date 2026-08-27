import Foundation
import LibraryCore

/// Per-book RAG status for the management page: current index state, lexical
/// progress (resources processed), semantic progress (chunks embedded for the
/// current model), and the persisted last error. All derived from the job row
/// plus table counts — nothing extra is stored for reporting.
public struct BookIndexStatus: Hashable, Sendable, Identifiable {
    public let bookID: BookID
    public let title: String
    public let state: BookIndexState
    public let nextResourceOrdinal: Int
    public let totalResources: Int
    public let embeddedCount: Int
    public let totalChunks: Int
    public let embeddingModel: String?
    public let lastError: String?

    public var id: BookID { bookID }

    public var lexicalFraction: Double {
        totalResources > 0 ? Double(min(nextResourceOrdinal, totalResources)) / Double(totalResources) : 0
    }

    public var semanticFraction: Double {
        totalChunks > 0 ? Double(min(embeddedCount, totalChunks)) / Double(totalChunks) : 0
    }
}

public struct BookIndexStatusService: Sendable {
    private let books: any BookRepository
    private let repository: any BookIndexRepository
    /// Resolves the currently configured embedding model (nil when disabled) so
    /// progress counts only vectors for the model actually in use.
    private let currentEmbeddingModel: @Sendable () async -> String?

    public init(
        books: any BookRepository,
        repository: any BookIndexRepository,
        currentEmbeddingModel: @escaping @Sendable () async -> String?
    ) {
        self.books = books
        self.repository = repository
        self.currentEmbeddingModel = currentEmbeddingModel
    }

    public func status() async throws -> [BookIndexStatus] {
        let allBooks = try await books.allBooks()
        let embeddingModel = await currentEmbeddingModel()
        var statuses: [BookIndexStatus] = []
        statuses.reserveCapacity(allBooks.count)
        for book in allBooks {
            let job = try? await repository.job(for: book.id, version: BookIndexPipeline.currentVersion)
            // Progress counts the retrieval units (children): parents are the
            // context/evidence unit and are never embedded, so counting them too
            // would make semanticFraction impossible to reach 1.0.
            let children = (try? await repository.chunks(for: book.id, version: BookIndexPipeline.currentVersion))?
                .filter { $0.role == .child } ?? []
            let totalChunks = children.count
            let embeddedCount: Int
            if let embeddingModel, !children.isEmpty {
                let stored = (try? await repository.embeddings(bookID: book.id, model: embeddingModel)) ?? [:]
                embeddedCount = stored.count
            } else {
                embeddedCount = 0
            }
            let totalResources = Set(children.map(\.resourceOrdinal)).count
            statuses.append(BookIndexStatus(
                bookID: book.id,
                title: book.title,
                state: job?.state ?? .pending,
                nextResourceOrdinal: job?.nextResourceOrdinal ?? 0,
                totalResources: totalResources,
                embeddedCount: embeddedCount,
                totalChunks: totalChunks,
                embeddingModel: job?.embeddingModel,
                lastError: job?.lastError
            ))
        }
        return statuses.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

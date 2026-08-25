import Foundation
import LibraryCore
import Observation
import RetrievalCore

@MainActor @Observable
final class RAGManagementModel {
    private let service: BookIndexStatusService
    private let coordinator: BookIndexCoordinator

    private(set) var statuses: [BookIndexStatus] = []
    private(set) var isLoading = false
    var errorMessage: String?

    init(service: BookIndexStatusService, coordinator: BookIndexCoordinator) {
        self.service = service
        self.coordinator = coordinator
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            statuses = try await service.status()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Force a semantic re-embed of one book (enqueued, non-blocking).
    func reembed(_ bookID: BookID) {
        coordinator.reembed(bookID: bookID)
    }

    /// Full rebuild of one book's index, then refresh.
    func reindex(_ bookID: BookID) async {
        await coordinator.reindex(bookID: bookID)
        await reload()
    }
}

import Foundation
import LibraryCore
import Observation
import ReflectionCore

/// Read-only presentation state for the user's local reflection archive.
/// It intentionally does not infer a profile, create memory, or call a provider.
@MainActor @Observable
final class ThoughtsModel {
    private let archive: ReflectionArchiveService

    private(set) var entries: [ReflectionArchiveEntry] = []
    private(set) var isLoading = false
    var errorMessage: String?

    init(books: any BookRepository, reflections: any ReflectionRepository) {
        archive = ReflectionArchiveService(books: books, reflections: reflections)
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await archive.recentEntries()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

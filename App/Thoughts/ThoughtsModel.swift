import AgentCore
import Foundation
import LibraryCore
import ModelProviders
import Observation
import ReflectionCore

/// Read-only presentation state for the user's local reflection archive.
/// It intentionally does not infer a profile, create memory, or call a provider.
@MainActor @Observable
final class ThoughtsModel {
    private let archive: ReflectionArchiveService
    private let reflections: any ReflectionRepository
    private let configurations: any ProviderConfigurationRepository
    private let secrets: any SecretStore

    private(set) var entries: [ReflectionArchiveEntry] = []
    private(set) var isLoading = false
    private(set) var replyingTo: ReflectionID?
    var errorMessage: String?

    init(
        books: any BookRepository,
        reflections: any ReflectionRepository,
        configurations: any ProviderConfigurationRepository,
        secrets: any SecretStore
    ) {
        archive = ReflectionArchiveService(books: books, reflections: reflections)
        self.reflections = reflections
        self.configurations = configurations
        self.secrets = secrets
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

    func requestAgentReply(for reflection: Reflection) async {
        guard replyingTo == nil else { return }
        replyingTo = reflection.id
        defer { replyingTo = nil }
        do {
            guard let configuration = try await configurations.currentConfiguration(),
                  let key = try await secrets.secret(for: configuration.secretReference),
                  !key.isEmpty else {
                throw ModelClientError.invalidConfiguration
            }
            let client = try OpenAICompatibleModelClient(configuration: configuration, apiKey: key)
            try await ReflectionAgentReplyService(reflections: reflections, client: client).reply(to: reflection.id)
            await reload()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = ProviderSettingsModel.message(for: error)
        }
    }
}

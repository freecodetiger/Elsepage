import AppInfrastructure
import LibraryCore
import Observation

/// Drives the three-step first-launch flow (PRD §11): 导入第一本 EPUB → 配置
/// AI Provider → 指向第一次阅读与 Reflection. Deliberately reuses the live
/// object graph: imports go through `LibraryModel` (same staging, dedupe and
/// indexing as the 书架) and the AI step mutates the shared
/// `ProviderSettingsModel`, so anything set up here is immediately the app's
/// real state — onboarding is an entrance, not a parallel world.
@MainActor @Observable
final class OnboardingModel: Identifiable {
    let library: LibraryModel
    let provider: ProviderSettingsModel
    private(set) var flow = OnboardingFlow()
    /// The book imported during the flow, so step 3 can open it directly.
    private(set) var importedBook: Book?
    private(set) var importErrorMessage: String?
    private(set) var isImporting = false

    init(library: LibraryModel, provider: ProviderSettingsModel) {
        self.library = library
        self.provider = provider
    }

    var step: OnboardingStep { flow.step }

    /// Step 1: import through the real library pipeline. A duplicate counts as
    /// success ("已在书架上" is equally true); a failure surfaces inline and the
    /// step stays skippable — onboarding never blocks on one book.
    func importEPUB(at url: URL) async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        library.errorMessage = nil
        library.duplicateTitle = nil
        guard let book = await library.importBook(url) else {
            importErrorMessage = library.errorMessage ?? "这本书没能导入，可以再试一次。"
            library.errorMessage = nil
            return
        }
        importErrorMessage = nil
        // A duplicate is confirmed inline (「已在书架上」); clear the flag so the
        // 书架 does not pop its own duplicate alert after the flow ends.
        library.duplicateTitle = nil
        importedBook = book
        flow.importSucceeded(title: book.title)
    }

    /// Step 2: save (key → Keychain, configuration → local store) then run the
    /// Test Connection. Feedback comes from the provider model's own state; a
    /// successful test unlocks the step's 继续 affordance.
    func saveAndTestProvider() async {
        provider.errorMessage = nil
        guard await provider.save() else { return }
        await provider.testConnection()
        if provider.lastConnectionTestSucceeded {
            flow.connectionTestSucceeded()
        }
    }

    func proceed() { flow.proceed() }
    func skipCurrentStep() { flow.skipCurrentStep() }
    func goBack() { flow.goBack() }

    /// Called when the flow ends. The completion flag itself is written by
    /// `AppModel.completeOnboarding()` (it owns the store); here we only drop
    /// the transient secret typed but never saved, matching the settings page.
    func prepareForDismissal() {
        provider.clearTransientSecret()
    }
}

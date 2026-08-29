import AppInfrastructure
import Foundation
import Testing

/// ONB-01..03: onboarding 状态机——三步推进、每步可见的跳过、回退不丢已完成
/// 内容;首次启动决策(已有内容静默完成);完成标记存于标准 UserDefaults 域,
/// Phase 1「清除所有本地数据」移除整个域后流程随之重新触发。
struct OnboardingFlowTests {
    // MARK: - 步骤推进

    @Test func freshFlowStartsOnImportStepWithThreeSteps() {
        let flow = OnboardingFlow()
        #expect(flow.step == .importBook)
        #expect(OnboardingStep.allCases.count == 3)
        #expect(!flow.isOnLastStep)
        #expect(!flow.isFinished)
    }

    @Test func importSuccessIsRememberedAndProceedAdvancesToConfigureAI() {
        var flow = OnboardingFlow()
        flow.importSucceeded(title: "夜航西飞")
        flow.proceed()
        #expect(flow.step == .configureAI)
        #expect(flow.importedBookTitle == "夜航西飞")
    }

    @Test func importSuccessWithBlankTitleIsIgnored() {
        var flow = OnboardingFlow()
        flow.importSucceeded(title: "   ")
        #expect(flow.importedBookTitle == nil)
    }

    @Test func connectionTestSuccessThenProceedReachesFirstRead() {
        var flow = OnboardingFlow()
        flow.skipCurrentStep()
        flow.connectionTestSucceeded()
        flow.proceed()
        #expect(flow.step == .firstRead)
        #expect(flow.hasSucceededConnectionTest)
        #expect(flow.isOnLastStep)
        #expect(!flow.isFinished)
    }

    @Test func proceedOnLastStepFinishesTheFlow() {
        var flow = OnboardingFlow()
        flow.proceed()
        flow.proceed()
        flow.proceed()
        #expect(flow.isFinished)
        #expect(flow.step == .firstRead)
    }

    @Test func skippingEveryStepStillReachesTheEndQuietly() {
        var flow = OnboardingFlow()
        flow.skipCurrentStep()
        flow.skipCurrentStep()
        flow.skipCurrentStep()
        #expect(flow.isFinished)
        #expect(flow.importedBookTitle == nil)
        #expect(!flow.hasSucceededConnectionTest)
    }

    @Test func proceedAfterFinishIsANoOp() {
        var flow = OnboardingFlow()
        flow.proceed()
        flow.proceed()
        flow.proceed()
        flow.proceed()
        #expect(flow.isFinished)
    }

    // MARK: - 回退

    @Test func firstStepCannotGoBack() {
        var flow = OnboardingFlow()
        flow.goBack()
        #expect(flow.step == .importBook)
        #expect(!flow.canGoBack)
    }

    @Test func goBackReturnsToThePreviousStep() {
        var flow = OnboardingFlow()
        flow.proceed()
        flow.goBack()
        #expect(flow.step == .importBook)
    }

    @Test func goBackKeepsEarlierAccomplishments() {
        var flow = OnboardingFlow()
        flow.importSucceeded(title: "夜航西飞")
        flow.proceed()
        flow.connectionTestSucceeded()
        flow.proceed()
        flow.goBack()
        flow.goBack()
        #expect(flow.step == .importBook)
        #expect(flow.importedBookTitle == "夜航西飞")
        #expect(flow.hasSucceededConnectionTest)
        #expect(!flow.isFinished)
    }

    @Test func goBackAfterFinishDoesNotUnfinishTheFlow() {
        var flow = OnboardingFlow()
        flow.proceed()
        flow.proceed()
        flow.proceed()
        flow.goBack()
        #expect(flow.isFinished)
    }

    // MARK: - 首次启动决策(已有内容自动完成)

    @Test func freshInstallShowsTheFlow() {
        #expect(OnboardingLaunchResolver.decide(
            hasCompletedBefore: false,
            hasBooksInLibrary: false,
            hasProviderConfiguration: false
        ) == .showFlow)
    }

    @Test func existingBooksAutoCompleteWithoutInterrupting() {
        #expect(OnboardingLaunchResolver.decide(
            hasCompletedBefore: false,
            hasBooksInLibrary: true,
            hasProviderConfiguration: false
        ) == .completeSilently)
    }

    @Test func existingProviderAutoCompletes() {
        #expect(OnboardingLaunchResolver.decide(
            hasCompletedBefore: false,
            hasBooksInLibrary: false,
            hasProviderConfiguration: true
        ) == .completeSilently)
    }

    @Test func completedFlagBeatsExistingContent() {
        #expect(OnboardingLaunchResolver.decide(
            hasCompletedBefore: true,
            hasBooksInLibrary: true,
            hasProviderConfiguration: true
        ) == .notNeeded)
    }

    // MARK: - 完成标记存储

    /// 完成标记是普通 UserDefaults 布尔值;真机上的重触发不靠额外清理逻辑,
    /// 而是依赖 Phase 1 清除数据时移除整个 standard 域。
    @Test func completionStoreRoundTripsThroughUserDefaults() throws {
        let suiteName = "onboarding.hasCompleted.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = OnboardingCompletionStore(defaults: defaults)
        #expect(!store.hasCompletedBefore)

        store.setCompleted()
        #expect(store.hasCompletedBefore)
        #expect(defaults.bool(forKey: OnboardingCompletionStore.storageKey))

        // 模拟清除所有本地数据:整个域被移除后回到首次启动状态。
        defaults.removePersistentDomain(forName: suiteName)
        #expect(!OnboardingCompletionStore(defaults: UserDefaults(suiteName: suiteName)!).hasCompletedBefore)
    }
}

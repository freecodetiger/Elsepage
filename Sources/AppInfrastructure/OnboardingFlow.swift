import Foundation

/// The three onboarding goals in PRD §11 order: 导入第一本 EPUB → 配置 AI
/// Provider → 指向第一次阅读与 Reflection. The order is part of the contract.
public enum OnboardingStep: Int, CaseIterable, Sendable {
    case importBook = 0
    case configureAI = 1
    case firstRead = 2

    public var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    public var previous: OnboardingStep? {
        rawValue == 0 ? nil : OnboardingStep(rawValue: rawValue - 1)
    }
}

/// UI-free state machine for the first-launch flow (PRD §11, ≤ 三步). Every
/// step has a visible skip, the last action completes the flow, and going back
/// never destroys what was already accomplished (PRD §10.1: 安静、不制造负罪感).
public struct OnboardingFlow: Equatable, Sendable {
    public private(set) var step: OnboardingStep = .importBook
    /// Title of the book that landed in the library during this flow, if any.
    /// Drives the step-1 confirmation line and the step-3 "打开刚导入的书" affordance.
    public private(set) var importedBookTitle: String?
    /// Whether a provider connection test succeeded during this flow.
    public private(set) var hasSucceededConnectionTest = false
    /// Set when the user finishes (or skips past) the last step.
    public private(set) var isFinished = false

    public init() {}

    public var canGoBack: Bool { !isFinished && step.previous != nil }

    public var isOnLastStep: Bool { step.next == nil }

    /// Records a successful import. A blank title is ignored so a bad metadata
    /// read cannot put an empty book name on screen.
    public mutating func importSucceeded(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        importedBookTitle = trimmed
    }

    /// Records a successful Test Connection.
    public mutating func connectionTestSucceeded() {
        hasSucceededConnectionTest = true
    }

    /// The primary action ("继续" / "打开刚导入的书"): advances one step and
    /// finishes the flow on the last step.
    public mutating func proceed() {
        guard !isFinished, let next = step.next else {
            isFinished = true
            return
        }
        step = next
    }

    /// The always-visible skip ("稍后再说" / "先跳过"): advances exactly like
    /// proceeding but records nothing — skipping is not failing.
    public mutating func skipCurrentStep() {
        proceed()
    }

    public mutating func goBack() {
        guard canGoBack, let previous = step.previous else { return }
        step = previous
    }
}

/// First-launch decision derived from the completion flag and existing content.
public enum OnboardingLaunchDecision: Equatable, Sendable {
    /// Flag absent and nothing set up yet: present the flow.
    case showFlow
    /// Flag absent but the user already has books or a configured provider —
    /// an upgrading user. Complete silently; never interrupt settled users.
    case completeSilently
    /// Completion flag already set.
    case notNeeded
}

public enum OnboardingLaunchResolver {
    /// Existing-content auto-skip (ONB-03): books in the library or a configured
    /// provider mean the flow would only repeat what the user already did.
    public static func decide(
        hasCompletedBefore: Bool,
        hasBooksInLibrary: Bool,
        hasProviderConfiguration: Bool
    ) -> OnboardingLaunchDecision {
        if hasCompletedBefore { return .notNeeded }
        if hasBooksInLibrary || hasProviderConfiguration { return .completeSilently }
        return .showFlow
    }
}

/// Persists onboarding completion in the app's standard UserDefaults domain
/// under "onboarding.hasCompleted". The placement is deliberate: 「清除所有本地数据」
/// (Phase 1) removes the whole standard domain without preservation, so the
/// flag disappears with it and the flow re-triggers after a wipe (ONB-03)
/// without any extra reset wiring.
public struct OnboardingCompletionStore: @unchecked Sendable {
    public static let storageKey = "onboarding.hasCompleted"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The flag is only ever written as `true`, so absence and `false` both
    /// mean "first launch".
    public var hasCompletedBefore: Bool {
        defaults.bool(forKey: Self.storageKey)
    }

    public func setCompleted() {
        defaults.set(true, forKey: Self.storageKey)
    }
}

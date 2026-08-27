import AchievementCore
import Foundation
import Observation

/// Presentation state for the low-key achievement badges. Owns the unlock event
/// handling and the one-at-a-time toast queue shown by `AchievementToastOverlay`.
/// Deliberately small: no scores, no levels, no locked/progress UI (PRD P8).
@MainActor @Observable
final class AchievementModel {
    private let service: AchievementService
    private(set) var unlocked: [AchievementRecord] = []
    private(set) var pendingUnlock: AchievementRecord?
    private var queue: [AchievementRecord] = []

    init(service: AchievementService) {
        self.service = service
    }

    func reload() async {
        do {
            unlocked = try await service.unlocked().sorted { $0.unlockedAt > $1.unlockedAt }
        } catch {
            // Derived presentation data; keep current values on failure.
        }
    }

    /// Evaluates a behavior moment and surfaces any newly unlocked achievements.
    /// Never throws — an achievement miss must not block the reflection flow.
    func handle(_ event: AchievementEvent) async {
        do {
            let created = try await service.evaluate(event)
            guard !created.isEmpty else { return }
            unlocked = (try? await service.unlocked()) ?? unlocked
            queue.append(contentsOf: created)
            if pendingUnlock == nil { presentNext() }
        } catch {
            // Keep the reflection flow alive regardless.
        }
    }

    func dismissPending() {
        pendingUnlock = nil
        presentNext()
    }

    private func presentNext() {
        guard pendingUnlock == nil, !queue.isEmpty else { return }
        pendingUnlock = queue.removeFirst()
    }
}

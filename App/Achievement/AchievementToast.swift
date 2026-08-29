import AchievementCore
import SwiftUI
import UIKit

/// Non-blocking top banner for a freshly unlocked achievement (P1: never interrupt
/// reading). Auto-dismisses after a short beat; tap to dismiss early.
struct AchievementToast: View {
    let achievement: Achievement
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: achievement.systemImage)
                .font(.title3)
                .foregroundStyle(Color.elsepageAccent)
                .frame(width: 36, height: 36)
                .background(Color.elsepageAccent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("解锁成就").font(.caption2).foregroundStyle(.secondary)
                Text(achievement.title).font(.subheadline.weight(.semibold))
                Text(achievement.blurb).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .accessibilityLabel("关闭")
        }
        .padding(ElsepageTheme.Spacing.medium)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ElsepageTheme.Radius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ElsepageTheme.Radius.large, style: .continuous)
                .stroke(Color.primary.opacity(0.06))
        }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .padding(.horizontal, ElsepageTheme.Spacing.page)
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
    }
}

/// Renders the pending unlock as a top banner with a single success haptic.
/// Applied at every container where an unlock can fire (AppShell, reflection sheet, archive).
struct AchievementToastOverlay: ViewModifier {
    let achievements: AchievementModel?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let record = achievements?.pendingUnlock,
               let definition = Achievement.all.first(where: { $0.id == record.id }) {
                AchievementToast(achievement: definition) { achievements?.dismissPending() }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear { present(record) }
            }
        }
        .animation(.snappy(duration: 0.25), value: achievements?.pendingUnlock?.id)
    }

    @MainActor
    private func present(_ record: AchievementRecord) {
        Haptics.achievementUnlocked()
        Task { [weak achievements] in
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run { achievements?.dismissPending() }
        }
    }
}

extension View {
    func achievementToast(_ achievements: AchievementModel?) -> some View {
        modifier(AchievementToastOverlay(achievements: achievements))
    }
}

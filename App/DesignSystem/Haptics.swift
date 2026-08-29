import UIKit

/// The closed haptics vocabulary (PRD §10.4): key moments only — 长按开始录音,
/// Reflection 完成, 新 Achievement, 书籍导入完成, 关键卡片展开. Deliberately
/// centralized so the vocabulary stays closed and every call site is greppable;
/// page turns and ordinary reading never vibrate (P8).
@MainActor
enum Haptics {
    /// 长按开始录音（以及对应的松手停止确认）。
    static func recordingPress() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Reflection 保存完成。
    static func reflectionSaved() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// 一枚新成就解锁（成就 toast 出现时）。
    static func achievementUnlocked() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// 书籍导入完成。
    static func importCompleted() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// 关键卡片展开（想法/记忆卡片）。
    static func cardExpanded() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// 会话里发送一条「继续说」（轻确认；保留既有触感）。
    static func followUpSent() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// 阅读器内高亮落笔。
    static func highlightCreated() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// 阅读器内标注删除。
    static func annotationDeleted() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
}

import AppInfrastructure
import SwiftUI

enum ElsepageTheme {
    enum Spacing {
        static let xSmall: CGFloat = 6
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
        static let xLarge: CGFloat = 28
        static let page: CGFloat = 20
    }

    enum Radius {
        static let small: CGFloat = 12
        static let large: CGFloat = 24
    }

    enum Typography {
        static let emptyStateTitle = Font.system(.title2, design: .serif, weight: .semibold)
        static let bookTitle = Font.system(.title3, design: .serif, weight: .semibold)
        static let itemTitle = Font.subheadline.weight(.semibold)
        static let metadata = Font.caption
    }

    enum MaterialToken {
        static let chrome: Material = .ultraThinMaterial
        static let control: Material = .thinMaterial
    }

    enum Shadow {
        static let coverColor = Color.black.opacity(0.17)
        static let coverRadius: CGFloat = 10
        static let coverY: CGFloat = 6
        static let floatingColor = Color.black.opacity(0.09)
        static let floatingRadius: CGFloat = 18
        static let floatingY: CGFloat = 8
    }

    enum Motion {
        static let quick = Animation.easeInOut(duration: 0.18)

        /// One-off key-moment animation (PRD §10.3: 阅读完成 / Reflection 完成 /
        /// 思想沉淀 / Memory 更新 / Streak 延续 / Achievement / 引用回跳). Always
        /// brief and quiet; under Reduce Motion it is suppressed entirely
        /// (nil = no animation). Reading content itself never animates (P1).
        static func moment(_ reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .snappy(duration: 0.3)
        }
    }
}

extension AnyTransition {
    /// The matching quiet transition for `ElsepageTheme.Motion.moment`; under
    /// Reduce Motion the swap is instant.
    static func moment(_ reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .opacity
    }
}

extension ShapeStyle where Self == Color {
    /// Theme tokens are built from `ElsepagePalette` (Sources/AppInfrastructure)
    /// so the WCAG contrast audited in unit tests is the exact palette the UI
    /// renders (A11Y-03).
    static var elsepageBackground: Color {
        color(from: ElsepagePalette.background)
    }

    static var elsepageSurface: Color {
        color(from: ElsepagePalette.surface)
    }

    static var elsepageAccent: Color {
        color(from: ElsepagePalette.accent)
    }

    /// Label color for prominent buttons filled with the accent tint — white on
    /// the deep light accent, near-black on the pale dark accent (A11Y-03).
    static var elsepageOnAccent: Color {
        color(from: ElsepagePalette.onAccent)
    }

    static var elsepageReaderSepia: Color {
        color(from: ElsepagePalette.readerSepia)
    }

    private static func color(from pair: ElsepagePalette.ThemePair) -> Color {
        Color(light: UIColor(red: pair.light.red, green: pair.light.green, blue: pair.light.blue, alpha: 1),
              dark: UIColor(red: pair.dark.red, green: pair.dark.green, blue: pair.dark.blue, alpha: 1))
    }
}

private extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

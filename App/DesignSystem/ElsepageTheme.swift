import AppInfrastructure
import Foundation
import SwiftUI

enum ElsepageTheme {
    enum Spacing {
        static let xSmall: CGFloat = 6
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
        static let xLarge: CGFloat = 28
        static let page: CGFloat = 20
        /// The 16pt content inset used by the native bookshelf, Thoughts and
        /// My Mind screens. `page` stays for screens that have not been
        /// converged yet.
        static let pageInset: CGFloat = 16
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
        /// 看法沉淀 / Memory 更新 / Streak 延续 / Achievement / 引用回跳). Always
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

    static var elsepageSurfaceSecondary: Color {
        color(from: ElsepagePalette.surfaceSecondary)
    }

    static var elsepageBorder: Color {
        color(from: ElsepagePalette.border)
    }

    static var elsepageTextPrimary: Color {
        color(from: ElsepagePalette.contentPrimary)
    }

    static var elsepageTextSecondary: Color {
        color(from: ElsepagePalette.contentSecondary)
    }

    static var elsepageTextTertiary: Color {
        color(from: ElsepagePalette.contentTertiary)
    }

    static var elsepageBrand: Color {
        color(from: ElsepagePalette.brand)
    }

    static var elsepageInteractive: Color {
        color(from: ElsepagePalette.interactive)
    }

    static var elsepageOnInteractive: Color {
        color(from: ElsepagePalette.onInteractive)
    }

    static var elsepageSuccess: Color {
        color(from: ElsepagePalette.success)
    }

    static var elsepageWarning: Color {
        color(from: ElsepagePalette.warning)
    }

    static var elsepageDanger: Color {
        color(from: ElsepagePalette.danger)
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

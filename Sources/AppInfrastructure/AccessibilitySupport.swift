import CoreGraphics
import Foundation

/// WCAG 2.1 contrast math plus the Elsepage theme palette as pure data (A11Y-03).
///
/// The palette lives here — not only in the App target — so unit tests can
/// assert AA contrast per theme over the exact values the SwiftUI tokens use,
/// and the two can never drift apart. `App/DesignSystem/ElsepageTheme.swift`
/// builds its dynamic `UIColor`s directly from `ElsepagePalette`.
public struct PaletteRGB: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    /// WCAG 2.1 relative luminance.
    public var relativeLuminance: Double {
        func linearize(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue)
    }
}

public enum WCAGContrast {
    /// WCAG AA for normal-size text (< 18pt regular / < 14pt bold).
    public static let bodyTextMinimum: Double = 4.5
    /// WCAG AA for large text (≥ 18pt regular / ≥ 14pt bold) and UI components.
    public static let largeTextOrUIMinimum: Double = 3.0

    public static func ratio(_ a: PaletteRGB, _ b: PaletteRGB) -> Double {
        let la = a.relativeLuminance, lb = b.relativeLuminance
        let (lighter, darker) = la >= lb ? (la, lb) : (lb, la)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Alpha-composites `top` over an opaque `base` (straight alpha), used to
    /// model translucent token backgrounds such as badge fills over a surface.
    public static func blend(_ top: PaletteRGB, alpha: Double, over base: PaletteRGB) -> PaletteRGB {
        let a = min(max(alpha, 0), 1)
        return PaletteRGB(
            red: top.red * a + base.red * (1 - a),
            green: top.green * a + base.green * (1 - a),
            blue: top.blue * a + base.blue * (1 - a)
        )
    }
}

/// The Elsepage theme palette (light + dark), mirrored 1:1 by
/// `App/DesignSystem/ElsepageTheme.swift`.
public enum ElsepagePalette {
    public struct ThemePair: Sendable {
        public let light: PaletteRGB
        public let dark: PaletteRGB

        public init(light: PaletteRGB, dark: PaletteRGB) {
            self.light = light
            self.dark = dark
        }

        public func resolve(dark: Bool) -> PaletteRGB { dark ? self.dark : self.light }
    }

    /// Page background.
    public static let background = ThemePair(
        light: PaletteRGB(red: 0.969, green: 0.965, blue: 0.949),
        dark: PaletteRGB(red: 0.075, green: 0.078, blue: 0.071)
    )
    /// Card / chrome surface. Material chrome approximates this over background.
    public static let surface = ThemePair(
        light: PaletteRGB(red: 0.992, green: 0.988, blue: 0.976),
        dark: PaletteRGB(red: 0.125, green: 0.129, blue: 0.118)
    )
    /// Brand sage green: text accents, prominent buttons, progress.
    /// A11Y-03: the light variant is deliberately deep enough for AA (≥ 4.5:1)
    /// as body-size text on every theme surface, including 12%-tinted badges.
    public static let accent = ThemePair(
        light: PaletteRGB(red: 0.33, green: 0.39, blue: 0.33),
        dark: PaletteRGB(red: 0.61, green: 0.69, blue: 0.60)
    )
    /// Reader sepia theme background (reader chrome sits on it).
    public static let readerSepia = ThemePair(
        light: PaletteRGB(red: 0.965, green: 0.945, blue: 0.902),
        dark: PaletteRGB(red: 0.14, green: 0.13, blue: 0.105)
    )
    /// Label color for prominent buttons filled with `accent`. White passes on
    /// the deep light accent, but the pale dark accent needs a near-black label
    /// (white is only 2.3:1 there) — so the pair is theme-adaptive, not white.
    public static let onAccent = ThemePair(
        light: PaletteRGB(red: 1, green: 1, blue: 1),
        dark: PaletteRGB(red: 0.075, green: 0.078, blue: 0.071)
    )
}

/// Platform accessibility baselines shared by App code (A11Y-03).
public enum AccessibilityMetrics {
    /// Apple HIG minimum tap target (44×44pt).
    public static let minimumTapTargetSide: CGFloat = 44
    /// Badge/tint fill opacity over surfaces; asserted ≥ AA in tests with the
    /// accent color composited at this alpha.
    public static let badgeTintAlpha: Double = 0.12
}

/// Testable VoiceOver label builders (A11Y-02). The library card label keeps
/// the Phase 2 reading order — title, author, stats — and now includes the
/// progress percent so the progress bar (hidden by the card's element
/// flattening) is still announced.
public enum LibraryBookAccessibility {
    public static func label(
        title: String,
        author: String?,
        statsLine: String?,
        progress: Double?
    ) -> String {
        var parts: [String] = [title, (author?.isEmpty ?? true) ? "未知作者" : author!]
        if let statsLine, !statsLine.isEmpty { parts.append(statsLine) }
        if let progress {
            let percent = Int((progress * 100).rounded())
            parts.append("阅读进度 \(percent)%")
        }
        return parts.joined(separator: "，")
    }
}

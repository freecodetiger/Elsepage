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
///
/// Semantic roles are intentionally separate even when light/dark values happen
/// to be equal. Product color, interaction color and status color must be able
/// to evolve independently without changing call sites.
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
        light: PaletteRGB(red: 0.949019608, green: 0.949019608, blue: 0.949019608),
        dark: PaletteRGB(red: 0.043137255, green: 0.043137255, blue: 0.043137255)
    )

    /// Card, form and navigation surface.
    public static let surface = ThemePair(
        light: PaletteRGB(red: 1, green: 1, blue: 1),
        dark: PaletteRGB(red: 0.094117647, green: 0.094117647, blue: 0.094117647)
    )

    /// Secondary card and response surfaces nested inside the primary surface.
    public static let surfaceSecondary = ThemePair(
        light: PaletteRGB(red: 0.968627451, green: 0.968627451, blue: 0.968627451),
        dark: PaletteRGB(red: 0.133333333, green: 0.133333333, blue: 0.133333333)
    )

    /// Hairlines and outlines.
    public static let border = ThemePair(
        light: PaletteRGB(red: 0.831372549, green: 0.831372549, blue: 0.831372549),
        dark: PaletteRGB(red: 0.203921569, green: 0.203921569, blue: 0.203921569)
    )

    /// Primary reading and UI text.
    public static let contentPrimary = ThemePair(
        light: PaletteRGB(red: 0.066666667, green: 0.066666667, blue: 0.066666667),
        dark: PaletteRGB(red: 0.956862745, green: 0.956862745, blue: 0.956862745)
    )

    /// Secondary text and metadata.
    public static let contentSecondary = ThemePair(
        light: PaletteRGB(red: 0.4, green: 0.4, blue: 0.4),
        dark: PaletteRGB(red: 0.650980392, green: 0.650980392, blue: 0.650980392)
    )

    /// Tertiary text and placeholders.
    public static let contentTertiary = ThemePair(
        light: PaletteRGB(red: 0.431372549, green: 0.431372549, blue: 0.431372549),
        dark: PaletteRGB(red: 0.541176471, green: 0.541176471, blue: 0.541176471)
    )

    /// Product identity and emphasis.
    public static let brand = ThemePair(
        light: PaletteRGB(red: 0.066666667, green: 0.066666667, blue: 0.066666667),
        dark: PaletteRGB(red: 0.960784314, green: 0.960784314, blue: 0.960784314)
    )

    /// Interactive controls, links and primary buttons.
    public static let interactive = ThemePair(
        light: PaletteRGB(red: 0.066666667, green: 0.066666667, blue: 0.066666667),
        dark: PaletteRGB(red: 0.960784314, green: 0.960784314, blue: 0.960784314)
    )

    /// Content drawn on an interactive fill.
    public static let onInteractive = ThemePair(
        light: PaletteRGB(red: 1, green: 1, blue: 1),
        dark: PaletteRGB(red: 0.066666667, green: 0.066666667, blue: 0.066666667)
    )

    /// Completed, connected and ready states.
    public static let success = ThemePair(
        light: PaletteRGB(red: 0.137254902, green: 0.478431373, blue: 0.231372549),
        dark: PaletteRGB(red: 0.439215686, green: 0.847058824, blue: 0.545098039)
    )

    /// Attention needed, but not a failure.
    public static let warning = ThemePair(
        light: PaletteRGB(red: 0.541176471, green: 0.352941176, blue: 0),
        dark: PaletteRGB(red: 0.941176471, green: 0.705882353, blue: 0.301960784)
    )

    /// Destructive action, recording and failure.
    public static let danger = ThemePair(
        light: PaletteRGB(red: 0.705882353, green: 0.137254902, blue: 0.094117647),
        dark: PaletteRGB(red: 1, green: 0.478431373, blue: 0.439215686)
    )

    /// Reader sepia theme background (reader chrome sits on it).
    public static let readerSepia = ThemePair(
        light: PaletteRGB(red: 0.965, green: 0.945, blue: 0.902),
        dark: PaletteRGB(red: 0.14, green: 0.13, blue: 0.105)
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

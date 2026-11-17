import SwiftUI
import UIKit

/// Semantic design tokens for new UI. Existing screens keep using
/// `ElsepageTheme` until they migrate; both resolve to the same palette, so a
/// screen can move one surface at a time without a visual fork.
///
/// Rules:
/// - Colors are roles, never literal values.
/// - Type uses `Font.TextStyle`, so Dynamic Type is automatic.
/// - Spacing follows the 4pt grid (2pt only for hairlines/optical nudges).
/// - Motion is expressed as intent; Reduce Motion suppression is the caller's
///   responsibility through the `reduceMotion` helpers.
enum ElsepageColor {
    // Surfaces
    static let canvas = Color.elsepageBackground
    static let surface = Color.elsepageSurface
    static let surfaceSecondary = Color.elsepageSurfaceSecondary
    static let border = Color.elsepageBorder
    static let separator = Color.elsepageBorder

    // Content
    static let textPrimary = Color.elsepageTextPrimary
    static let textSecondary = Color.elsepageTextSecondary
    static let textTertiary = Color.elsepageTextTertiary

    // Interactive
    static let accent = Color.elsepageInteractive
    static let onAccent = Color.elsepageOnInteractive
    static let brand = Color.elsepageBrand

    // Status
    static let success = Color.elsepageSuccess
    static let warning = Color.elsepageWarning
    static let danger = Color.elsepageDanger

    // Component states
    static let pressedOverlay = Color.primary.opacity(0.06)
    static let disabledContent = Color.elsepageTextTertiary
    static let scrim = Color.black.opacity(0.28)
    static let fieldFill = Color(uiColor: .tertiarySystemFill)
}

enum ElsepageFont {
    static let display = Font.system(.largeTitle, design: .default, weight: .bold)
    static let title1 = Font.system(.title, design: .default, weight: .semibold)
    static let title2 = Font.system(.title2, design: .default, weight: .semibold)
    static let title3 = Font.system(.title3, design: .default, weight: .semibold)
    static let headline = Font.system(.headline, design: .default, weight: .semibold)
    static let body = Font.body
    static let callout = Font.callout
    static let subheadline = Font.subheadline
    static let footnote = Font.footnote
    static let caption = Font.caption
    static let caption2 = Font.caption2

    static let bookTitle = Font.system(.title2, design: .serif, weight: .semibold)
    static let serifBody = Font.system(.body, design: .serif)
    static let serifSubheadline = Font.system(.subheadline, design: .serif)
    static let mono = Font.system(.footnote, design: .monospaced)
}

enum ElsepageSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    static let huge: CGFloat = 40

    /// Page inset for the three root screens and their sheets.
    static let page: CGFloat = 16

    /// HIG minimum touch target; also the default icon-button side.
    static let touchTarget: CGFloat = 44
    static let controlHeight: CGFloat = 44
    static let fieldMinHeight: CGFloat = 44
    static let buttonHeight: CGFloat = 48
    static let compactButtonHeight: CGFloat = 44
}

enum ElsepageRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    /// Capsule is a shape, not a radius; use `Capsule()` directly.
    static let card: CGFloat = 12
    static let field: CGFloat = 10
    static let button: CGFloat = 12
    static let sheet: CGFloat = 24
}

enum ElsepageBorder {
    static let hairline: CGFloat = 0.5
    static let regular: CGFloat = 1
    static let strong: CGFloat = 1.5
    static let color = ElsepageColor.border
}

struct ElsepageShadow: Equatable {
    let color: Color
    let radius: CGFloat
    let y: CGFloat

    static let none = ElsepageShadow(color: .clear, radius: 0, y: 0)
    static let card = ElsepageShadow(
        color: .black.opacity(0.06),
        radius: 12,
        y: 4
    )
    static let floating = ElsepageShadow(
        color: .black.opacity(0.12),
        radius: 18,
        y: 8
    )
    static let cover = ElsepageShadow(
        color: .black.opacity(0.17),
        radius: 10,
        y: 6
    )
}

enum ElsepageElevation {
    static let none = ElsepageShadow.none
    static let card = ElsepageShadow.card
    static let floating = ElsepageShadow.floating
    static let cover = ElsepageShadow.cover
}

enum ElsepageMotion {
    static let quick = Animation.easeInOut(duration: 0.18)
    static let standard = Animation.snappy(duration: 0.28)
    static let slow = Animation.easeInOut(duration: 0.35)
    static let pressScale: CGFloat = 0.98

    static func interactive(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : quick
    }

    static func standard(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : standard
    }
}

enum ElsepageState {
    static let pressedOpacity: Double = 0.86
    static let disabledOpacity: Double = 0.38
    static let loadingOpacity: Double = 0.72
    static let focusRingWidth: CGFloat = 2
}

/// Presentational state for catalog previews and for components that need to
/// render a state without a live interaction (e.g. a disabled row).
enum ElsepageControlState: String, CaseIterable, Identifiable {
    case normal
    case pressed
    case disabled
    case loading

    var id: String { rawValue }
    var title: String {
        switch self {
        case .normal: "Normal"
        case .pressed: "Pressed"
        case .disabled: "Disabled"
        case .loading: "Loading"
        }
    }
}

extension View {
    @ViewBuilder
    func elsepageShadow(_ shadow: ElsepageShadow) -> some View {
        if shadow == .none {
            self
        } else {
            self.shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
        }
    }

    @ViewBuilder
    func elsepageCardSurface(
        radius: CGFloat = ElsepageRadius.card,
        fill: Color = ElsepageColor.surface,
        border: Bool = true,
        elevation: ElsepageShadow = .none
    ) -> some View {
        self
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if border {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(ElsepageColor.border, lineWidth: ElsepageBorder.hairline)
                }
            }
            .elsepageShadow(elevation)
    }
}

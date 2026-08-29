import AppInfrastructure
import CoreGraphics
import LibraryCore
import XCTest

/// A11Y-01/02/03 unit coverage: WCAG contrast over the real theme palette,
/// VoiceOver label building, the tap-target baseline, and the accessibility
/// Dynamic Type grid adaptation.
final class AccessibilitySupportTests: XCTestCase {
    private let white = PaletteRGB(red: 1, green: 1, blue: 1)
    private let black = PaletteRGB(red: 0, green: 0, blue: 0)

    // MARK: - WCAG math sanity

    func testBlackOnWhiteIsTwentyOneToOne() {
        XCTAssertEqual(WCAGContrast.ratio(black, white), 21.0, accuracy: 0.01)
    }

    func testRatioIsSymmetric() {
        let sage = ElsepagePalette.accent.light
        XCTAssertEqual(WCAGContrast.ratio(sage, white), WCAGContrast.ratio(white, sage), accuracy: 0.0001)
    }

    func testBlendCompositesStraightAlpha() {
        let blended = WCAGContrast.blend(PaletteRGB(red: 1, green: 1, blue: 1), alpha: 0.5, over: black)
        XCTAssertEqual(blended.red, 0.5, accuracy: 0.0001)
        XCTAssertEqual(blended.green, 0.5, accuracy: 0.0001)
        XCTAssertEqual(blended.blue, 0.5, accuracy: 0.0001)
    }

    // MARK: - A11Y-03: theme token pairs meet WCAG AA in light AND dark

    /// The accent is used as body-size text (Journal labels, feedback lines,
    /// emphasized streak badge), so it must clear 4.5:1 on every surface it is
    /// drawn on, in both color schemes.
    func testAccentMeetsBodyTextContrastOnEverySurfaceInLightAndDark() {
        for dark in [false, true] {
            let scheme = dark ? "dark" : "light"
            for (surfaceName, surface) in [
                ("background", ElsepagePalette.background),
                ("surface", ElsepagePalette.surface),
                ("readerSepia", ElsepagePalette.readerSepia),
            ] {
                let ratio = WCAGContrast.ratio(ElsepagePalette.accent.resolve(dark: dark), surface.resolve(dark: dark))
                XCTAssertGreaterThanOrEqual(
                    ratio, WCAGContrast.bodyTextMinimum,
                    "accent on \(surfaceName) (\(scheme)) is \(ratio)"
                )
            }
        }
    }

    /// Prominent buttons fill with the accent and must keep an AA label both
    /// schemes (dark mode uses the near-black onAccent, white fails there).
    func testOnAccentLabelMeetsBodyTextContrastOnAccentFillInLightAndDark() {
        for dark in [false, true] {
            let ratio = WCAGContrast.ratio(
                ElsepagePalette.onAccent.resolve(dark: dark),
                ElsepagePalette.accent.resolve(dark: dark)
            )
            XCTAssertGreaterThanOrEqual(
                ratio, WCAGContrast.bodyTextMinimum,
                "onAccent label on accent fill (\(dark ? "dark" : "light")) is \(ratio)"
            )
        }
    }

    /// Badge fills are the accent at `badgeTintAlpha` over chrome; the accent
    /// badge text must stay AA against the composited background.
    func testAccentBadgeTextMeetsAAOverTintedBadgeBackgroundsInLightAndDark() {
        for dark in [false, true] {
            let scheme = dark ? "dark" : "light"
            let accent = ElsepagePalette.accent.resolve(dark: dark)
            for (baseName, base) in [
                ("background", ElsepagePalette.background),
                ("surface", ElsepagePalette.surface),
            ] {
                let badgeBackground = WCAGContrast.blend(
                    accent,
                    alpha: AccessibilityMetrics.badgeTintAlpha,
                    over: base.resolve(dark: dark)
                )
                let ratio = WCAGContrast.ratio(accent, badgeBackground)
                XCTAssertGreaterThanOrEqual(
                    ratio, WCAGContrast.bodyTextMinimum,
                    "accent on \(Int(AccessibilityMetrics.badgeTintAlpha * 100))% tinted badge over \(baseName) (\(scheme)) is \(ratio)"
                )
            }
        }
    }

    // MARK: - A11Y-03: tap target baseline

    func testMinimumTapTargetMatchesHIGFortyFourPoints() {
        XCTAssertEqual(AccessibilityMetrics.minimumTapTargetSide, 44)
    }

    // MARK: - A11Y-02: library card VoiceOver label

    func testLibraryCardLabelIncludesTitleAuthorStatsAndProgress() {
        let label = LibraryBookAccessibility.label(
            title: "置身事内",
            author: "兰小欢",
            statsLine: "读过 24 分钟 · 划线 3 · 想法 2",
            progress: 0.42
        )
        XCTAssertEqual(label, "置身事内，兰小欢，读过 24 分钟 · 划线 3 · 想法 2，阅读进度 42%")
    }

    func testLibraryCardLabelFallsBackForUnknownAuthorAndOmitsAbsentData() {
        let fresh = LibraryBookAccessibility.label(title: "新地", author: nil, statsLine: nil, progress: nil)
        XCTAssertEqual(fresh, "新地，未知作者")

        let emptyAuthor = LibraryBookAccessibility.label(title: "新地", author: "", statsLine: nil, progress: 0)
        XCTAssertEqual(emptyAuthor, "新地，未知作者，阅读进度 0%")
    }

    // MARK: - A11Y-01: library grid adapts at accessibility sizes

    func testAccessibilityDynamicTypeCollapsesLibraryGridToSingleColumn() {
        XCTAssertEqual(LibraryGridLayout.columnCount(isAccessibilitySize: false), 2)
        XCTAssertEqual(LibraryGridLayout.columnCount(isAccessibilitySize: true), 1)
    }

    func testColumnWidthHonorsExplicitColumnCount() {
        let width = LibraryGridLayout.columnWidth(
            containerWidth: 390,
            horizontalPadding: 20,
            columnSpacing: 16,
            columnCount: 1
        )
        XCTAssertEqual(width, 350)
    }
}

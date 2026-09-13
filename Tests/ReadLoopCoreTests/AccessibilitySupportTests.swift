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
        let interactive = ElsepagePalette.interactive.light
        XCTAssertEqual(WCAGContrast.ratio(interactive, white), WCAGContrast.ratio(white, interactive), accuracy: 0.0001)
    }

    func testBlendCompositesStraightAlpha() {
        let blended = WCAGContrast.blend(PaletteRGB(red: 1, green: 1, blue: 1), alpha: 0.5, over: black)
        XCTAssertEqual(blended.red, 0.5, accuracy: 0.0001)
        XCTAssertEqual(blended.green, 0.5, accuracy: 0.0001)
        XCTAssertEqual(blended.blue, 0.5, accuracy: 0.0001)
    }

    /// App chrome is intentionally neutral. Reader paper themes are excluded
    /// because reading comfort may still use warm paper/sepia surfaces.
    func testNeutralChromeTokensStayMonochromeInLightAndDark() {
        for dark in [false, true] {
            let scheme = dark ? "dark" : "light"
            for (tokenName, token) in [
                ("background", ElsepagePalette.background),
                ("surface", ElsepagePalette.surface),
                ("surfaceSecondary", ElsepagePalette.surfaceSecondary),
                ("border", ElsepagePalette.border),
                ("contentPrimary", ElsepagePalette.contentPrimary),
                ("contentSecondary", ElsepagePalette.contentSecondary),
                ("contentTertiary", ElsepagePalette.contentTertiary),
                ("brand", ElsepagePalette.brand),
                ("interactive", ElsepagePalette.interactive),
                ("onInteractive", ElsepagePalette.onInteractive),
            ] {
                let color = token.resolve(dark: dark)
                XCTAssertEqual(color.red, color.green, accuracy: 0.0001, "\(tokenName) red/green (\(scheme))")
                XCTAssertEqual(color.green, color.blue, accuracy: 0.0001, "\(tokenName) green/blue (\(scheme))")
            }
        }
    }

    // MARK: - A11Y-03: theme token pairs meet WCAG AA in light AND dark

    /// Reading text and interactive text must clear AA on every app surface.
    func testPrimaryAndInteractiveTextMeetBodyTextContrastOnEverySurface() {
        for dark in [false, true] {
            let scheme = dark ? "dark" : "light"
            for (surfaceName, surface) in [
                ("background", ElsepagePalette.background),
                ("surface", ElsepagePalette.surface),
                ("readerSepia", ElsepagePalette.readerSepia),
            ] {
                for (tokenName, token) in [
                    ("contentPrimary", ElsepagePalette.contentPrimary),
                    ("contentSecondary", ElsepagePalette.contentSecondary),
                    ("contentTertiary", ElsepagePalette.contentTertiary),
                    ("brand", ElsepagePalette.brand),
                    ("interactive", ElsepagePalette.interactive),
                ] {
                    let ratio = WCAGContrast.ratio(token.resolve(dark: dark), surface.resolve(dark: dark))
                    XCTAssertGreaterThanOrEqual(
                        ratio, WCAGContrast.bodyTextMinimum,
                        "\(tokenName) on \(surfaceName) (\(scheme)) is \(ratio)"
                    )
                }
            }
        }
    }

    /// Prominent buttons fill with the interactive token and must keep an AA
    /// label in both schemes.
    func testOnInteractiveLabelMeetsBodyTextContrastOnInteractiveFill() {
        for dark in [false, true] {
            let ratio = WCAGContrast.ratio(
                ElsepagePalette.onInteractive.resolve(dark: dark),
                ElsepagePalette.interactive.resolve(dark: dark)
            )
            XCTAssertGreaterThanOrEqual(
                ratio, WCAGContrast.bodyTextMinimum,
                "onInteractive label on interactive fill (\(dark ? "dark" : "light")) is \(ratio)"
            )
        }
    }

    /// Status colors are text-bearing tokens and must not become decorative
    /// light pastels that fail on neutral surfaces.
    func testStatusColorsMeetBodyTextContrastOnEverySurface() {
        for dark in [false, true] {
            let scheme = dark ? "dark" : "light"
            for (surfaceName, surface) in [
                ("background", ElsepagePalette.background),
                ("surface", ElsepagePalette.surface),
            ] {
                for (tokenName, token) in [
                    ("success", ElsepagePalette.success),
                    ("warning", ElsepagePalette.warning),
                    ("danger", ElsepagePalette.danger),
                ] {
                    let ratio = WCAGContrast.ratio(token.resolve(dark: dark), surface.resolve(dark: dark))
                    XCTAssertGreaterThanOrEqual(
                        ratio, WCAGContrast.bodyTextMinimum,
                        "\(tokenName) on \(surfaceName) (\(scheme)) is \(ratio)"
                    )
                }
            }
        }
    }

    /// Badge fills use the interactive token at `badgeTintAlpha` over chrome;
    /// the token must stay AA against the composited background.
    func testInteractiveBadgeTextMeetsAAOverTintedBadgeBackgrounds() {
        for dark in [false, true] {
            let scheme = dark ? "dark" : "light"
            let interactive = ElsepagePalette.interactive.resolve(dark: dark)
            for (baseName, base) in [
                ("background", ElsepagePalette.background),
                ("surface", ElsepagePalette.surface),
            ] {
                let badgeBackground = WCAGContrast.blend(
                    interactive,
                    alpha: AccessibilityMetrics.badgeTintAlpha,
                    over: base.resolve(dark: dark)
                )
                let ratio = WCAGContrast.ratio(interactive, badgeBackground)
                XCTAssertGreaterThanOrEqual(
                    ratio, WCAGContrast.bodyTextMinimum,
                    "interactive on \(Int(AccessibilityMetrics.badgeTintAlpha * 100))% tinted badge over \(baseName) (\(scheme)) is \(ratio)"
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

    // MARK: - Chinese-first date formatting

    func testChineseDateFormatsNeverUseEnglishMonthNames() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 14,
            hour: 23,
            minute: 10
        )))

        XCTAssertEqual(ElsepageDateFormat.monthTitle(date), "2026年9月")
        XCTAssertEqual(ElsepageDateFormat.shortDate(date), "9月14日")
        XCTAssertEqual(ElsepageDateFormat.dateTime(date), "9月14日 23:10")
        XCTAssertEqual(ElsepageDateFormat.yearMonthDay(date), "2026年9月14日")
        XCTAssertFalse(ElsepageDateFormat.monthTitle(date).contains("September"))
        XCTAssertFalse(ElsepageDateFormat.monthTitle(date).contains("Sep"))
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

import XCTest
@testable import ReadLoop

final class DesignSystemTokenTests: XCTestCase {
    func testSpacingFollowsAGridAndKeepsTouchTargets() {
        let spacing = [
            ElsepageSpacing.xxs,
            ElsepageSpacing.xs,
            ElsepageSpacing.sm,
            ElsepageSpacing.md,
            ElsepageSpacing.lg,
            ElsepageSpacing.xl,
            ElsepageSpacing.xxl,
            ElsepageSpacing.xxxl,
            ElsepageSpacing.huge,
        ]
        XCTAssertEqual(spacing, spacing.sorted())
        XCTAssertEqual(ElsepageSpacing.page, 16)
        XCTAssertGreaterThanOrEqual(ElsepageSpacing.touchTarget, 44)
        XCTAssertGreaterThanOrEqual(ElsepageSpacing.controlHeight, 44)
        XCTAssertGreaterThanOrEqual(ElsepageSpacing.fieldMinHeight, 44)
        XCTAssertGreaterThanOrEqual(ElsepageSpacing.buttonHeight, 44)
        XCTAssertGreaterThanOrEqual(ElsepageSpacing.compactButtonHeight, 44)
    }

    func testRadiiAreMonotonic() {
        let radii = [
            ElsepageRadius.xs,
            ElsepageRadius.sm,
            ElsepageRadius.md,
            ElsepageRadius.lg,
            ElsepageRadius.xl,
        ]
        XCTAssertEqual(radii, radii.sorted())
        XCTAssertEqual(ElsepageRadius.card, ElsepageRadius.md)
    }

    func testEveryButtonRoleAndStateIsCatalogued() {
        XCTAssertEqual(ElsepageButtonRole.allCases.count, 4)
        XCTAssertEqual(ElsepageControlState.allCases.count, 4)
        XCTAssertEqual(ElsepageBannerStyle.allCases.count, 4)
    }

    func testElevationAliasesStayInSync() {
        XCTAssertEqual(ElsepageElevation.none, ElsepageShadow.none)
        XCTAssertEqual(ElsepageElevation.card, ElsepageShadow.card)
        XCTAssertEqual(ElsepageElevation.floating, ElsepageShadow.floating)
        XCTAssertEqual(ElsepageElevation.cover, ElsepageShadow.cover)
    }

    func testReaderChromeFloatsWithoutReservingThePage() {
        // The chrome is a transient overlay: it must not take a permanent band
        // from the page, and its row still has to fit a touch target.
        XCTAssertEqual(ReaderChromeMetrics.contentTopInset, 0)
        XCTAssertEqual(ReaderChromeMetrics.contentBottomInset, 0)
        XCTAssertGreaterThanOrEqual(ReaderChromeMetrics.topBarHeight, ElsepageSpacing.touchTarget)
        XCTAssertGreaterThanOrEqual(ReaderChromeMetrics.bottomBarHeight, ElsepageSpacing.touchTarget)
    }
}

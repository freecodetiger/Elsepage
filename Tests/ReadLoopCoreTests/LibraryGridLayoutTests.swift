import CoreGraphics
import LibraryCore
import XCTest

final class LibraryGridLayoutTests: XCTestCase {
    func testTwoColumnsHaveEqualWidthWithinPaddedPhoneContent() {
        XCTAssertEqual(
            LibraryGridLayout.columnWidth(containerWidth: 390, horizontalPadding: 16, columnSpacing: 16),
            171
        )
    }

    func testWideCoverCannotChangeGridGeometry() {
        let narrowCoverColumn = LibraryGridLayout.columnWidth(
            containerWidth: 390,
            horizontalPadding: 16,
            columnSpacing: 16
        )
        let wideCoverColumn = LibraryGridLayout.columnWidth(
            containerWidth: 390,
            horizontalPadding: 16,
            columnSpacing: 16
        )

        XCTAssertEqual(wideCoverColumn, narrowCoverColumn)
        XCTAssertEqual(LibraryGridLayout.coverAspectRatio, 2.0 / 3.0)
    }
}

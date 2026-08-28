import CoreGraphics
import ReaderCore
import XCTest

final class AnnotationMenuPlacerTests: XCTestCase {
    private let container = CGRect(x: 0, y: 0, width: 393, height: 852)
    private let margin: CGFloat = 12
    private let gap: CGFloat = 10
    private let menu = CGSize(width: 320, height: 52)

    private func origin(anchor: CGRect?, menuSize: CGSize = CGSize(width: 320, height: 52)) -> CGPoint {
        AnnotationMenuPlacer.origin(anchor: anchor, menuSize: menuSize, container: container, margin: margin, gap: gap)
    }

    func testPrefersAboveTheAnchor() {
        let anchor = CGRect(x: 100, y: 400, width: 180, height: 24)
        let origin = origin(anchor: anchor)
        XCTAssertEqual(origin.y, anchor.minY - gap - menu.height)
    }

    func testFallsBackBelowWhenNoRoomAbove() {
        let anchor = CGRect(x: 100, y: 40, width: 180, height: 24)
        let origin = origin(anchor: anchor)
        XCTAssertEqual(origin.y, anchor.maxY + gap)
    }

    func testClampsTopWhenNeitherSideFits() {
        let anchor = CGRect(x: 100, y: 10, width: 180, height: 800)
        let origin = origin(anchor: anchor)
        XCTAssertEqual(origin.y, container.minY + margin)
    }

    func testPinsToTopWhenNeitherSideFits() {
        let anchor = CGRect(x: 100, y: 4, width: 180, height: 846)
        let origin = origin(anchor: anchor)
        XCTAssertEqual(origin.y, container.minY + margin)
    }

    func testCentersHorizontallyOnAnchor() {
        let anchor = CGRect(x: 150, y: 400, width: 90, height: 24)
        let origin = origin(anchor: anchor)
        XCTAssertEqual(origin.x, anchor.midX - menu.width / 2)
    }

    func testKeepsMenuInsideLeadingEdge() {
        let anchor = CGRect(x: 5, y: 400, width: 20, height: 24)
        let origin = origin(anchor: anchor)
        XCTAssertEqual(origin.x, margin)
    }

    func testKeepsMenuInsideTrailingEdge() {
        let anchor = CGRect(x: 370, y: 400, width: 20, height: 24)
        let origin = origin(anchor: anchor)
        XCTAssertEqual(origin.x, container.maxX - margin - menu.width)
    }

    func testDocksWithoutAnchor() {
        let origin = origin(anchor: nil)
        XCTAssertEqual(origin.x, container.midX - menu.width / 2)
        XCTAssertEqual(origin.y, container.maxY - margin - menu.height)
    }

    func testZeroSizeMenuReturnsContainerCenter() {
        let origin = origin(anchor: CGRect(x: 50, y: 50, width: 10, height: 10), menuSize: .zero)
        XCTAssertEqual(origin.x, container.midX)
        XCTAssertEqual(origin.y, container.midY)
    }

    func testHandleZonesSurroundSelectionEdges() {
        let selection = CGRect(x: 100, y: 300, width: 120, height: 80)
        let zones = AnnotationMenuPlacer.selectionHandleZones(around: selection, container: container)
        XCTAssertEqual(zones.count, 2)
        XCTAssertTrue(zones[0].maxY > selection.minY, "start zone should dip into the selection")
        XCTAssertTrue(zones[0].minY < selection.minY, "start handle sits above the selection")
        XCTAssertTrue(zones[1].minY < selection.maxY, "end zone should dip into the selection")
        XCTAssertTrue(zones[1].maxY > selection.maxY, "end handle sits below the selection")
    }

    func testHandleZonesDoNotEscapeTheContainer() {
        let selection = CGRect(x: 4, y: 6, width: 380, height: 840)
        let zones = AnnotationMenuPlacer.selectionHandleZones(around: selection, container: container)
        for zone in zones {
            XCTAssertTrue(container.contains(zone))
        }
    }

    func testCollapsedSelectionHasNoHandleZones() {
        let zones = AnnotationMenuPlacer.selectionHandleZones(around: CGRect.null, container: container)
        XCTAssertTrue(zones.isEmpty)
    }
}

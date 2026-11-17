import XCTest

/// Who owns the long press on a shelf cover.
///
/// The drag itself cannot be synthesized here: neither XCUITest's
/// hold-then-drag nor agent-device's `gesture drag` reaches the shelf's
/// long-press recognizer from a test process. It is verified on the simulator
/// by driving the app with `agent-device gesture drag`: swapping writes
/// `manualOrder`, and dropping on the compose button opens the removal alert.
/// What CI can assert is the gesture split that makes dragging safe — the long
/// press no longer opens the old delete menu and does not open the book, and a
/// plain tap still opens it.
final class LibraryReorderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-onboarding.hasCompleted", "YES", "-seed-library"]
        app.launch()
        XCTAssertTrue(app.buttons["书架"].waitForExistence(timeout: 90), "书架没有出现")
    }

    func testLongPressOnCoverNoLongerOpensDeleteMenu() throws {
        let cell = try gridBook()
        cell.press(forDuration: 1.0)

        XCTAssertFalse(
            app.buttons["从书架移除"].waitForExistence(timeout: 2),
            "网格长按仍弹出删除菜单；长按应属于拖拽"
        )
        XCTAssertFalse(
            app.webViews.firstMatch.waitForExistence(timeout: 2),
            "长按把书打开了；长按应只抬起封面"
        )
    }

    func testTapStillOpensTheBook() throws {
        let cell = try gridBook()
        cell.tap()

        XCTAssertTrue(
            app.webViews.firstMatch.waitForExistence(timeout: 10),
            "轻点封面没有打开书；拖拽手势抢走了轻点"
        )
    }

    /// The grid, not the current-reading row: the row is a single card outside
    /// the drag surface and keeps its context menu.
    private func gridBook() throws -> XCUIElement {
        let cells = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "测试作者"))
        guard cells.count > 1 else {
            throw XCTSkip("网格里少于两本书；先导入多本测试书")
        }
        return cells.element(boundBy: 1)
    }
}

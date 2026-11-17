import XCTest

/// Deleting a book from the current-reading row.
///
/// Grid covers no longer carry a context menu — their long press belongs to
/// drag-to-reorder and drag-to-delete (see `LibraryReorderUITests`). The row
/// above the grid sits outside that drag surface, so it keeps the menu and
/// remains the only reachable delete path for a one-book library.
final class LibraryInteractionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-onboarding.hasCompleted", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["书架"].waitForExistence(timeout: 60), "书架没有出现")
    }

    func testCurrentBookContextMenuOffersRemoval() throws {
        // The current book is the top row, not a grid cell; it must still be
        // removable, otherwise the last book in the library cannot be deleted.
        let book = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "阅读进度"))
            .firstMatch
        guard book.waitForExistence(timeout: 10) else {
            throw XCTSkip("书架没有书")
        }

        book.press(forDuration: 1.0)
        let remove = app.buttons["从书架移除"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "长按当前书没有出现“从书架移除”")
        XCTAssertFalse(app.webViews.firstMatch.exists, "长按把书打开了，而不是打开菜单")
    }

}

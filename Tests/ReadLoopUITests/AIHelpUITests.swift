import XCTest

/// Exercises the reader AI chain against the deterministic `-fake-provider`
/// client: streaming, stop, failure + retry, and the anti-spoiler notice.
/// No provider key or network is involved.
final class AIHelpUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-onboarding.hasCompleted", "YES"]
    }

    func testStreamingAnswerCanBeStopped() throws {
        launch(fakeProvider: "slow")
        try openHelpSheet()
        XCTAssertTrue(
            app.staticTexts["回答只使用这段原文和你已经读过的部分。"].waitForExistence(timeout: 5),
            "防剧透说明没有显示"
        )

        send("这句话到底在说什么")

        let stop = app.buttons["停止回答"]
        if !stop.waitForExistence(timeout: 10) {
            print("AI-AX:\n\(app.debugDescription)")
        }
        XCTAssertTrue(stop.exists, "流式回答开始后没有停止按钮")
        stop.tap()

        XCTAssertTrue(
            app.staticTexts["已停止"].waitForExistence(timeout: 10),
            "停止后没有进入已停止状态"
        )
    }

    func testFailedAnswerOffersRetry() throws {
        launch(fakeProvider: "failure")
        try openHelpSheet()
        send("这句话到底在说什么")

        let retry = app.buttons["重试"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15), "失败后没有重试入口")
        retry.tap()

        // The fake fails again; the retry path must stay reachable.
        XCTAssertTrue(app.buttons["重试"].waitForExistence(timeout: 15), "重试后重试入口消失")
    }

    func testCompletedAnswerRendersCitation() throws {
        launch()
        try openHelpSheet()
        send("这句话到底在说什么")

        // The fake streams `[E1]`, which the validator turns into a citation
        // superscript on the evidence card.
        XCTAssertTrue(
            app.otherElements["AI 回答"].waitForExistence(timeout: 20),
            "回答没有渲染"
        )

        // `[E1]` becomes a validated citation and an evidence row.
        let citation = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "来源 1"))
            .firstMatch
        XCTAssertTrue(citation.waitForExistence(timeout: 10), "引用没有生成证据来源")
        citation.tap()

        // The sheet collapses to a short detent and the reader confirms the
        // jump; the Q&A thread stays alive for follow-ups.
        XCTAssertTrue(
            app.staticTexts["已回到原文"].waitForExistence(timeout: 10),
            "引用跳转后没有回到原文"
        )
    }

    // MARK: - Helpers

    private func launch(fakeProvider: String? = nil) {
        if let fakeProvider {
            app.launchArguments += ["-fake-provider", fakeProvider]
        } else {
            app.launchArguments += ["-fake-provider"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["书架"].waitForExistence(timeout: 60), "书架没有出现")
    }

    private func openHelpSheet() throws {
        let book = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "阅读进度"))
            .firstMatch
        guard book.waitForExistence(timeout: 10) else {
            throw XCTSkip("书架没有书；先导入一本再跑 AI 链路用例")
        }
        book.tap()

        let page = app.webViews.firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 30), "阅读器没有打开")
        sleep(2)

        // Select on a real paragraph element rather than fixed coordinates:
        // with several books in the library the first one can have a short
        // page, and a coordinate press would land on empty space.
        let paragraphs = app.webViews.staticTexts
        let paragraph = paragraphs.element(boundBy: min(2, max(0, paragraphs.count - 1)))
        if paragraph.exists, paragraph.isHittable {
            paragraph.press(forDuration: 1.1)
        } else {
            let start = page.coordinate(withNormalizedOffset: CGVector(dx: 0.32, dy: 0.42))
            let end = page.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.42))
            start.press(forDuration: 1.1, thenDragTo: end)
        }

        let ask = app.buttons["就这段问 AI"]
        XCTAssertTrue(ask.waitForExistence(timeout: 15), "长按选句后没有出现问 AI 入口")
        ask.tap()

        XCTAssertTrue(app.staticTexts["问 AI"].waitForExistence(timeout: 10), "问答 Sheet 没有打开")
    }

    private func send(_ question: String) {
        let field =
            app.textViews.firstMatch.exists
            ? app.textViews.firstMatch
            : app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "找不到追问输入框")
        field.tap()
        field.typeText(question)

        let sendButton = app.buttons["发送追问"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5), "找不到发送按钮")
        sendButton.tap()
    }
}

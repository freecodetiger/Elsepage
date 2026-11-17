import XCTest

/// Runtime accessibility audits and performance baselines.
///
/// The app has no test-only launch hooks: onboarding is skipped through the
/// `UserDefaults` argument domain, which `OnboardingCompletionStore` already
/// reads.
final class ReadLoopUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-onboarding.hasCompleted", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 60), "App 未进入前台")
        XCTAssertTrue(app.buttons["书架"].waitForExistence(timeout: 30), "书架没有出现")
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Accessibility audits

    func testShelfAccessibilityAudit() throws {
        try audit("书架")
        try reportVisualDebt("书架")
    }

    func testThoughtsAccessibilityAudit() throws {
        selectTab("想法")
        try audit("想法")
        try reportVisualDebt("想法")
    }

    func testMyMindAccessibilityAudit() throws {
        selectTab("我的")
        try audit("我的")
        try reportVisualDebt("我的")
    }

    func testSettingsAccessibilityAudit() throws {
        app.buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 10), "设置页没有打开")
        try audit("设置")
        try reportVisualDebt("设置")
    }

    func testReaderAccessibilityAudit() throws {
        try openFirstBook()
        try audit("阅读器")
        try reportVisualDebt("阅读器")
    }

    // MARK: - Performance baselines

    func testLaunchPerformance() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            app.launch()
        }
    }

    func testReaderOpenPerformance() throws {
        let book = firstBook()
        guard book.waitForExistence(timeout: 10) else {
            throw XCTSkip(" 书架没有书；先导入一本再跑阅读器性能基线")
        }

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStop]
        // Same `os_signpost` the in-app diagnostics screen aggregates, so the
        // CI number and the Perf screen describe one measurement.
        let openMetric = XCTOSSignpostMetric(
            subsystem: "com.readloop.app",
            category: "perf",
            name: "readerOpen"
        )

        measure(metrics: [openMetric, XCTClockMetric(), XCTMemoryMetric()], options: options) {
            book.tap()
            _ = app.buttons["结束阅读并返回书架"].waitForExistence(timeout: 30)
            stopMeasuring()
            closeReader()
        }
    }

    // MARK: - Helpers

    private func selectTab(_ title: String) {
        let button = app.buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "找不到 Tab：\(title)")
        button.tap()
        sleep(1)
    }

    private func firstBook() -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "阅读进度"))
            .firstMatch
    }

    private func openFirstBook() throws {
        let book = firstBook()
        guard book.waitForExistence(timeout: 10) else {
            throw XCTSkip("书架没有书；先导入一本再跑阅读器审计")
        }
        book.tap()

        let close = app.buttons["结束阅读并返回书架"]
        if !close.waitForExistence(timeout: 15) {
            // Chrome auto-hides, so tap the page to bring it back before
            // deciding the reader failed to open.
            for offset in [CGVector(dx: 0.5, dy: 0.45), CGVector(dx: 0.5, dy: 0.3)] {
                app.coordinate(withNormalizedOffset: offset).press(forDuration: 0.08)
                if close.waitForExistence(timeout: 3) { break }
            }
        }
        if !close.exists {
            print("READER-AX:\n\(app.debugDescription)")
        }
        XCTAssertTrue(close.exists, "阅读器没有打开")
        sleep(2)
    }

    /// Ends the iteration without driving "结束阅读 → 反思" in between
    /// measurements: the end-of-session sheet would otherwise sit over the
    /// shelf and the next tap would miss.
    private func closeReader() {
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["书架"].waitForExistence(timeout: 30), "重启后没有回到书架")
    }

    /// Structural checks are gated: they are precise, and they catch the
    /// regressions this project actually shipped (a 16pt clear button).
    private func audit(_ screen: String) throws {
        do {
            try app.performAccessibilityAudit(for: [
                .hitRegion,
                .sufficientElementDescription,
            ]) { @Sendable issue in
                print(Self.describe(issue, screen: screen))
                return false
            }
        } catch {
            XCTFail("\(screen) 无障碍结构审计未通过：\(error.localizedDescription)")
        }
    }

    /// Contrast, clipping, and Dynamic Type findings are reported, not gated
    /// yet: SwiftUI's audit flags plain `Text` and system list headers as
    /// unsupported/clipped, and the remaining hits are the real secondary-text
    /// contrast debt tracked in docs/design/07-remaining-issues.md. Turning
    /// this into a hard gate needs the palette pass first.
    private func reportVisualDebt(_ screen: String) throws {
        do {
            try app.performAccessibilityAudit(for: [
                .contrast,
                .textClipped,
                .dynamicType,
            ]) { @Sendable issue in
                print(Self.describe(issue, screen: "\(screen)/visual"))
                return true
            }
        } catch {
            let attachment = XCTAttachment(string: error.localizedDescription)
            attachment.name = "\(screen)-visual-audit.txt"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private static func describe(_ issue: XCUIAccessibilityAuditIssue, screen: String) -> String {
        let label = issue.element?.label ?? "-"
        let identifier = issue.element?.identifier ?? "-"
        return "AUDIT [\(screen)] \(issue.compactDescription) "
            + "element=\(label) id=\(identifier) | \(issue.detailedDescription)"
    }
}

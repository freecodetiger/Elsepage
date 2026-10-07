import LibraryCore
import XCTest

/// The shelf claims "the chapter you are reading"; EPUB nav front matter stored
/// as a chapter would make that claim false.
final class ChapterTitleTests: XCTestCase {
    func testSkipsFrontMatterStoredFromTheEpubNavigation() {
        XCTAssertNil(ChapterTitle.readingChapter(in: ["总目录", nil, "   "]))
        XCTAssertNil(ChapterTitle.readingChapter(in: ["封面", "Contents"]))
    }

    func testPicksTheFirstRealChapterAndTrimsIt() {
        XCTAssertEqual(
            ChapterTitle.readingChapter(in: ["总目录", "第一章 银行家为什么破产"]),
            "第一章 银行家为什么破产"
        )
        XCTAssertEqual(ChapterTitle.readingChapter(in: [" 第三章 税 "]), "第三章 税")
    }

    func testMatchIsExactAfterTrimmingAndLowercasing() {
        XCTAssertTrue(ChapterTitle.isNavigational(" Cover "))
        XCTAssertTrue(ChapterTitle.isNavigational("TABLE OF CONTENTS"))
        XCTAssertFalse(ChapterTitle.isNavigational("总目录页"))
    }
}

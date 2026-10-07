import Foundation

/// Chapter titles come from the EPUB navigation document verbatim, so front
/// matter entries ("总目录", "封面") are stored as chapters like any other.
/// They are correct in the reader's table of contents — this filter is only for
/// the shelf, which claims "the chapter you are reading", a different assertion.
public enum ChapterTitle {
    private static let navigational: Set<String> = [
        "总目录", "目录", "封面", "扉页", "书名页", "版权页", "前言页",
        "contents", "table of contents", "cover", "title page", "copyright",
    ]

    public static func isNavigational(_ title: String) -> Bool {
        navigational.contains(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// The first title that actually names a chapter, or nil when the range
    /// covers only front matter (or has no titles at all).
    public static func readingChapter(in titles: [String?]) -> String? {
        titles
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !isNavigational($0) }
    }
}

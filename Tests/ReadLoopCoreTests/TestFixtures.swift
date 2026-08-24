import Foundation
import LibraryCore
import ReaderCore

enum TestFixtures {
    static var minimalEPUB: URL {
        #if SWIFT_PACKAGE
            Bundle.module.url(forResource: "minimal", withExtension: "epub", subdirectory: "Fixtures/EPUB")!
        #else
            Bundle(for: FixtureBundleToken.self).url(forResource: "minimal", withExtension: "epub")!
        #endif
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func book(fingerprint: String = "abc") -> Book {
        Book(fingerprint: .init(rawValue: fingerprint), title: "A Book", fileName: "book-\(UUID().uuidString).epub", fileSize: 3)
    }

    static func realisticLocator(progression: Double = 0.42, includeText: Bool = true) throws -> BookLocator {
        var object: [String: Any] = [
            "href": "EPUB/chapter.xhtml#readium-css-selector",
            "type": "application/xhtml+xml",
            "title": "A Small Beginning",
            "locations": [
                "progression": progression,
                "totalProgression": 0.73,
                "position": 8,
                "cssSelector": "body > p:nth-child(2)",
                "fragment": "readium-css-selector",
            ],
            "futureExtension": ["vendor": "readloop-test", "version": 99],
        ]
        if includeText {
            object["text"] = [
                "before": "A reader begins with ",
                "highlight": "a page",
                "after": ", returns with a thought.",
            ]
        }
        let json = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try BookLocator(
            json: json,
            href: "EPUB/chapter.xhtml#readium-css-selector",
            progression: progression,
            totalProgression: 0.73,
            textBefore: includeText ? "A reader begins with " : nil,
            textHighlight: includeText ? "a page" : nil,
            textAfter: includeText ? ", returns with a thought." : nil
        )
    }
}

private final class FixtureBundleToken {}

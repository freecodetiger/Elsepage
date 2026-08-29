import Foundation

/// One fixed evaluation sample (PRD §16): current book context, user history,
/// the reflection under test, the retrieval evidence available for the reply,
/// and human-written notes describing what a good response does.
///
/// Samples are JSON files under `Fixtures/BenchSamples/`. The schema is
/// documented in `Fixtures/BenchSamples/README.md`.
public struct BenchSample: Sendable {
    public let id: String
    public let category: String
    public let book: BenchBookContext
    public let currentLocator: BenchLocator?
    public let userHistory: BenchUserHistory
    public let currentReflection: String
    public let retrievalEvidence: [BenchEvidencePassage]
    public let expectedFeedbackNotes: [String]

    public init(
        id: String, category: String, book: BenchBookContext,
        currentLocator: BenchLocator?, userHistory: BenchUserHistory,
        currentReflection: String, retrievalEvidence: [BenchEvidencePassage],
        expectedFeedbackNotes: [String]
    ) {
        self.id = id
        self.category = category
        self.book = book
        self.currentLocator = currentLocator
        self.userHistory = userHistory
        self.currentReflection = currentReflection
        self.retrievalEvidence = retrievalEvidence
        self.expectedFeedbackNotes = expectedFeedbackNotes
    }
}

public struct BenchBookContext: Sendable {
    public let title: String
    public let author: String?
    public let chapter: String?
    /// Informational only — shown to human scorers, never sent to the model.
    /// The nearby passage the model sees comes from `currentLocator`.
    public let excerpt: String?
}

public struct BenchLocator: Sendable {
    public let href: String
    public let progression: Double?
    public let textBefore: String?
    public let textHighlight: String?
    public let textAfter: String?
}

public struct BenchPastReflection: Sendable {
    public let id: String?
    public let bookTitle: String?
    /// False → the past thought belongs to a different book (cross-book lane).
    public let sameBook: Bool
    /// Listed newest first; `createdAt` is derived deterministically from position.
    public let text: String
}

public struct BenchMemoryClaim: Sendable {
    public let kind: String?
    public let claim: String
}

public struct BenchEvidencePassage: Sendable {
    public let chapterTitle: String?
    public let sectionTitle: String?
    public let text: String
    public let href: String?
}

// MARK: - Decoding

private struct RawSample: Decodable {
    var id: String?
    var category: String?
    var book: RawBook?
    var currentLocator: RawLocator?
    var userHistory: RawHistory?
    var currentReflection: String?
    var retrievalEvidence: [RawPassage]?
    var expectedFeedbackNotes: [String]?

    struct RawBook: Decodable {
        var title: String?
        var author: String?
        var chapter: String?
        var excerpt: String?
    }
    struct RawLocator: Decodable {
        var href: String?
        var progression: Double?
        var textBefore: String?
        var textHighlight: String?
        var textAfter: String?
    }
    struct RawHistory: Decodable {
        var pastReflections: [RawPast]?
        var memoryClaims: [RawMemory]?
    }
    struct RawPast: Decodable {
        var id: String?
        var bookTitle: String?
        var sameBook: Bool?
        var text: String?
    }
    struct RawMemory: Decodable {
        var kind: String?
        var claim: String?
    }
    struct RawPassage: Decodable {
        var chapterTitle: String?
        var sectionTitle: String?
        var text: String?
        var href: String?
    }
}

public enum BenchSampleError: Error, Equatable, Sendable {
    case missingField(file: String, field: String)
    case invalidJSON(file: String)
    case emptyLocator(file: String)
    case duplicateID(String)
    case noSamplesFound(path: String)
    case invalidDirectory(path: String)

    public var message: String {
        switch self {
        case .missingField(let file, let field): "\(file): 缺少必填字段 \"\(field)\""
        case .invalidJSON(let file): "\(file): 不是合法的 JSON 对象"
        case .emptyLocator(let file): "\(file): currentLocator.href 不能为空"
        case .duplicateID(let id): "样本 id 重复: \(id)"
        case .noSamplesFound(let path): "样本目录中没有 *.json 样本: \(path)"
        case .invalidDirectory(let path): "样本目录不可读: \(path)"
        }
    }
}

/// Loads and validates `*.json` samples from a directory (sorted by file name,
/// so runs and reports are order-stable).
public enum BenchSampleLoader {
    public static func load(from directory: URL) throws -> [BenchSample] {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            throw BenchSampleError.invalidDirectory(path: directory.path)
        }
        guard !files.isEmpty else { throw BenchSampleError.noSamplesFound(path: directory.path) }

        var samples: [BenchSample] = []
        var seenIDs = Set<String>()
        for file in files {
            let sample = try decode(file)
            guard seenIDs.insert(sample.id).inserted else {
                throw BenchSampleError.duplicateID(sample.id)
            }
            samples.append(sample)
        }
        return samples
    }

    public static func decode(_ file: URL) throws -> BenchSample {
        let name = file.lastPathComponent
        guard let data = try? Data(contentsOf: file) else {
            throw BenchSampleError.invalidJSON(file: name)
        }
        let raw: RawSample
        do {
            raw = try JSONDecoder().decode(RawSample.self, from: data)
        } catch {
            throw BenchSampleError.invalidJSON(file: name)
        }
        guard let id = raw.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            throw BenchSampleError.missingField(file: name, field: "id")
        }
        guard let reflection = raw.currentReflection?.trimmingCharacters(in: .whitespacesAndNewlines), !reflection.isEmpty else {
            throw BenchSampleError.missingField(file: name, field: "currentReflection")
        }
        guard let bookTitle = raw.book?.title, !bookTitle.isEmpty else {
            throw BenchSampleError.missingField(file: name, field: "book.title")
        }
        if let locator = raw.currentLocator, (locator.href ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw BenchSampleError.emptyLocator(file: name)
        }

        let history = raw.userHistory
        return BenchSample(
            id: id,
            category: raw.category ?? "未分类",
            book: BenchBookContext(
                title: bookTitle,
                author: raw.book?.author,
                chapter: raw.book?.chapter,
                excerpt: raw.book?.excerpt
            ),
            currentLocator: raw.currentLocator.map {
                BenchLocator(
                    href: $0.href ?? "",
                    progression: $0.progression,
                    textBefore: $0.textBefore,
                    textHighlight: $0.textHighlight,
                    textAfter: $0.textAfter
                )
            },
            userHistory: BenchUserHistory(
                pastReflections: (history?.pastReflections ?? []).compactMap {
                    guard let text = $0.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
                    return BenchPastReflection(id: $0.id, bookTitle: $0.bookTitle, sameBook: $0.sameBook ?? true, text: text)
                },
                memoryClaims: (history?.memoryClaims ?? []).compactMap {
                    guard let claim = $0.claim?.trimmingCharacters(in: .whitespacesAndNewlines), !claim.isEmpty else { return nil }
                    return BenchMemoryClaim(kind: $0.kind, claim: claim)
                }
            ),
            currentReflection: reflection,
            retrievalEvidence: (raw.retrievalEvidence ?? []).compactMap {
                guard let text = $0.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
                return BenchEvidencePassage(chapterTitle: $0.chapterTitle, sectionTitle: $0.sectionTitle, text: text, href: $0.href)
            },
            expectedFeedbackNotes: raw.expectedFeedbackNotes ?? []
        )
    }
}

/// User history supplied by a sample: past reflections across books plus
/// long-term memory claims. Both are candidate material — the real routing and
/// retrievers decide what actually reaches the reply.
public struct BenchUserHistory: Sendable {
    public let pastReflections: [BenchPastReflection]
    public let memoryClaims: [BenchMemoryClaim]
}

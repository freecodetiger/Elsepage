import Foundation
import LibraryCore

/// Stable identity for a text range. Start and end locators are both part of the
/// identity; range equality must never depend on the visible excerpt alone.
public struct AnnotationRange: Hashable, Codable, Sendable {
    public let bookID: BookID
    public let resourceHref: String
    public let startLocator: BookLocator
    public let endLocator: BookLocator

    public init(
        bookID: BookID,
        resourceHref: String,
        startLocator: BookLocator,
        endLocator: BookLocator
    ) {
        self.bookID = bookID
        self.resourceHref = resourceHref
        self.startLocator = startLocator
        self.endLocator = endLocator
    }

    public var rangeKey: String {
        [
            bookID.description,
            Self.resourceIdentifier(resourceHref),
            startLocator.canonicalKey,
            endLocator.canonicalKey,
        ].joined(separator: "|")
    }

    public var isSingleResource: Bool {
        Self.resourceIdentifier(startLocator.href) == Self.resourceIdentifier(endLocator.href)
    }

    public func isExactSameRange(as other: AnnotationRange) -> Bool {
        rangeKey == other.rangeKey
    }

    /// Conservative overlap used for annotation conflict UI and highlight
    /// collision checks. It avoids claiming certainty when locators lack
    /// progression; false negatives are safer than destructive merges.
    public func appearsToOverlapText(with other: AnnotationRange) -> Bool {
        guard Self.resourceIdentifier(resourceHref) == Self.resourceIdentifier(other.resourceHref) else {
            return false
        }
        if isExactSameRange(as: other) { return true }

        let lhsText = Self.normalizedText(startLocator.textHighlight ?? endLocator.textHighlight)
        let rhsText = Self.normalizedText(other.startLocator.textHighlight ?? other.endLocator.textHighlight)
        let sameOrContainedText = !lhsText.isEmpty && !rhsText.isEmpty
            && (lhsText == rhsText || lhsText.contains(rhsText) || rhsText.contains(lhsText))

        if let lhsStart = startLocator.progression, let rhsStart = other.startLocator.progression {
            let distance = abs(lhsStart - rhsStart)
            guard distance <= 0.02 else { return false }
            return sameOrContainedText
        }
        return sameOrContainedText
    }

    private static func resourceIdentifier(_ href: String) -> String {
        href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
    }

    private static func normalizedText(_ text: String?) -> String {
        (text ?? "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .filter { !$0.isWhitespace }
    }
}

public struct HighlightLayer: Hashable, Codable, Sendable {
    public var color: HighlightColor
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        color: HighlightColor,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct NoteEntry: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public var body: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        body: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One annotation identity per exact AnnotationRange. Highlight and note layers are
/// independent; neither owns the other.
public struct TextAnnotation: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let range: AnnotationRange
    public var highlight: HighlightLayer?
    public var notes: [NoteEntry]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        range: AnnotationRange,
        highlight: HighlightLayer? = nil,
        notes: [NoteEntry] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.range = range
        self.highlight = highlight
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool {
        highlight == nil && notes.isEmpty
    }
}

public protocol TextAnnotationRepository: Sendable {
    func annotations(for bookID: BookID) async throws -> [TextAnnotation]
    func save(annotation: TextAnnotation) async throws
    func deleteAnnotation(id: UUID) async throws
}

import Foundation

public struct StructureAwareChunker: Sendable {
    public let targetCharacters: Int
    public let maximumCharacters: Int
    /// Characters shared between consecutive split parts, so a hard cut at
    /// `maximumCharacters` does not lose the sentence that spans the boundary.
    public let overlapCharacters: Int

    public init(targetCharacters: Int = 900, maximumCharacters: Int = 1_400, overlapCharacters: Int = 150) {
        precondition(targetCharacters > 0 && maximumCharacters >= targetCharacters)
        // Clamp so the split stride is never 0 (overlap >= max would loop forever).
        self.targetCharacters = targetCharacters; self.maximumCharacters = maximumCharacters
        self.overlapCharacters = Swift.max(0, Swift.min(overlapCharacters, maximumCharacters - 1))
    }

    public func chunks(from blocks: [BookTextBlock], indexVersion: Int) -> [BookChunk] {
        var groups: [[BookTextBlock]] = []
        var current: [BookTextBlock] = []
        var count = 0
        func flush() { if !current.isEmpty { groups.append(current); current = []; count = 0 } }

        for block in blocks.sorted(by: Self.order) where !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let first = current.first,
               (first.resourceHref != block.resourceHref || first.chapterID != block.chapterID || first.sectionID != block.sectionID) { flush() }
            let length = block.text.count
            if !current.isEmpty && count + 2 + length > maximumCharacters { flush() }
            if length > maximumCharacters {
                flush()
                groups.append(contentsOf: split(block).map { [$0] })
            } else {
                current.append(block); count += length + (current.count > 1 ? 2 : 0)
                if count >= targetCharacters { flush() }
            }
        }
        flush()
        return groups.enumerated().map { ordinal, group in makeChunk(group, ordinal: ordinal, version: indexVersion) }
    }

    private func split(_ block: BookTextBlock) -> [BookTextBlock] {
        var result: [BookTextBlock] = []
        // Sliding window: parts advance by (max - overlap) so consecutive parts
        // share the tail of the previous one. stride >= 1 via the overlap clamp.
        let stride = maximumCharacters - overlapCharacters
        var part = 0
        while part * stride < block.text.count {
            let start = block.text.index(block.text.startIndex, offsetBy: part * stride)
            let end = block.text.index(start, offsetBy: maximumCharacters, limitedBy: block.text.endIndex) ?? block.text.endIndex
            let text = String(block.text[start..<end])
            result.append(BookTextBlock(id: .init(rawValue: "\(block.id.rawValue):\(part)"), bookID: block.bookID,
                resourceHref: block.resourceHref, chapterID: block.chapterID, chapterTitle: block.chapterTitle,
                sectionID: block.sectionID, sectionTitle: block.sectionTitle, resourceOrdinal: block.resourceOrdinal,
                ordinal: block.ordinal * 10_000 + part, text: text, startLocator: block.startLocator, endLocator: block.endLocator))
            part += 1
        }
        return result
    }

    private func makeChunk(_ blocks: [BookTextBlock], ordinal: Int, version: Int) -> BookChunk {
        let first = blocks[0], last = blocks[blocks.count - 1]
        let key = "v\(version)|\(first.bookID)|\(first.resourceHref)|\(blocks.map(\.id.rawValue).joined(separator: ","))"
        return BookChunk(id: .init(rawValue: StableHash.fnv1a64(key)), bookID: first.bookID,
            resourceHref: first.resourceHref, chapterID: first.chapterID, chapterTitle: first.chapterTitle,
            sectionID: first.sectionID, sectionTitle: first.sectionTitle, resourceOrdinal: first.resourceOrdinal,
            ordinal: ordinal, text: blocks.map(\.text).joined(separator: "\n\n"),
            normalizedText: blocks.map(\.text).joined(separator: " ").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current),
            startLocator: first.startLocator, endLocator: last.endLocator, sourceBlockIDs: blocks.map(\.id))
    }

    private static func order(_ lhs: BookTextBlock, _ rhs: BookTextBlock) -> Bool {
        (lhs.resourceOrdinal, lhs.ordinal) < (rhs.resourceOrdinal, rhs.ordinal)
    }
}

enum StableHash {
    static func fnv1a64(_ string: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 { hash ^= UInt64(byte); hash &*= 1_099_511_628_211 }
        return String(format: "%016llx", hash)
    }
}

import Foundation

public struct StructureAwareChunker: Sendable {
    public let targetCharacters: Int
    public let maximumCharacters: Int
    /// Characters shared between consecutive split parts, so a hard cut at
    /// `maximumCharacters` does not lose the sentence that spans the boundary.
    public let overlapCharacters: Int
    /// Retrieval-child sizing (the small end of small-to-big). Children own FTS +
    /// embeddings; parents stay the context/evidence unit.
    public let childTargetCharacters: Int
    public let childMaximumCharacters: Int

    public init(targetCharacters: Int = 900, maximumCharacters: Int = 1_400, overlapCharacters: Int = 150,
                childTargetCharacters: Int = 350, childMaximumCharacters: Int = 600) {
        precondition(targetCharacters > 0 && maximumCharacters >= targetCharacters)
        precondition(childTargetCharacters > 0 && childMaximumCharacters >= childTargetCharacters)
        // Clamp so the split stride is never 0 (overlap >= max would loop forever).
        self.targetCharacters = targetCharacters; self.maximumCharacters = maximumCharacters
        self.overlapCharacters = Swift.max(0, Swift.min(overlapCharacters, maximumCharacters - 1))
        self.childTargetCharacters = childTargetCharacters; self.childMaximumCharacters = childMaximumCharacters
    }

    /// Emits parent chunks (the context/evidence unit) followed by their retrieval
    /// children (the small end of small-to-big). Children are derived from the same
    /// block groups as their parent, so oversized-block split parts are covered too.
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
                groups.append(contentsOf: split(block, maximum: maximumCharacters, overlap: overlapCharacters).map { [$0] })
            } else {
                current.append(block); count += length + (current.count > 1 ? 2 : 0)
                if count >= targetCharacters { flush() }
            }
        }
        flush()
        var result: [BookChunk] = []
        for (ordinal, group) in groups.enumerated() {
            let parent = makeChunk(group, ordinal: ordinal, version: indexVersion)
            result.append(parent)
            result.append(contentsOf: children(within: group, parent: parent, indexVersion: indexVersion))
        }
        return result
    }

    private func split(_ block: BookTextBlock, maximum: Int, overlap: Int) -> [BookTextBlock] {
        var result: [BookTextBlock] = []
        // Sliding window: parts advance by (max - overlap) so consecutive parts
        // share the tail of the previous one. stride >= 1 via the overlap clamp.
        let stride = maximum - overlap
        var part = 0
        while part * stride < block.text.count {
            let start = block.text.index(block.text.startIndex, offsetBy: part * stride)
            let end = block.text.index(start, offsetBy: maximum, limitedBy: block.text.endIndex) ?? block.text.endIndex
            let text = String(block.text[start..<end])
            result.append(BookTextBlock(id: .init(rawValue: "\(block.id.rawValue):\(part)"), bookID: block.bookID,
                resourceHref: block.resourceHref, chapterID: block.chapterID, chapterTitle: block.chapterTitle,
                sectionID: block.sectionID, sectionTitle: block.sectionTitle, resourceOrdinal: block.resourceOrdinal,
                ordinal: block.ordinal * 10_000 + part, text: text, startLocator: block.startLocator, endLocator: block.endLocator))
            part += 1
        }
        return result
    }

    /// Splits a parent's constituent blocks into retrieval children (~target
    /// chars each). Children stay inside the parent (no cross-parent windows) and
    /// carry deterministic content-addressed IDs. Oversized blocks are split with
    /// no overlap: the small-to-big expansion re-unites siblings inside the parent.
    public func children(within blocks: [BookTextBlock], parent: BookChunk, indexVersion: Int) -> [BookChunk] {
        let ordered = blocks.sorted(by: Self.order).filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var result: [BookChunk] = []
        var group: [BookTextBlock] = []
        var count = 0
        var childIndex = 0
        func flush() {
            guard !group.isEmpty else { return }
            result.append(makeChild(group, parent: parent, childIndex: childIndex, version: indexVersion))
            childIndex += 1
            group = []; count = 0
        }
        for block in ordered {
            let length = block.text.count
            if !group.isEmpty && count + 2 + length > childMaximumCharacters { flush() }
            if length > childMaximumCharacters {
                flush()
                for part in split(block, maximum: childMaximumCharacters, overlap: 0) {
                    result.append(makeChild([part], parent: parent, childIndex: childIndex, version: indexVersion))
                    childIndex += 1
                }
            } else {
                group.append(block); count += length + (group.count > 1 ? 2 : 0)
                if count >= childTargetCharacters { flush() }
            }
        }
        flush()
        return result
    }

    private func makeChild(_ blocks: [BookTextBlock], parent: BookChunk, childIndex: Int, version: Int) -> BookChunk {
        let first = blocks[0], last = blocks[blocks.count - 1]
        let key = "v\(version)|\(parent.bookID)|\(parent.resourceHref)|child|\(parent.id.rawValue)|\(childIndex)"
        return BookChunk(
            id: .init(rawValue: StableHash.fnv1a64(key)),
            bookID: parent.bookID, resourceHref: parent.resourceHref,
            chapterID: parent.chapterID, chapterTitle: parent.chapterTitle,
            sectionID: parent.sectionID, sectionTitle: parent.sectionTitle,
            resourceOrdinal: parent.resourceOrdinal,
            // Children share a resource with parents; base-10_000 offset (10_000 +
            // parent.ordinal * 10_000 + childIndex) keeps the
            // UNIQUE(bookID,indexVersion,resourceOrdinal,ordinal) key disjoint from
            // parent ordinals (0..P-1, P < 10_000).
            ordinal: 10_000 + parent.ordinal * 10_000 + childIndex,
            text: blocks.map(\.text).joined(separator: "\n\n"),
            normalizedText: blocks.map(\.text).joined(separator: " ").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current),
            startLocator: first.startLocator, endLocator: last.endLocator,
            sourceBlockIDs: blocks.map(\.id),
            role: .child, parentID: parent.id
        )
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

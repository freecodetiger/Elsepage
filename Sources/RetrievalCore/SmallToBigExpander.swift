import Foundation
import LibraryCore
import ReaderCore

/// The "big" half of small-to-big retrieval. Ranked children (the retrieval
/// unit) are grouped by parent and expanded into one parent-anchored context
/// window per parent (the context/evidence unit). Deterministic and
/// structure-bounded: expansion stays inside the parent, respects a character
/// budget, and re-checks the reading boundary so no future text leaks into the
/// evidence.
public struct SmallToBigExpander: Sendable {
    /// Per-window character budget for sibling accumulation (Chinese chars ≈ tokens).
    public let windowCharacterBudget: Int
    /// Max siblings to pull on each side of the anchor child.
    public let maxSiblingsPerSide: Int

    public init(windowCharacterBudget: Int = 1_200, maxSiblingsPerSide: Int = 3) {
        self.windowCharacterBudget = max(1, windowCharacterBudget)
        self.maxSiblingsPerSide = max(1, maxSiblingsPerSide)
    }

    /// Expands ranked children into one parent-anchored window per distinct parent,
    /// preserving the input order (score already descending). Children without a
    /// parent (pre-migration rows / test fixtures) pass through unchanged.
    public func expand(
        _ ranked: [(BookChunk, Double)],
        boundary: ReadingBoundary?,
        using repository: any BookIndexRepository,
        bookID: BookID,
        version: Int
    ) async throws -> [(BookChunk, Double)] {
        var windows: [(BookChunk, Double)] = []
        var seenParents = Set<BookChunkID>()
        for (child, score) in ranked {
            guard let parentID = child.parentID else {
                windows.append((child, score)) // tolerant pass-through
                continue
            }
            guard seenParents.insert(parentID).inserted else { continue } // one window per parent
            let siblings = try await repository.children(of: parentID, bookID: bookID, version: version)
            windows.append((try makeWindow(anchor: child, siblings: siblings, boundary: boundary, score: score), score))
        }
        return windows
    }

    private func makeWindow(anchor: BookChunk, siblings: [BookChunk], boundary: ReadingBoundary?, score: Double) throws -> BookChunk {
        let ordered = siblings.sorted { $0.ordinal < $1.ordinal }
        guard let anchorIndex = ordered.firstIndex(where: { $0.id == anchor.id }) else { return anchor }
        // Only siblings whose start lies within the boundary may join the window.
        let included = ordered.filter { boundary?.contains($0) ?? true }
        guard let anchorIncluded = included.firstIndex(where: { $0.id == anchor.id }) else { return anchor }

        var window: [BookChunk] = [included[anchorIncluded]]
        var budget = windowCharacterBudget - included[anchorIncluded].text.count
        var left = anchorIncluded - 1
        var right = anchorIncluded + 1
        var sides = 0
        while budget > 0, sides < maxSiblingsPerSide * 2, (left >= 0 || right < included.count) {
            let preferRight: Bool
            if right >= included.count { preferRight = false }
            else if left < 0 { preferRight = true }
            else { preferRight = included[right].ordinal - anchor.ordinal <= anchor.ordinal - included[left].ordinal }
            let candidate = preferRight ? included[right] : included[left]
            guard candidate.text.count <= budget else { break }
            if preferRight { window.append(candidate); right += 1 }
            else { window.insert(candidate, at: 0); left -= 1 }
            budget -= candidate.text.count
            sides += 1
        }

        let sortedWindow = window.sorted { $0.ordinal < $1.ordinal }
        // Re-check the tail: a sibling straddling the boundary end gets its future
        // portion trimmed (proportional approximation; children are small).
        let safeWindow = try sortedWindow.map { try trimmedToBoundary($0, boundary: boundary) }
        let first = safeWindow[0]
        let last = safeWindow[safeWindow.count - 1]
        return BookChunk(
            id: anchor.parentID ?? anchor.id,
            bookID: anchor.bookID, resourceHref: anchor.resourceHref,
            chapterID: anchor.chapterID, chapterTitle: anchor.chapterTitle,
            sectionID: anchor.sectionID, sectionTitle: anchor.sectionTitle,
            resourceOrdinal: anchor.resourceOrdinal, ordinal: anchor.ordinal,
            text: safeWindow.map(\.text).joined(separator: "\n\n"),
            normalizedText: safeWindow.map(\.text).joined(separator: " ").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current),
            startLocator: first.startLocator, endLocator: last.endLocator,
            sourceBlockIDs: safeWindow.flatMap(\.sourceBlockIDs),
            role: .parent, parentID: nil
        )
    }

    /// Trim a chunk's text to the portion before the boundary when its end
    /// progression crosses it. Approximates uniform text density within the small
    /// chunk (we have no per-character progression map at this layer).
    private func trimmedToBoundary(_ chunk: BookChunk, boundary: ReadingBoundary?) throws -> BookChunk {
        guard let boundary, chunk.resourceOrdinal == boundary.resourceOrdinal,
              let limit = boundary.progression,
              let start = chunk.startLocator.progression,
              let end = chunk.endLocator.progression,
              end > limit, end > start else { return chunk }
        let keepFraction = max(0, min(1, (limit - start) / (end - start)))
        let trimmedText = String(chunk.text.prefix(Int(Double(chunk.text.count) * keepFraction)))
        guard !trimmedText.isEmpty else { return chunk }
        // Clamp the semantic end progression to the boundary too, so `evidence.end
        // <= readingBoundary` holds on the locator as well as the content.
        let clampedEnd = try BookLocator(
            json: chunk.endLocator.json, href: chunk.endLocator.href,
            progression: limit, totalProgression: chunk.endLocator.totalProgression
        )
        return BookChunk(
            id: chunk.id, bookID: chunk.bookID, resourceHref: chunk.resourceHref,
            chapterID: chunk.chapterID, chapterTitle: chunk.chapterTitle,
            sectionID: chunk.sectionID, sectionTitle: chunk.sectionTitle,
            resourceOrdinal: chunk.resourceOrdinal, ordinal: chunk.ordinal,
            text: trimmedText,
            normalizedText: trimmedText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current),
            startLocator: chunk.startLocator, endLocator: clampedEnd,
            sourceBlockIDs: chunk.sourceBlockIDs, role: chunk.role, parentID: chunk.parentID
        )
    }
}

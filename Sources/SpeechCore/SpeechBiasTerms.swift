import Foundation

/// Pulls out the terms from book text that are worth biasing recognition toward.
///
/// The measured failure is a Latin-script word coming back as Chinese
/// homophones (`incentive` → `intent`, `Keynesian` → `Kenyon`), and a passage is
/// where that vocabulary comes from. Biasing only helps words that are already
/// in the list, so the list has to be built from what the reader is actually
/// looking at.
public enum SpeechBiasTerms {
    /// Measured: 22 entries cost nothing against 4 (`docs/testing/voice/2026-10-09-transcription-measurement.md`).
    /// 40 keeps headroom without walking into the unmeasured 22–100 range.
    public static let maximumTerms = 40

    /// Shorter runs are overwhelmingly function words (`of`, `to`, `is`) that
    /// earn no recognition value while spending bias budget.
    public static let minimumTermLength = 3

    /// The full bias list: `alwaysInclude` first, then whatever the highlighted
    /// passages contribute, truncated to `maximumTerms`.
    ///
    /// The ordering is the point. Title and author are always relevant — and are
    /// the entries the measurement actually moved — so a passage yielding more
    /// than the cap can never evict them. Callers supply the book fields; the
    /// ordering and the cap live here so they can be tested.
    public static func terms(
        alwaysInclude: [String],
        highlightedTexts: [String],
        limit: Int = maximumTerms
    ) -> [String] {
        let passageTerms = highlightedTexts.flatMap { latinTerms(in: $0, limit: limit) }
        return Array((alwaysInclude + passageTerms).prefix(limit))
    }

    /// Latin-script words in `text`, in the order they appear.
    ///
    /// Chinese terms are deliberately **not** extracted. Finding them needs word
    /// segmentation, and a naive character-run sweep would hand back most of the
    /// sentence — a list long enough to crowd out the terms that matter while
    /// adding nothing. The book title and author already cover the Chinese
    /// proper nouns that matter most.
    ///
    /// An English passage yields ordinary words (`that`, `with`). At the measured
    /// scale those are harmless, but they are why callers should keep the cap and
    /// put the always-relevant entries first rather than trusting the order here.
    public static func latinTerms(in text: String, limit: Int = maximumTerms) -> [String] {
        guard limit > 0 else { return [] }
        var terms: [String] = []
        var run = ""

        func flush() {
            defer { run = "" }
            // Trim the joiners a run can pick up at its edges — a trailing hyphen
            // in "well-" is not part of a term.
            let trimmed = run.trimmingCharacters(in: CharacterSet(charactersIn: "-'"))
            guard trimmed.count >= minimumTermLength,
                  trimmed.contains(where: isLatinLetter) else { return }
            terms.append(trimmed)
        }

        for character in text {
            if isTermCharacter(character) {
                run.append(character)
            } else {
                flush()
            }
        }
        flush()
        return Array(terms.prefix(limit))
    }

    /// Letters and ASCII digits of the Latin script, plus the two joiners that
    /// keep a real term in one piece (`post-modern`, `Man's`).
    private static func isTermCharacter(_ character: Character) -> Bool {
        if character == "-" || character == "'" { return true }
        guard character.isLetter || character.isNumber else { return false }
        return character.unicodeScalars.allSatisfy { $0.isASCII }
            || isLatinLetter(character)
    }

    /// Latin (and the neighbouring European blocks) sit far below the CJK, kana
    /// and Hangul ranges, which is what makes this a cheap discriminator.
    private static func isLatinLetter(_ character: Character) -> Bool {
        guard character.isLetter else { return false }
        return character.unicodeScalars.allSatisfy { $0.value < 0x0500 }
    }
}

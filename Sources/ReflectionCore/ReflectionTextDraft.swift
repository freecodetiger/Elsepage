import Foundation

/// Editable source text for one Reflection.
///
/// `originalText` is the user's current source of truth. `polishedText` is an
/// optional AI-derived version and never replaces what the user edits as the
/// original. Editing the original invalidates a previously generated polish so
/// stale AI output cannot be submitted alongside newer user text.
public struct ReflectionTextDraft: Equatable, Sendable {
    public enum Version: Equatable, Sendable {
        case original
        case polished
    }

    public private(set) var originalText: String
    public private(set) var polishedText: String?
    public private(set) var selectedVersion: Version
    public private(set) var revision: UInt64

    public init(
        originalText: String = "",
        polishedText: String? = nil,
        selectedVersion: Version = .original,
        revision: UInt64 = 0
    ) {
        self.originalText = originalText
        self.polishedText = polishedText
        self.selectedVersion = polishedText == nil ? .original : selectedVersion
        self.revision = revision
    }

    public var selectedText: String {
        switch selectedVersion {
        case .original: originalText
        case .polished: polishedText ?? originalText
        }
    }

    public var canSubmit: Bool {
        !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public mutating func updateSelectedText(_ text: String) {
        switch selectedVersion {
        case .original:
            updateOriginalText(text)
        case .polished:
            polishedText = text
            revision &+= 1
        }
    }

    public mutating func updateOriginalText(_ text: String) {
        guard originalText != text || polishedText != nil || selectedVersion != .original else {
            return
        }
        originalText = text
        polishedText = nil
        selectedVersion = .original
        revision &+= 1
    }

    public mutating func applyPolishedText(_ text: String) {
        guard !text.isEmpty else { return }
        polishedText = text
        selectedVersion = .polished
        revision &+= 1
    }

    public mutating func select(_ version: Version) {
        guard version != .polished || polishedText != nil else { return }
        selectedVersion = version
    }

    public mutating func clear() {
        guard !originalText.isEmpty || polishedText != nil else { return }
        originalText = ""
        polishedText = nil
        selectedVersion = .original
        revision &+= 1
    }

    /// Used by conversation follow-ups, where the selected text becomes the
    /// persisted user message before the draft is cleared.
    public mutating func takeSelectedTextForSending() -> String? {
        let text = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        clear()
        return text
    }
}

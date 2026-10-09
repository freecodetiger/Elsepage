import Foundation
import Speech

/// The one place recognition tuning lives.
///
/// The live-buffer path and any measurement harness both apply these values, so
/// what gets measured is what ships. Defaults reproduce the pre-existing
/// behavior exactly — adding this type changed no recognition setting on its own.
public struct SpeechRecognitionConfiguration: Sendable, Equatable {
    /// Biasing works for short phrases (names, terms), and an oversized list
    /// dilutes it, so entries are capped on both length and count.
    public static let maximumContextualStrings = 100
    public static let maximumContextualStringLength = 40

    public static let defaultLocaleIdentifier = "zh-CN"

    public var localeIdentifier: String
    /// Short phrases to bias the recognizer toward — book title, author, subject
    /// terms. This is the only lever against the Latin-script words that a
    /// single-locale recognizer otherwise renders as Chinese homophones: neither
    /// `SFSpeechRecognizer` nor `SpeechAnalyzer` recognizes mixed-language audio.
    public var contextualStrings: [String]
    public var taskHint: SFSpeechRecognitionTaskHint
    public var addsPunctuation: Bool
    public var shouldReportPartialResults: Bool
    /// On by default, so recognition never leaves the device: the app's
    /// local-first promise holds, no book text is sent to Apple, and
    /// `contextualStrings` cannot become an undisclosed outbound channel.
    ///
    /// The measured accuracy cost was nil on the five-clip sample (see
    /// `docs/testing/voice/2026-10-09-transcription-measurement.md`), but that
    /// sample was short, quiet and single-speaker — long, noisy or accented
    /// audio is where on-device models usually trail.
    ///
    /// A missing on-device model reports a clear failure instead of quietly
    /// uploading the audio. See `SpeechProviderError.onDeviceModelUnavailable`.
    public var requiresOnDeviceRecognition: Bool

    public init(
        localeIdentifier: String = SpeechRecognitionConfiguration.defaultLocaleIdentifier,
        contextualStrings: [String] = [],
        taskHint: SFSpeechRecognitionTaskHint = .unspecified,
        addsPunctuation: Bool = true,
        shouldReportPartialResults: Bool = true,
        requiresOnDeviceRecognition: Bool = true
    ) {
        self.localeIdentifier = localeIdentifier
        self.contextualStrings = Self.normalized(contextualStrings)
        self.taskHint = taskHint
        self.addsPunctuation = addsPunctuation
        self.shouldReportPartialResults = shouldReportPartialResults
        self.requiresOnDeviceRecognition = requiresOnDeviceRecognition
    }

    /// Contextual strings have to be short, distinct phrases. A long entry (a
    /// whole paragraph handed in by mistake) and a duplicate both spend bias
    /// budget without earning any, so they are dropped rather than passed on.
    /// Order is preserved so a caller can rank its sources.
    static func normalized(_ strings: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for raw in strings {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= maximumContextualStringLength else { continue }
            guard seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
            if result.count == maximumContextualStrings { break }
        }
        return result
    }

    /// Applies to either request type — `SFSpeechAudioBufferRecognitionRequest`
    /// for live audio, `SFSpeechURLRecognitionRequest` for file measurement.
    public func apply(to request: SFSpeechRecognitionRequest) {
        request.shouldReportPartialResults = shouldReportPartialResults
        request.addsPunctuation = addsPunctuation
        request.taskHint = taskHint
        request.requiresOnDeviceRecognition = requiresOnDeviceRecognition
        // Assigning an empty list is not equivalent to leaving the property alone
        // on every OS version, and there is nothing to gain from it.
        if !contextualStrings.isEmpty {
            request.contextualStrings = contextualStrings
        }
    }
}

import Foundation
import Speech

/// Whether recognition can actually start for a given configuration.
///
/// This exists so the UI (which decides whether to offer a microphone at all)
/// and the provider (which decides whether to start) share one rule and cannot
/// disagree. A microphone that is offered but fails on tap is worse than no
/// microphone, and the reverse — hiding a feature that works — is worse still.
public enum SpeechRecognitionAvailability: Equatable, Sendable {
    case available
    /// No usable recognizer for the locale at all.
    case unavailable(localeIdentifier: String)
    /// The locale's on-device model is not installed, and this configuration
    /// requires one.
    ///
    /// Note that `supportsOnDeviceRecognition` is a capability check, not proof
    /// that the asset is installed: it can report `true` while recognition still
    /// fails. So this is the common case, not the only one — `SpeechProviderError.from`
    /// catches the rest by classifying the framework's own error.
    case onDeviceModelMissing(localeIdentifier: String)

    public var isAvailable: Bool { self == .available }

    /// The rule, stated once. Both callers route through here.
    ///
    /// Deliberately does not consider microphone or speech authorization: those
    /// are requested on demand and a denied permission is something the user can
    /// change, so treating it as unavailability would hide the feature forever.
    public static func evaluate(
        recognizer: SFSpeechRecognizer?,
        configuration: SpeechRecognitionConfiguration
    ) -> SpeechRecognitionAvailability {
        guard let recognizer, recognizer.isAvailable else {
            return .unavailable(localeIdentifier: configuration.localeIdentifier)
        }
        if configuration.requiresOnDeviceRecognition, !recognizer.supportsOnDeviceRecognition {
            return .onDeviceModelMissing(localeIdentifier: configuration.localeIdentifier)
        }
        return .available
    }
}

public extension SpeechRecognitionConfiguration {
    /// Asks the system right now.
    ///
    /// Never cached: iOS installs on-device models in the background, so this
    /// answer changes while the app is running. Callers should re-ask on each
    /// appearance rather than storing the result.
    var availability: SpeechRecognitionAvailability {
        SpeechRecognitionAvailability.evaluate(
            recognizer: SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
            configuration: self
        )
    }
}

public extension SpeechRecognitionAvailability {
    /// The one line to show the user for this state, or nil when it is usable.
    ///
    /// Routes through `SpeechProviderError` so the inline hint and the error a
    /// failed recording would raise cannot drift apart.
    var message: String? {
        switch self {
        case .available:
            return nil
        case .unavailable:
            // No locale in the copy: there is nothing the user can do about a
            // missing recognizer, so naming the language would only add noise.
            return SpeechProviderError.recognitionUnavailable.errorDescription
        case .onDeviceModelMissing(let localeIdentifier):
            return SpeechProviderError.onDeviceModelUnavailable(localeIdentifier).errorDescription
        }
    }
}

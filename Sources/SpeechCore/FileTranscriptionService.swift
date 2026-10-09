import Foundation
import Speech

/// Transcribes an already-recorded audio file under a given configuration.
///
/// This exists to make recognition quality *measurable* rather than felt. The
/// live path can only ever be judged from a fresh utterance, so a before/after
/// comparison of a setting would confound the setting with the speaker saying
/// the phrase differently the second time. Re-running an unchanged clip holds
/// the audio fixed, which is the only way to attribute a difference to the
/// configuration.
public struct FileTranscriptionService: Sendable {
    public init() {}

    /// Returns the final transcript. Apple caps server-based recognition of a
    /// single request at roughly a minute of audio; this path takes the final
    /// result only and treats an error as a failed measurement rather than
    /// salvaging partial text.
    public func transcribe(
        _ url: URL,
        configuration: SpeechRecognitionConfiguration
    ) async throws -> String {
        let locale = Locale(identifier: configuration.localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechProviderError.recognitionUnavailable
        }
        // Checked up front: otherwise the request fails later with an opaque
        // Apple error, and a measurement run would look like a mystery rather
        // than a missing model.
        switch SpeechRecognitionAvailability.evaluate(recognizer: recognizer, configuration: configuration) {
        case .available:
            break
        case .unavailable:
            throw SpeechProviderError.recognitionUnavailable
        case .onDeviceModelMissing(let localeIdentifier):
            throw SpeechProviderError.onDeviceModelUnavailable(localeIdentifier)
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        configuration.apply(to: request)

        // The result handler fires repeatedly — once per partial, then once for
        // the final result or an error. Only a callback carrying a verdict may
        // settle the continuation, and only the first such callback may do so;
        // resuming a `CheckedContinuation` twice traps.
        let settled = OnceFlag()
        let task = SFSpeechRecognitionTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let recognition = recognizer.recognitionTask(with: request) { result, error in
                    let verdict: Result<String, Error>?
                    if let result, result.isFinal {
                        verdict = .success(result.bestTranscription.formattedString)
                    } else if let error {
                        // Classified rather than passed through raw: the
                        // capability check above misses the case where the
                        // system reports support but the asset is absent.
                        verdict = .failure(SpeechProviderError.from(error, configuration: configuration))
                    } else {
                        verdict = nil
                    }
                    guard let verdict, settled.claim() else { return }
                    continuation.resume(with: verdict)
                }
                task.set(recognition)
            }
        } onCancel: {
            // `cancel()` delivers an error to the handler, which settles the
            // continuation. Nothing else is needed here.
            task.cancel()
        }
    }
}

/// Lets exactly one caller win, however many callbacks arrive and in whatever
/// order.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

/// Holds the recognition task so `onCancel` can reach it. Cancellation can race
/// the task being installed, so a cancel that arrives first is replayed.
private final class SFSpeechRecognitionTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: SFSpeechRecognitionTask?
    private var cancelled = false

    func set(_ task: SFSpeechRecognitionTask) {
        lock.lock()
        let alreadyCancelled = cancelled
        if !alreadyCancelled { self.task = task }
        lock.unlock()
        if alreadyCancelled { task.cancel() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }
}

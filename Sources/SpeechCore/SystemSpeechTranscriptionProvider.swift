#if os(iOS)
import AVFAudio
import Foundation
import Speech

/// Apple system Speech adapter. The app streams audio without persisting an audio file.
@MainActor
public final class SystemSpeechTranscriptionProvider: LiveTranscriptionProvider {
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    public init() {}

    public var authorizationStatus: SpeechAuthorization {
        let speech = Self.map(SFSpeechRecognizer.authorizationStatus())
        let microphone = AVAudioSession.sharedInstance().recordPermission
        if microphone == .denied { return .denied }
        return speech
    }

    public var isAvailable: Bool {
        SFSpeechRecognizer()?.isAvailable == true
    }

    public func requestAuthorization() async -> SpeechAuthorization {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: Self.map(status))
            }
        }
        guard speech == .authorized else { return speech }
        let microphone = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        return microphone ? .authorized : .denied
    }

    public func start(localeIdentifier: String?) throws -> AsyncThrowingStream<TranscriptionEvent, Error> {
        cancel()
        let recognizer = localeIdentifier.map { SFSpeechRecognizer(locale: Locale(identifier: $0)) } ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else { throw SpeechProviderError.recognitionUnavailable }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw SpeechProviderError.recordingCouldNotStart(error.localizedDescription)
        }

        self.recognizer = recognizer
        recognitionRequest = request
        return AsyncThrowingStream { continuation in
            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal == true
                let failure = error?.localizedDescription
                Task { @MainActor [weak self] in
                    if let text {
                        continuation.yield(isFinal ? .final(text) : .partial(text))
                    }
                    if isFinal {
                        self?.finishAudio()
                        continuation.finish()
                    } else if let failure {
                        self?.finishAudio()
                        continuation.finish(throwing: SpeechProviderError.recordingCouldNotStart(failure))
                    }
                }
            }
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor [weak self] in self?.cancel() }
            }
        }
    }

    public func stop() {
        guard audioEngine.isRunning else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
    }

    public func cancel() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        finishAudio()
    }

    private func finishAudio() {
        recognitionTask = nil
        recognitionRequest = nil
        recognizer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func map(_ status: SFSpeechRecognizerAuthorizationStatus) -> SpeechAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .authorized: .authorized
        @unknown default: .restricted
        }
    }
}
#endif

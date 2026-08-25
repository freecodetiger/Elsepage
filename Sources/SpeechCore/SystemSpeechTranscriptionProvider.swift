#if os(iOS)
import AVFAudio
import AVFoundation
import CoreMedia
import Foundation
import Speech

/// Apple system Speech adapter. Streams audio to Speech and, when requested via
/// `prepareAudioRecording(at:)`, mirrors the input buffers to an `.caf` file so the
/// reflection can optionally keep the raw recording.
@MainActor
public final class SystemSpeechTranscriptionProvider: LiveTranscriptionProvider {
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    private var audioDestination: URL?
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?

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

    public func prepareAudioRecording(at url: URL?) throws {
        finishAudioWriter()
        audioDestination = url
    }

    public func start(localeIdentifier: String?) throws -> AsyncThrowingStream<TranscriptionEvent, Error> {
        cancel()
        let recognizer = localeIdentifier.map { SFSpeechRecognizer(locale: Locale(identifier: $0)) } ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else { throw SpeechProviderError.recognitionUnavailable }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let audioInput = makeAudioWriterInput(for: format, at: audioDestination)
        var lastPTS = CMTime.zero
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
            guard let audioInput, audioInput.isReadyForMoreMediaData,
                  let sample = Self.makeSampleBuffer(from: buffer, at: lastPTS) else { return }
            audioInput.append(sample)
            lastPTS = CMTimeAdd(
                lastPTS,
                CMTime(value: CMTimeValue(buffer.frameLength), timescale: CMTimeScale(buffer.format.sampleRate))
            )
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            finishAudioWriter()
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
        finishAudioWriter()
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
        finishAudioWriter()
        recognitionTask = nil
        recognitionRequest = nil
        recognizer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Sets up an AVAssetWriter mirroring the mic buffers to a `.caf` file, or returns nil
    /// (best-effort: audio persistence failing never blocks transcription).
    private func makeAudioWriterInput(for format: AVAudioFormat, at destination: URL?) -> AVAssetWriterInput? {
        guard let destination else { return nil }
        do {
            let writer = try AVAssetWriter(outputURL: destination, fileType: .caf)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: format.settings)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { return nil }
            writer.add(input)
            guard writer.startWriting() else { return nil }
            writer.startSession(atSourceTime: .zero)
            assetWriter = writer
            assetWriterInput = input
            return input
        } catch {
            return nil
        }
    }

    private func finishAudioWriter() {
        guard let writer = assetWriter else { return }
        assetWriterInput?.markAsFinished()
        if writer.status == .writing {
            writer.finishWriting { }
        }
        assetWriter = nil
        assetWriterInput = nil
    }

    nonisolated private static func makeSampleBuffer(from buffer: AVAudioPCMBuffer, at presentationTime: CMTime) -> CMSampleBuffer? {
        guard let formatDescription = buffer.format.formatDescription else { return nil }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(buffer.format.sampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var out: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithAudioBufferPCMData(
            allocator: kCFAllocatorDefault,
            audioBufferList: buffer.audioBufferList,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(buffer.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &out
        )
        return status == noErr ? out : nil
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

#if os(iOS)
import AVFAudio
import AVFoundation
import CoreMedia
import Foundation
import Speech

/// Apple system Speech adapter. Streams audio to Speech and, when requested via
/// `prepareAudioRecording(at:)`, mirrors the input buffers to an encoded audio
/// file (MP3 on real devices, AAC on the simulator which has no MP3 encoder).
@MainActor
public final class SystemSpeechTranscriptionProvider: LiveTranscriptionProvider {
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    private var audioDestination: URL?
    private var extAudioFile: ExtAudioFileRef?

    /// Extension the recorder should use for the audio destination file.
    public var preferredAudioFileExtension: String { Self.canEncodeMP3 ? "mp3" : "m4a" }

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

        // Configure and activate the audio session BEFORE touching the engine's
        // input node. On a real device the input format is not determined until
        // the session is active; calling `outputFormat(forBus:)`/`installTap`
        // first yields a zero-rate format and crashes with EXC_BAD_ACCESS
        // (simulator is lenient, which is why this only reproduced on-device).
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            audioEngine.prepare()
        } catch {
            throw SpeechProviderError.recordingCouldNotStart(error.localizedDescription)
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechProviderError.recordingCouldNotStart("麦克风输入格式不可用")
        }
        if let destination = audioDestination {
            extAudioFile = makeExtAudioFile(at: destination, inputFormat: format)
        }
        let writer = extAudioFile
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
            // Best-effort audio persistence; failure never blocks transcription.
            if let writer { ExtAudioFileWriteAsync(writer, buffer.frameLength, buffer.audioBufferList) }
        }

        do {
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

    private func finishAudioWriter() {
        // ExtAudioFile flushes and finalizes the encoded file on dispose.
        if let extAudioFile { ExtAudioFileDispose(extAudioFile) }
        self.extAudioFile = nil
    }

    /// Wraps the mic PCM buffers into an encoded file. MP3 on real devices
    /// (44.1 kHz hardware encoder), AAC (.m4a) on the simulator. ExtAudioFile
    /// performs the client→file sample-rate/channel conversion.
    private func makeExtAudioFile(at url: URL, inputFormat: AVAudioFormat) -> ExtAudioFileRef? {
        let isMP3 = url.pathExtension.lowercased() == "mp3"
        let formatID: AudioFormatID = isMP3 ? kAudioFormatMPEGLayer3 : kAudioFormatMPEG4AAC
        let fileType: AudioFileTypeID = isMP3 ? kAudioFileMP3Type : kAudioFileM4AType
        let clientPtr = inputFormat.streamDescription
        var clientFormat = clientPtr.pointee
        let channels = max(1, min(Int(clientFormat.mChannelsPerFrame), 2))
        var fileDesc = AudioStreamBasicDescription(
            mSampleRate: 44_100,
            mFormatID: formatID,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 0,
            mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 0,
            mReserved: 0
        )
        var ext: ExtAudioFileRef?
        guard ExtAudioFileCreateWithURL(url as CFURL, fileType, &fileDesc, nil, AudioFileFlags.eraseFile.rawValue, &ext) == noErr,
              let ext else { return nil }
        let setStatus = ExtAudioFileSetProperty(
            ext,
            kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            &clientFormat
        )
        guard setStatus == noErr else {
            ExtAudioFileDispose(ext)
            return nil
        }
        return ext
    }

    private static var canEncodeMP3: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
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

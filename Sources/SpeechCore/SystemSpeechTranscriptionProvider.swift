#if os(iOS)
import AVFAudio
import AVFoundation
import CoreMedia
import Foundation
import OSLog
import Speech

/// Apple system Speech adapter. Streams audio to Speech and, when requested via
/// `prepareAudioRecording(at:)`, mirrors the input buffers to an encoded audio
/// file (MP3 on real devices, AAC on the simulator which has no MP3 encoder).
@MainActor
public final class SystemSpeechTranscriptionProvider: LiveTranscriptionProvider {
    private nonisolated static let defaultLocaleIdentifier = "zh-CN"
    private nonisolated static let permissionTimeout: Duration = .seconds(8)
    private nonisolated static let permissionLogger = Logger(subsystem: "com.readloop.reader", category: "SpeechPermission")

    // AVAudioEngine can retain an empty graph after an audio route changes.
    // Recreate it for every recording so a stopped engine is never reused.
    private var audioEngine: AVAudioEngine?
    private var inputTapInstalled = false
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var activeRecordingID: UUID?

    private var audioDestination: URL?
    private var extAudioFile: ExtAudioFileRef?

    /// Extension the recorder should use for the audio destination file.
    public var preferredAudioFileExtension: String { Self.canEncodeMP3 ? "mp3" : "m4a" }

    public init() {}

    public var authorizationStatus: SpeechAuthorization {
        let speech = Self.map(SFSpeechRecognizer.authorizationStatus())
        let microphone = AVAudioSession.sharedInstance().recordPermission
        // Speech and microphone are independent permissions. Treat an
        // undetermined microphone permission as undetermined even when Speech
        // is already authorized, so start() waits for the mic prompt to finish
        // before touching AVAudioEngine.
        if microphone == .denied { return .denied }
        if microphone == .undetermined { return .notDetermined }
        return speech
    }

    public var isAvailable: Bool {
        SFSpeechRecognizer(locale: Locale(identifier: Self.defaultLocaleIdentifier))?.isAvailable == true
    }

    public func requestAuthorization() async -> SpeechAuthorization {
        Self.permissionLogger.info("[VOICE_PERMISSION] request started")
        let speech: SpeechAuthorization
        if Self.map(SFSpeechRecognizer.authorizationStatus()) == .notDetermined {
            guard let resolved = await awaitPermission(kind: "speech") else {
                Self.permissionLogger.error("[VOICE_PERMISSION] speech request timed out")
                return .denied
            }
            speech = resolved
        } else {
            speech = Self.map(SFSpeechRecognizer.authorizationStatus())
            Self.permissionLogger.info("[VOICE_PERMISSION] speech already resolved: \(String(describing: speech), privacy: .public)")
        }
        guard speech == .authorized else {
            Self.permissionLogger.info("[VOICE_PERMISSION] finished: speech=\(String(describing: speech), privacy: .public)")
            return speech
        }
        let microphone: Bool
        if AVAudioSession.sharedInstance().recordPermission == .undetermined {
            guard let resolved = await awaitPermission(kind: "microphone") else {
                Self.permissionLogger.error("[VOICE_PERMISSION] microphone request timed out")
                return .denied
            }
            microphone = resolved == .authorized
        } else {
            microphone = AVAudioSession.sharedInstance().recordPermission == .granted
            Self.permissionLogger.info("[VOICE_PERMISSION] microphone already resolved: \(microphone, privacy: .public)")
        }
        let result: SpeechAuthorization = microphone ? .authorized : .denied
        Self.permissionLogger.info("[VOICE_PERMISSION] finished: speech=authorized microphone=\(microphone, privacy: .public) result=\(String(describing: result), privacy: .public)")
        return result
    }

    private nonisolated func awaitPermission(kind: String) async -> SpeechAuthorization? {
        await withTaskGroup(of: SpeechAuthorization?.self, returning: SpeechAuthorization?.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    Self.permissionLogger.info("[VOICE_PERMISSION] \(kind, privacy: .public) request dispatched")
                    if kind == "speech" {
                        SFSpeechRecognizer.requestAuthorization { status in
                            let resolved = Self.map(status)
                            Self.permissionLogger.info("[VOICE_PERMISSION] speech callback: \(String(describing: resolved), privacy: .public)")
                            continuation.resume(returning: resolved)
                        }
                    } else {
                        AVAudioSession.sharedInstance().requestRecordPermission { granted in
                            Self.permissionLogger.info("[VOICE_PERMISSION] microphone callback: \(granted, privacy: .public)")
                            continuation.resume(returning: granted ? .authorized : .denied)
                        }
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: Self.permissionTimeout)
                Self.permissionLogger.error("[VOICE_PERMISSION] \(kind, privacy: .public) timeout after 8s")
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    public func prepareAudioRecording(at url: URL?) throws {
        finishAudioWriter()
        audioDestination = url
    }

    public func start(localeIdentifier: String?) throws -> AsyncThrowingStream<TranscriptionEvent, Error> {
        cancel()
        let locale = Locale(identifier: localeIdentifier ?? Self.defaultLocaleIdentifier)
        let recognizer = SFSpeechRecognizer(locale: locale)
        guard let recognizer, recognizer.isAvailable else { throw SpeechProviderError.recognitionUnavailable }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        // Configure and activate the audio session before creating the engine.
        // On a real device the input route may be absent even when permission is
        // authorized. AVAudioEngine.prepare() raises an uncaught NSException
        // when its graph has neither an input nor an output node, so this must be
        // checked before touching the engine.
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            finishAudio()
            throw SpeechProviderError.recordingCouldNotStart(error.localizedDescription)
        }

        guard session.isInputAvailable,
              session.inputNumberOfChannels > 0,
              !session.currentRoute.inputs.isEmpty else {
            finishAudio()
            throw SpeechProviderError.recordingCouldNotStart("麦克风输入路由不可用，请检查麦克风权限或音频设备后重试")
        }

        let engine = AVAudioEngine()
        audioEngine = engine
        // AVAudioEngine creates its singleton nodes lazily when they are first
        // accessed. Access the input node before prepare(), otherwise a record-
        // only engine has an empty graph and prepare() raises an NSException.
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            finishAudio()
            throw SpeechProviderError.recordingCouldNotStart("麦克风输入格式不可用")
        }
        engine.prepare()
        if let destination = audioDestination {
            extAudioFile = makeExtAudioFile(at: destination, inputFormat: format)
        }
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format,
            block: Self.makeInputTap(request: request, writer: extAudioFile)
        )
        inputTapInstalled = true

        do {
            try engine.start()
        } catch {
            finishAudio()
            throw SpeechProviderError.recordingCouldNotStart(error.localizedDescription)
        }

        self.recognizer = recognizer
        recognitionRequest = request
        let recordingID = UUID()
        activeRecordingID = recordingID
        return AsyncThrowingStream { continuation in
            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal == true
                let failure = error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self, self.activeRecordingID == recordingID else { return }
                    if let text {
                        continuation.yield(isFinal ? .final(text) : .partial(text))
                    }
                    if isFinal {
                        self.finishAudio()
                        continuation.finish()
                    } else if let failure {
                        self.finishAudio()
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
        guard let audioEngine, audioEngine.isRunning else { return }
        audioEngine.stop()
        removeInputTap(from: audioEngine)
        recognitionRequest?.endAudio()
        finishAudioWriter()
    }

    public func cancel() {
        stopAudioEngine()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        finishAudio()
    }

    private func finishAudio() {
        stopAudioEngine()
        finishAudioWriter()
        recognitionTask = nil
        recognitionRequest = nil
        recognizer = nil
        activeRecordingID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func stopAudioEngine() {
        guard let audioEngine else { return }
        if audioEngine.isRunning { audioEngine.stop() }
        removeInputTap(from: audioEngine)
        self.audioEngine = nil
    }

    private func removeInputTap(from audioEngine: AVAudioEngine) {
        guard inputTapInstalled else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        inputTapInstalled = false
    }

    /// AVAudioNode invokes taps on its realtime audio queue, not on MainActor.
    /// Keep this factory nonisolated so Swift does not insert an executor check
    /// into the callback created by the MainActor-isolated provider.
    private nonisolated static func makeInputTap(
        request: SFSpeechAudioBufferRecognitionRequest,
        writer: ExtAudioFileRef?
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
            // Best-effort audio persistence; failure never blocks transcription.
            if let writer { ExtAudioFileWriteAsync(writer, buffer.frameLength, buffer.audioBufferList) }
        }
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

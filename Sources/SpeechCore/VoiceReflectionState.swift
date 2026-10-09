import Foundation

public enum SpeechAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

public enum TranscriptionEvent: Equatable, Sendable {
    case partial(String)
    case final(String)
}

public enum VoiceReflectionPhase: Equatable, Sendable {
    case idle
    case requestingPermission
    case recording
    case stopping
    case transcriptReady
    case cancelled
    case failed
}

public enum VoiceReflectionAction: Equatable, Sendable {
    case requestRecording
    case permissionResolved(SpeechAuthorization)
    case recordingStarted
    case transcription(TranscriptionEvent)
    case stopRequested
    case cancelled
    case failed(String)
    case reset
}

/// Pure state used by the UI and independently testable without Speech or AVFoundation.
/// `transcript` is only an editable draft; saving it as source-of-truth is a separate action.
public struct VoiceReflectionState: Equatable, Sendable {
    public private(set) var phase: VoiceReflectionPhase = .idle
    public private(set) var transcript = ""
    public private(set) var failureMessage: String?
    /// Whether a voice reflection should also persist the raw audio file (default: off per PRD "可选").
    public var saveAudio = true
    /// Name of the written audio file inside the Reflections directory, or nil when not saving audio.
    public var audioFileName: String?

    public init() {}

    public var hasTranscript: Bool {
        !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public mutating func apply(_ action: VoiceReflectionAction) {
        switch action {
        case .requestRecording where phase == .idle || phase == .cancelled || phase == .failed || phase == .transcriptReady:
            phase = .requestingPermission
            failureMessage = nil
        case .permissionResolved(.authorized) where phase == .requestingPermission:
            break
        case .permissionResolved(.denied) where phase == .requestingPermission:
            fail("没有语音识别权限。你仍然可以输入文字。")
        case .permissionResolved(.restricted) where phase == .requestingPermission:
            fail("此设备限制了语音识别。你仍然可以输入文字。")
        case .permissionResolved(.notDetermined):
            break
        case .recordingStarted where phase == .requestingPermission:
            phase = .recording
            transcript = ""
        case .transcription(.partial(let text)) where phase == .recording || phase == .stopping:
            transcript = text
        case .transcription(.final(let text)) where phase == .recording || phase == .stopping:
            transcript = text
            phase = hasTranscript ? .transcriptReady : .idle
        case .stopRequested where phase == .recording:
            phase = .stopping
        case .cancelled:
            phase = .cancelled
            transcript = ""
            failureMessage = nil
        case .failed(let message):
            fail(message)
        case .reset:
            self = Self()
        default:
            break
        }
    }

    private mutating func fail(_ message: String) {
        phase = .failed
        failureMessage = message
    }
}

@MainActor
public protocol LiveTranscriptionProvider: AnyObject {
    var authorizationStatus: SpeechAuthorization { get }
    var isAvailable: Bool { get }
    func requestAuthorization() async -> SpeechAuthorization
    func start(configuration: SpeechRecognitionConfiguration) throws -> AsyncThrowingStream<TranscriptionEvent, Error>
    func stop()
    func cancel()
    /// File extension the recorder should use for the saved audio destination.
    /// The system provider uses AAC/M4A.
    var preferredAudioFileExtension: String { get }
    /// Best-effort audio persistence hook. Called before `start` with the destination
    /// file URL (or nil to disable). Default implementation is a no-op.
    func prepareAudioRecording(at url: URL?) throws
}

@MainActor
public extension LiveTranscriptionProvider {
    func prepareAudioRecording(at url: URL?) throws {}
    var preferredAudioFileExtension: String { "m4a" }
}

public enum SpeechProviderError: LocalizedError, Equatable, Sendable {
    case recognitionUnavailable
    case recordingCouldNotStart(String)
    /// The locale's on-device model is not installed, and recognition is
    /// configured to stay on the device.
    case onDeviceModelUnavailable(String)

    /// The dictation service reports a missing on-device asset as
    /// `kAFAssistantErrorDomain` code 1101 — which, raw, tells the user nothing.
    public static let assistantErrorDomain = "kAFAssistantErrorDomain"
    public static let missingOnDeviceAssetCode = 1101

    /// Classifies an error that reached us at recognition time.
    ///
    /// `SpeechRecognitionAvailability` catches the common case before starting,
    /// but `supportsOnDeviceRecognition` can report `true` while the asset is
    /// actually missing, so this is the net underneath it.
    public static func from(
        _ error: Error,
        configuration: SpeechRecognitionConfiguration
    ) -> SpeechProviderError {
        let nsError = error as NSError
        // Only blame a missing model when on-device was actually required.
        // Otherwise a failure that had a server path available would be reported
        // as an on-device problem, sending the user to fix the wrong thing.
        if configuration.requiresOnDeviceRecognition,
           nsError.domain == assistantErrorDomain,
           nsError.code == missingOnDeviceAssetCode {
            return .onDeviceModelUnavailable(configuration.localeIdentifier)
        }
        return .recordingCouldNotStart(error.localizedDescription)
    }

    public var errorDescription: String? {
        switch self {
        case .recognitionUnavailable:
            "当前无法使用语音识别。你仍然可以输入文字。"
        case .recordingCouldNotStart(let reason):
            "无法开始录音：\(reason)"
        case .onDeviceModelUnavailable(let localeIdentifier):
            // Deliberately does not offer to fall back: uploading the audio is
            // the thing this configuration exists to avoid. The hint matters
            // because iOS fetches on-device models in the background; without
            // it the user would have no idea there is anything to wait for.
            """
            本机还没有「\(localeIdentifier)」的本地识别模型，所以无法转写，音频不会上传。\
            保持联网并充电一段时间，系统会自动下载模型；也可以在「设置 → 通用 → 键盘 → 听写」\
            中开启该语言的听写来触发下载。你仍然可以输入文字。
            """
        }
    }
}

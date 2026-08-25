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

    public init() {}

    public var hasTranscript: Bool {
        !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public mutating func apply(_ action: VoiceReflectionAction) {
        switch action {
        case .requestRecording where phase == .idle || phase == .cancelled || phase == .failed:
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
    func start(localeIdentifier: String?) throws -> AsyncThrowingStream<TranscriptionEvent, Error>
    func stop()
    func cancel()
}

public enum SpeechProviderError: LocalizedError, Equatable, Sendable {
    case recognitionUnavailable
    case recordingCouldNotStart(String)

    public var errorDescription: String? {
        switch self {
        case .recognitionUnavailable:
            "当前无法使用语音识别。你仍然可以输入文字。"
        case .recordingCouldNotStart(let reason):
            "无法开始录音：\(reason)"
        }
    }
}

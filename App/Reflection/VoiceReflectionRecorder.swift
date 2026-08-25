import Observation
import SpeechCore
import SwiftUI

@MainActor @Observable
final class VoiceReflectionRecorder {
    private let provider: any LiveTranscriptionProvider
    private var streamTask: Task<Void, Never>?

    private(set) var state = VoiceReflectionState()

    init(provider: (any LiveTranscriptionProvider)? = nil) {
        self.provider = provider ?? SystemSpeechTranscriptionProvider()
    }

    var latestTranscript: String { state.transcript }
    var isRecording: Bool { state.phase == .recording || state.phase == .stopping }

    func start() async {
        guard !isRecording else { return }
        state.apply(.requestRecording)
        let permission = provider.authorizationStatus == .notDetermined
            ? await provider.requestAuthorization()
            : provider.authorizationStatus
        state.apply(.permissionResolved(permission))
        guard permission == .authorized else { return }
        guard provider.isAvailable else {
            state.apply(.failed(SpeechProviderError.recognitionUnavailable.localizedDescription))
            return
        }

        do {
            let stream = try provider.start(localeIdentifier: nil)
            state.apply(.recordingStarted)
            streamTask = Task { [weak self] in
                do {
                    for try await event in stream {
                        guard !Task.isCancelled else { return }
                        self?.state.apply(.transcription(event))
                    }
                    if self?.state.phase == .stopping, self?.state.hasTranscript == true {
                        self?.state.apply(.transcription(.final(self?.state.transcript ?? "")))
                    }
                } catch is CancellationError {
                    // Explicit cancellation is a normal state and is applied by cancel().
                } catch {
                    self?.state.apply(.failed(error.localizedDescription))
                }
            }
        } catch {
            state.apply(.failed(error.localizedDescription))
        }
    }

    func stop() {
        guard state.phase == .recording else { return }
        state.apply(.stopRequested)
        provider.stop()
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        provider.cancel()
        state.apply(.cancelled)
    }
}

struct VoiceReflectionControls: View {
    @Binding var editableText: String
    @State private var recorder = VoiceReflectionRecorder()
    @State private var textBeforeRecording = ""

    var body: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
            HStack(spacing: ElsepageTheme.Spacing.small) {
                Button {
                    if recorder.isRecording {
                        recorder.stop()
                    } else {
                        textBeforeRecording = editableText
                        Task { await recorder.start() }
                    }
                } label: {
                    Label(recorder.isRecording ? "结束录音" : "语音输入", systemImage: recorder.isRecording ? "stop.fill" : "mic.fill")
                }
                .buttonStyle(.borderedProminent)

                if recorder.isRecording {
                    Button("取消", role: .cancel) { recorder.cancel() }
                        .buttonStyle(.bordered)
                }
            }
            .disabled(recorder.state.phase == .requestingPermission)

            if recorder.state.phase == .requestingPermission {
                ProgressView("正在请求权限…")
                    .font(.footnote)
            } else if let failure = recorder.state.failureMessage {
                Text(failure).font(.footnote).foregroundStyle(.secondary)
            } else if recorder.isRecording {
                Text("正在转写…结束后可以继续编辑文字。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: recorder.latestTranscript) { _, transcript in
            let prefix = textBeforeRecording.trimmingCharacters(in: .whitespacesAndNewlines)
            editableText = transcript.isEmpty ? textBeforeRecording : [prefix, transcript].filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        .onDisappear { recorder.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("语音感想")
    }
}

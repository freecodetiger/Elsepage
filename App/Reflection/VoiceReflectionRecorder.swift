import Observation
import SpeechCore
import SwiftUI
import UIKit

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
    var saveAudio: Bool {
        get { state.saveAudio }
        set { state.saveAudio = newValue }
    }

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
            if state.saveAudio, let url = Self.audioDestinationURL() {
                try provider.prepareAudioRecording(at: url)
                state.audioFileName = url.lastPathComponent
            } else {
                try provider.prepareAudioRecording(at: nil)
                state.audioFileName = nil
            }
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
            discardAudioFile()
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
        discardAudioFile()
    }

    /// Deletes the audio file for the current recording and clears the reference.
    private func discardAudioFile() {
        guard let name = state.audioFileName else { return }
        try? FileManager.default.removeItem(at: Self.audioDirectory().appendingPathComponent(name))
        state.audioFileName = nil
    }

    private static func audioDirectory() -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Reflections", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func audioDestinationURL() -> URL? {
        let name = "\(UUID().uuidString.lowercased())-\(Int(Date().timeIntervalSince1970)).caf"
        return audioDirectory().appendingPathComponent(name)
    }
}

struct VoiceReflectionControls: View {
    @Binding var editableText: String
    @Binding var audioFileName: String?
    var onVoiceTranscript: () -> Void = {}
    @State private var recorder = VoiceReflectionRecorder()
    @State private var textBeforeRecording = ""
    @State private var didLongPress = false

    var body: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
            HStack(spacing: ElsepageTheme.Spacing.small) {
                Button {
                    if didLongPress {
                        didLongPress = false
                        return
                    }
                    if recorder.isRecording {
                        recorder.stop()
                    } else {
                        beginRecording()
                    }
                } label: {
                    Label(recorder.isRecording ? "结束录音" : "语音输入", systemImage: recorder.isRecording ? "stop.fill" : "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.3)
                        .onChanged { _ in
                            didLongPress = true
                            haptic()
                            if !recorder.isRecording {
                                beginRecording()
                            }
                        }
                        .onEnded { _ in
                            haptic()
                            if recorder.isRecording {
                                recorder.stop()
                            }
                        }
                )

                if recorder.isRecording {
                    Button("取消", role: .cancel) { recorder.cancel() }
                        .buttonStyle(.bordered)
                }

                Spacer()

                Toggle("保存音频", isOn: Binding(
                    get: { recorder.saveAudio },
                    set: { recorder.saveAudio = $0 }
                ))
                .font(.footnote)
                .toggleStyle(.switch)
                .accessibilityLabel("保存这段音频")
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
            if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onVoiceTranscript()
            }
        }
        .onChange(of: recorder.state.audioFileName) { _, name in
            audioFileName = name
        }
        .onDisappear { recorder.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("语音感想")
    }

    private func beginRecording() {
        textBeforeRecording = editableText
        Task { await recorder.start() }
    }

    private func haptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

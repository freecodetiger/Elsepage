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
            if state.saveAudio, let url = audioDestinationURL() {
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

    private func audioDestinationURL() -> URL? {
        let name = "\(UUID().uuidString.lowercased())-\(Int(Date().timeIntervalSince1970)).\(provider.preferredAudioFileExtension)"
        return Self.audioDirectory().appendingPathComponent(name)
    }
}

struct VoiceReflectionControls: View {
    @Binding var editableText: String
    @Binding var audioFileName: String?
    var canPolish = false
    var onPolish: (() async -> Void)? = nil
    var onVoiceTranscript: () -> Void = {}
    @State private var recorder = VoiceReflectionRecorder()
    @State private var textBeforeRecording = ""
    @State private var pressTask: Task<Void, Never>?
    @State private var isHoldingLongPress = false
    @State private var isPolishing = false

    var body: some View {
        VStack(spacing: ElsepageTheme.Spacing.medium) {
            statusLine
            micButton
            HStack(spacing: 12) {
                Toggle("保存音频", isOn: Binding(
                    get: { recorder.saveAudio },
                    set: { recorder.saveAudio = $0 }
                ))
                .font(.caption)
                .toggleStyle(.switch)
                .accessibilityLabel("保存这段音频")
                Spacer()
                if canPolish, !editableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        Task {
                            isPolishing = true
                            await onPolish?()
                            isPolishing = false
                        }
                    } label: {
                        if isPolishing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("一键润色", systemImage: "wand.and.stars")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isPolishing)
                }
            }
            .disabled(recorder.state.phase == .requestingPermission)
        }
        .frame(maxWidth: .infinity)
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

    @ViewBuilder private var statusLine: some View {
        if recorder.state.phase == .requestingPermission {
            ProgressView("正在请求权限…")
                .font(.footnote)
        } else if let failure = recorder.state.failureMessage {
            Text(failure).font(.footnote).foregroundStyle(.secondary)
        } else if recorder.isRecording {
            Text("正在转写…点击或松手结束")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if recorder.state.hasTranscript {
            Text("已转写，可继续编辑或润色")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Prominent bottom-center mic button. Both default interactions work:
    /// tap to start / tap to stop, and hold to start / release to stop.
    private var micButton: some View {
        ZStack {
            Circle()
                .fill(recorder.isRecording ? Color.red.opacity(0.12) : Color.elsepageAccent.opacity(0.10))
                .frame(width: 76, height: 76)
                .overlay(
                    Circle().strokeBorder(recorder.isRecording ? Color.red : Color.elsepageAccent, lineWidth: 2)
                )
            Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: 30))
                .foregroundStyle(recorder.isRecording ? Color.red : Color.elsepageAccent)
        }
        .scaleEffect(recorder.isRecording ? 1.1 : 1.0)
        .animation(.snappy(duration: 0.2), value: recorder.isRecording)
        .contentShape(Circle())
        .accessibilityLabel(recorder.isRecording ? "结束录音" : "开始语音输入")
        .gesture(recordingGesture)
    }

    private var recordingGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // A deliberate scroll that starts on the button cancels the pending press.
                guard abs(value.translation.width) < 20, abs(value.translation.height) < 20 else {
                    pressTask?.cancel()
                    pressTask = nil
                    return
                }
                guard pressTask == nil else { return }
                pressTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    isHoldingLongPress = true
                    haptic()
                    if !recorder.isRecording {
                        beginRecording()
                    }
                }
            }
            .onEnded { _ in
                let wasLongPress = isHoldingLongPress
                pressTask?.cancel()
                pressTask = nil
                isHoldingLongPress = false
                if wasLongPress {
                    if recorder.isRecording { recorder.stop() }
                    haptic()
                } else if recorder.isRecording {
                    recorder.stop()
                } else {
                    beginRecording()
                }
            }
    }

    private func beginRecording() {
        textBeforeRecording = editableText
        Task { await recorder.start() }
    }

    private func haptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
